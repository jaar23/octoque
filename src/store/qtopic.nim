import options, net, locks, strformat, sequtils, sugar, os, threadpool
import std/enumerate, std/deques, std/times, std/base64
import uuid4, octolog, qmessage, subscriber, storage_manager


var
  storeLock: Lock
  storeCond: Cond
  subscLock: Lock
  subscCond: Cond

type
  ConnectionType* = enum
    BROKER, PUBSUB

  QTopic* = object
    name: string
    qchannel: Channel[string]
    capacity: int
    qfile: File
    deqfile: File
    base64Encoded: bool
    subscriptions {.guard: subscLock.}: seq[ref Subscriber]
    topicConnectionType: ConnectionType
    store {.guard: storeLock.}: Deque[ref QMessage]
    #storageManager: ref StorageManager
   

proc name*(qtopic: ref QTopic): string =
  qtopic.name


proc connectionType*(qtopic: ref QTopic): ConnectionType =
  qtopic.topicConnectionType


proc deqlog*(qtopic: ref QTopic, messageId: string): void =
  qtopic.deqfile.write(&"ACK {$messageId} {$getTime().toUnixFloat()}\r\n")
  qtopic.deqfile.flushFile()


proc enqlog*(qtopic: ref QTopic, line: string): void =
  qtopic.qfile.write(line)
  qtopic.qfile.flushFile()


proc storeData (qtopic: ref QTopic, data: string): void =
  defer:
    storeCond.signal()
  withLock storeLock:
    if qtopic == nil:
      storeCond.wait(storeLock)
    let queueDateTime = getTime().toUnixFloat()
    # if qtopic.connectionType != PUBSUB:
      # let id = qtopic.storageManager.saveQueueData(data, queueDateTime,
      #     qtopic.base64Encoded, "")
    let id = queueDateTime.toInt()
    let qmsg = newQMessageRef(id, qtopic.name, data, queueDateTime,
        qtopic.base64Encoded)
    {.cast(gcsafe).}:
      let parcel = newParcel(id, qtopic.name, qmsg[], QUEUE)
      storageManager.manager.sendParcel(parcel)
    qtopic.store.addLast(qmsg)
    # else:
    #  let qmsg = newQMessageRef(0, qtopic.name, data, queueDateTime,
    #      qtopic.base64Encoded)
    #  qtopic.store.addLast(qmsg)
    #  AOF
    # qtopic.enqlog(qmsg.toJSON() & "\r\n")
    debug "store new data into " & qtopic.name


proc recv*(qtopic: ref QTopic): Option[string] =
  defer:
    storeCond.signal()
  if qtopic == nil:
    storeCond.wait(storeLock)
  withLock storeLock:
    if qtopic.store.len == 0:
      return none(string)
    else:
      try:
        let recvMsg = qtopic.store.popFirst()
        return some(recvMsg.deqMessage())
      except:
        error &"{getThreadId()}.{qtopic.name} failed to dequeue"
        error getCurrentExceptionMsg()


proc send*(qtopic: ref QTopic, data: string): void =
  debug &"{getThreadId()}.{qtopic.name} send to qchannel"
  debug &"data size: {data.len}"
  try:
    if qtopic.base64Encoded:
      qtopic.qchannel.send(encode(data))
    else:
      qtopic.qchannel.send(data)
  except:
    error &"{getThreadId()}.{qtopic.name} failed to enqueue"
    error getCurrentExceptionMsg()


proc clear*(qtopic: ref QTopic): bool =
  defer:
    storeCond.signal()
  if qtopic == nil:
    storeCond.wait(storeLock)
  info &"{getThreadId()}.{qtopic.name} clear message"
  withLock storeLock:
    qtopic.store.clear()
    return qtopic.store.len == 0


proc commit*(qtopic: ref QTopic): void =
  qtopic.qfile.flushFile()


proc delivered*(qtopic: ref QTopic, messageId: int): void =
  # AOR
  # qtopic.deqlog(messageId)
  debug "update queue data consumption status"
  {.cast(gcsafe).}:
    let parcel = newParcel(messageId, qtopic.name, CONSUMED)
    storageManager.manager.sendParcel(parcel)
  # let updatedRows = qtopic.storageManager.consumedQueueData(messageId)
  # debug &"{updatedRows} is consumed"


