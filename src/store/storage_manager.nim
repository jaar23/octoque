import db_connector/db_sqlite
import std/[os, strformat, times, strutils], options
import octolog, qmessage, threadpool


type
  StorageOps* = enum
    QUEUE, CONSUMED, CLEANUP
  StorageState* = enum
    RUNNING, STOPPING, STOP, DISABLED
  Parcel* = object
    messageId: int
    topic: string
    qmessage: Option[QMessage]
    operation: StorageOps
  TopicStorage = object
    topic: string
    db: DbConn
  StorageManager* = object
    topicStorages: seq[ref TopicStorage]
    state: StorageState
  StorageError = object of CatchableError
  ParcelError = object of CatchableError

var storageChannel: Channel[Parcel]

proc topicStorages*(sm: ref StorageManager): seq[
    ref TopicStorage] = sm.topicStorages

proc qmessage*(parcel: ref Parcel): Option[QMessage] = parcel.qmessage

proc operation*(parcel: ref Parcel): StorageOps = parcel.operation

proc messageId*(parcel: ref Parcel): int = parcel.messageId

proc topic*(parcel: ref Parcel): string = parcel.topic

proc qmessage*(parcel: Parcel): Option[QMessage] = parcel.qmessage

proc operation*(parcel: Parcel): StorageOps = parcel.operation

proc messageId*(parcel: Parcel): int = parcel.messageId

proc topic*(parcel: Parcel): string = parcel.topic

proc topic*(topicStore: ref TopicStorage): string = topicStore.topic

proc db*(topicStore: ref TopicStorage): DbConn = topicStore.db

proc newParcel*(messageId: int, topic: string, qmessage: QMessage,
    operation: StorageOps): Parcel =
  var parcel = Parcel(messageId: messageId, topic: topic, qmessage: some(
      qmessage), operation: operation)
  return parcel


proc newParcel*(messageId: int, topic: string, operation: StorageOps): Parcel =
  var parcel = Parcel(messageId: messageId, topic: topic, qmessage: none(
      QMessage), operation: operation)
  return parcel

proc findTopicStore (sm: ref StorageManager, topic: string): Option[
    ref TopicStorage] =
  for ts in sm.topicStorages:
    if ts.topic == topic:
      result = some(ts)
      break

# +------------+----------+
# | column     | type     |
# |------------|----------|
# | id         | int      |
# | data       | text     |
# | queuedDt   | datetime |
# | consumedDt | datetime |
# | b64encoded | int      |
# | client     | varchar  |
# +------------+----------+
#
proc initTopicStorage*(topic: string): ref TopicStorage =
  let storageLocation = "."
  try:
    if not os.fileExists(&"{storageLocation}/{topic}.db"):
      info &"no topic ({topic}) db found"
      let db = open(&"{storageLocation}/{topic}.db", "", "", "")
      db.exec(sql"DROP TABLE IF EXISTS queue")
      db.exec(sql"""CREATE TABLE queue (
                   id          INTEGER PRIMARY KEY,
                   data        TEXT NOT NULL,
                   queued_dt   DECIMAL(18,10),
                   consumed_dt DECIMAL(18, 10),
                   b64_encoded INTEGER,
                   client      VARCHAR(255)
                )""")
      info &"a new topic {topic} db is created"
      result = (ref TopicStorage)(topic: topic, db: db)
    else:
      let db = open(&"{storageLocation}/{topic}.db", "", "", "")
      result = (ref TopicStorage)(topic: topic, db: db)
  except:
    error getCurrentExceptionMsg()


proc saveQueueData*(topicStore: ref TopicStorage, id: int, data: string, queuedDateTime: float,
                    base64Encoded: bool, clientIp: string): int =
  try:
    let id = topicStore.db.tryInsertId(sql"""INSERT INTO queue 
                                (id, data, queued_dt, consumed_dt, b64_encoded, client)
                                VALUES
                                (?, ?, ?, ?, ?, ?)
                                """, id, data, queuedDateTime, 0.0, base64Encoded, clientIp)
    if id == -1:
      raise newException(StorageError, &"unable to persist queue data, {data}")

    result = id
  except:
    error &"storage manager error, {getCurrentExceptionMsg()}"


proc consumedQueueData*(topicStore: ref TopicStorage, id: int): int =
  try:
    let consumedDt = getTime().toUnixFloat()
    let affRows = topicStore.db.execAffectedRows(
        sql"""UPDATE queue SET consumed_dt = ? WHERE id = ?""", 
        consumedDt, id)
    result = affRows
  except:
    error &"storage manager error, {getCurrentExceptionMsg()}"


proc getAllQueueData*(topicStore: ref TopicStorage): seq[QMessage] =
  try:
    let rows = topicStore.db.getAllRows(sql"""SELECT 
                                        id, data, queue_dt, consumed_dt, b64_encoded 
                                        FROM queue""")
    for row in rows:
      let id: int = parseInt(row[0])
      let data = row[1]
      let queuedDateTime = parseFloat(row[2])
      let consumedDateTime = parseFloat(row[3])
      let base64Encoded = parseBool(row[4])
      result.add(newQMessage(topicStore.topic, id, data, queuedDateTime,
          consumedDateTime, base64Encoded))

  except:
    error &"storage manager error, {getCurrentExceptionMsg()}"