proc listen*(qtopic: ref QTopic): void {.thread.} =
  defer:
    storeCond.signal()
  info &"{getThreadId()}.{qtopic.name} listening"
  while true:
    let recvData = qtopic.qchannel.recv()
    debug $getThreadId() & "." & qtopic.name & " store new message, " & $recvData.len
    if qtopic == nil:
      storeCond.wait(storeLock)
    qtopic.storeData(recvData)


proc size*(self: ref QTopic): int =
  defer:
    storeCond.signal()
  if self == nil:
    storeCond.wait(storeLock)
  withLock storeLock:
    debug "store len: " & $self.store.len
    return self.store.len


## currently not in use
## check out subscribe function
proc publish*(qtopic: ref QTopic, data: string, clientIp: string): void =
  defer:
    storeCond.signal()
  if qtopic == nil:
    storeCond.wait(storeLock)
  info &"{getThreadId()}.{qtopic.name} publish to subscriber"
  withLock subscLock:
    try:
      for s in qtopic.subscriptions.filter(s => not s.isDisconnected()):
        let queuedDateTime = getTime().toUnixFloat()
        let id = queuedDateTime.toInt()
        # let id = qtopic.storageManager.saveQueueData(data, queuedDateTime, qtopic.base64Encoded, clientIp)
        let qmsg = newQMessageRef(id, qtopic.name, data, queuedDateTime, qtopic.base64Encoded)
        discard s.trySend(&"{qmsg.toJSON()}\n")
    except:
      error &"{getThreadId()}.{qtopic.name} failed to send data"
      error getCurrentExceptionMsg()


proc unsubscribe*(qtopic: ref QTopic, subscriber: ref Subscriber): void =
  defer:
    subscCond.signal()
    storeCond.signal()
  if qtopic == nil:
    subscCond.wait(subscLock)
    storeCond.wait(storeLock)
  withLock subscLock:
    var idle = false
    let droppedConn = qtopic.subscriptions.filter(s => s.isDisconnected())
    if droppedConn.len == qtopic.subscriptions.len:
      idle = true
      for (i, s) in enumerate(qtopic.subscriptions):
        if s.isDisconnected():
          info &"{subscriber.runnerId()} unsubscribe and remove from subscriptions"
          qtopic.subscriptions.delete(i)
          subscCond.signal()
    else:
      for (i, s) in enumerate(qtopic.subscriptions.filter(s => s.isDisconnected())):
        if s.connectionId == subscriber.connectionId:
          info &"{subscriber.runnerId()} unsubscribe from subscriptions"
          s.close()
          break
    info &"{subscriber.runnerId()} exit unsubscribe, remaining: {qtopic.subscriptions.len}"


proc unsubscribe*(qtopic: ref QTopic, connId: Uuid): void =
  defer:
    subscCond.signal()
    storeCond.signal()
  if qtopic == nil:
    subscCond.wait(subscLock)
    storeCond.wait(storeLock)
  withLock subscLock:
    if qtopic.subscriptions.len == 0:
      return
    for (i, s) in enumerate(qtopic.subscriptions):
      if s.connectionId == connId:
        info(s.runnerId() & "unsubscribe and remove from subscriptions")
        s.close()
        qtopic.subscriptions.delete(i)
        subscCond.signal()
        break


proc subscribe*(qtopic: ref QTopic, subscriber: ref Subscriber): void =
  defer:
    subscCond.signal()
    storeCond.signal()
  if qtopic == nil:
    subscCond.wait(subscLock)
    storeCond.wait(storeLock)
  var qsubs: ref Subscriber
  withLock subscLock:
    qtopic.subscriptions.add(subscriber)
    for s in qtopic.subscriptions:
      if s.connectionId == subscriber.connectionId:
        qsubs = s
        break
    subscCond.signal()
    info &"{getThreadId()}.{qtopic.name} subscriptions size: {qtopic.subscriptions.len}"

  try:
    spawn qsubs.run()
    #discard qsubs.ping()
    sleep(100)
    while true:
      ## client should response to ping
      ## in order to notify server they are still connected
      let pong = qsubs.ping()
      if not pong:
        break
      # var recvData = ""
      # var queuedDateTime = 0.0
      # withLock storeLock:
      #   if qtopic.store.len != 0:
      #     let recvMsg = qtopic.store.popFirst()
      #     recvData = recvMsg.data()
      #     queuedDateTime = recvMsg.queuedDateTime()
      # if recvData != "":
      withLock subscLock:
        # if recvData != "":
        #   subscCond.wait(subscLock)
        for sbr in qtopic.subscriptions:
          # let id = qtopic.storageManager.saveQueueData(recvData, queuedDateTime, 
          #                                              qtopic.base64Encoded, sbr.connectionIp)
          # let id = queuedDateTime.toInt()
          # let qmsg = newQMessageRef(id, qtopic.name, recvData, queuedDateTime, 
          #                           qtopic.base64Encoded)
          # let parcel = newParcel(id, qtopic.name, qmsg[], QUEUE)
          # storageManager.manager.sendParcel(parcel)
          withLock storeLock:
            if qtopic.store.len != 0:
              let recvMsg = qtopic.store.popFirst()
              sbr.push(recvMsg.toJSON())
              # let sent = sbr.trySend(recvMsg.toJSON())
              # if not sent:
              #   qtopic.store.addLast(recvMsg)
            storeCond.signal()
        subscCond.signal()
  except:
    error &"{getThreadId()}.{qtopic.name} {getCurrentExceptionMsg()}"
  finally:
    info &"{getThreadId()}.{qtopic.name} {subscriber.runnerId()} is exiting pubsub loop"


proc initQTopic*(name: string, capacity: int,
    connType: ConnectionType = BROKER): ref QTopic =
  var qtopic: ref QTopic = (ref QTopic)(name: name, capacity: capacity)
  qtopic.qchannel.open()
  let queueFileName = &"otq-{name}-enq.log"
  let dequeueFileName = &"otq-{name}-deq.log"
  if not os.fileExists(queueFileName):
    var file = open(queueFileName, fmWrite)
    file.close()
    qtopic.qfile = open(queueFileName, fmAppend)
  else:
    qtopic.qfile = open(queueFileName, fmAppend)

  if not os.fileExists(dequeueFileName):
    var file = open(dequeueFileName, fmWrite)
    file.close()
    qtopic.deqfile = open(dequeueFileName, fmAppend)
  else:
    qtopic.deqfile = open(dequeueFileName, fmAppend)
  #qtopic.storageManager = initStorage(name)
  {.cast(gcsafe).}:
    storageManager.manager.addTopic(@[name])

  initCond storeCond
  initLock storeLock
  initCond subscCond
  initLock subscLock
  withLock storeLock:
    qtopic.topicConnectionType = connType
    qtopic.store = initDeque[ref QMessage]()
  withLock subscLock:
    qtopic.subscriptions = newSeq[ref Subscriber]()
  return qtopic


proc initQTopicUnlimited*(name: string, connType: ConnectionType = BROKER): ref QTopic =
  var qtopic: ref QTopic = (ref QTopic)(name: name)
  qtopic.topicConnectionType = connType
  qtopic.qchannel.open()
  let queueFileName = &"otq-{name}-enq.log"
  let dequeueFileName = &"otq-{name}-deq.log"
  if not os.fileExists(queueFileName):
    var file = open(queueFileName, fmWrite)
    file.close()
    qtopic.qfile = open(queueFileName, fmAppend)
  else:
    qtopic.qfile = open(queueFileName, fmAppend)

  if not os.fileExists(dequeueFileName):
    var file = open(dequeueFileName, fmWrite)
    file.close()
    qtopic.deqfile = open(dequeueFileName, fmAppend)
  else:
    qtopic.deqfile = open(dequeueFileName, fmAppend)
  #qtopic.storageManager = initStorage(name)
  {.cast(gcsafe).}:
    storageManager.manager.addTopic(@[name])

  initCond storeCond
  initLock storeLock
  initCond subscCond
  initLock subscLock
  withLock storeLock:
    qtopic.store = initDeque[ref QMessage]()
  withLock subscLock:
    qtopic.subscriptions = newSeq[ref Subscriber]()
  return qtopic


proc `$`*(qtopic: ref QTopic): string =
  result = "+----------------------------------------------------\n"
  result &= "| Name              : " & qtopic.name & "\n"
  result &= "| Connection Type   : " & $qtopic.connectionType & "\n"
  result &= "| Capacity          : " & $qtopic.capacity & "\n"
  result &= "| Store Size        : " & $qtopic.size() & "\n"
  result &= "+----------------------------------------------------\n"