proc getUnconsumedQueueData*(topicStore: ref TopicStorage): seq[QMessage] =
  try:
    let rows = topicStore.db.getAllRows(sql"""SELECT 
                                    id, data, queue_dt, consumed_dt, b64_encoded 
                                    FROM queue
                                    WHERE consumed_dt = 0.0
                                """)
    for row in rows:
      let id: int = parseInt(row[0])
      let data = row[1]
      let queuedDateTime = parseFloat(row[2])
      let consumedDateTime = parseFloat(row[3])
      let base64Encoded = parseBool(row[4])
      result.add(newQMessage(topicStore.topic, id, data, queuedDateTime,
          consumedDateTime, base64Encoded))
  except:
    error &"storage manager error, {getCurrentExceptionMsg()}"


proc cleanUpData*(topicStore: ref TopicStorage): bool =
  try:
    topicStore.db.exec(sql"DROP TABLE IF EXISTS queue")
    topicStore.db.exec(sql"""CREATE TABLE queue (
                     id          INTEGER PRIMARY KEY,
                     data        TEXT NOT NULL,
                     queued_dt   DECIMAL(18,10),
                     consumed_dt DECIMAL(18, 10),
                     b64_encoded INTEGER,
                     client      VARCHAR(255)
                    )""")
    return true
  except:
    error &"storage manager error, {getCurrentExceptionMsg()}"
    return false


proc initStorageManager*(): ref StorageManager =
  try:
    var storageManager = (ref StorageManager)(topicStorages: @[],
        state: RUNNING)
    # for topic in topics:
    #   var ts = initTopicStorage(topic)
    #   storageManager.topicStorages.add(ts)
    return storageManager
  except:
    error &"storage manager error, {getCurrentExceptionMsg()}"


proc addTopic*(sm: ref StorageManager, topics: seq[string]): void =
  try:
    for topic in topics:
      var ts = initTopicStorage(topic)
      sm.topicStorages.add(ts)
      info &"{topic} persistence is managed by storage manager"
    info &"topics in storage manager ({sm.topicStorages.len})"
  except:
    error &"storage manager error, {getCurrentExceptionMsg()}"


proc parcelCollector*(sm: ref StorageManager) {.thread.} =
  info "storage manager is running, parcel collector started"
  try:
    while sm.state != STOP:
      let parcel = storageChannel.recv()
      info &"{parcel}"
      let ts: Option[ref TopicStorage] = sm.findTopicStore(parcel.topic)

      ## topic storage should be initialize during start up
      if ts.isNone:
        raise newException(ParcelError, "topic storage not found")
      if parcel.operation == QUEUE:
        let qmessage = if parcel.qmessage.isSome: parcel.qmessage.get else: raise newException(
            ParcelError, "queue message not found")
        discard ts.get.saveQueueData(qmessage.id(), qmessage.data(),
                                     qmessage.queuedDateTime(),
                                     qmessage.base64Encoded(),
                                     qmessage.clientIp())
        debug &"message is persisted"
      elif parcel.operation == CONSUMED:
        discard ts.get.consumedQueueData(parcel.messageId)
        debug(&"{$parcel.messageId} is consumed")
      elif parcel.operation == CLEANUP:
        debug &"clean up {parcel.topic} persistence"
        let cleaned = ts.get.cleanUpData()
        if not cleaned:
          raise newException(StorageError, "unable to clean up {parcel.topic} persistence")
      else:
        raise newException(ParcelError, "invalid parcel operation")
  except:
    error &"storage manager error, {getCurrentExceptionMsg()}"


proc start*(sm: ref StorageManager): void =
  storageChannel.open()
  spawn sm.parcelCollector()


proc stop*(sm: ref StorageManager): void =
  sm.state = STOPPING
  if storageChannel.peek() > 0:
    info "storage manager persist remaining cache to disk"
  while true:
    if storageChannel.peek() == 0:
      break
  sm.state = STOP
  sleep(1000)
  storageChannel.close()


proc disable*(sm: ref StorageManager): void =
  sm.state = DISABLED
  storageChannel.close()
  info &"storage manager is disabled, octoque running in in-memory mode"


proc sendParcel*(sm: ref StorageManager, parcel: Parcel): void =
  try:
    if sm.state == DISABLED:
      return
    if sm.state != RUNNING:
      raise newException(ParcelError, "storage manager is not running")
    let sent = storageChannel.trySend(parcel)
    if not sent:
      raise newException(ParcelError, &"failed to send parcel {parcel}")
  except:
    error &"storage manager error, {getCurrentExceptionMsg()}"


var manager* = initStorageManager()

export storageManager
