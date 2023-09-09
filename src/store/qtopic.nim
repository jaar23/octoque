import options, net, locks, strformat, sequtils, sugar
import std/enumerate
import subscriber
import uuid4
import threadpool
import octolog

var
  storeLock: Lock
  subscLock: Lock

type
  ConnectionType* = enum
    BROKER, PUBSUB

  QTopic* = object
    name: string
    qchannel: Channel[string]
    retryStore: Channel[string]
    store {.guard: storeLock.}: Channel[string]
    subscriptions {.guard: subscLock.}: seq[ref Subscriber]
    topicConnectionType: ConnectionType
    capacity: int


proc name*(qtopic: ref QTopic): string =
  qtopic.name


proc connectionType*(qtopic: ref QTopic): ConnectionType =
  qtopic.topicConnectionType


proc storeData (qtopic: ref QTopic, data: string): void =
  #debug $getThreadId() & "." & qtopic.name & "store new message, " & data
  withLock storeLock:
    let sent = qtopic.store.trySend(data)
    if not sent:
      error &"{getThreadId()}.{qtopic.name} send failed, retrying"
      error &"{getThreadId()}.{qtopic.name} current store size: {qtopic.store.peek()}"
      qtopic.retryStore.send(data)


proc recv*(qtopic: ref QTopic): Option[string] =
  withLock storeLock:
    if qtopic.store.peek() > 0:
      let recvData = qtopic.store.recv()
      return some(recvData)
    else:
      return none(string)


proc send*(qtopic: ref QTopic, data: string): void =
  debug &"{getThreadId()}.{qtopic.name} send to qchannel"
  qtopic.qchannel.send(data)


proc clear*(qtopic: ref QTopic): bool =
  info &"{getThreadId()}.{qtopic.name} clear message"
  withLock storeLock:
    qtopic.store.close()
    qtopic.store.open()
    return qtopic.store.ready()


proc listen*(qtopic: ref QTopic): void {.thread.} =
  info &"{getThreadId()}.{qtopic.name} listening"
  while true:
    let recvData = qtopic.qchannel.recv()
    debug $getThreadId() & "." & qtopic.name & "store new message, " & recvData
    spawn qtopic.storeData(recvData)
   

proc size*(self: ref QTopic): int =
  withLock storeLock:
    return self.store.peek()


proc publish*(qtopic: ref QTopic, data: string): void =
  info &"{getThreadId()}.{qtopic.name} publish to subscriber"
  withLock subscLock:
    try:
      for s in qtopic.subscriptions.filter(s => not s.isDisconnected()):
        let pong = s.ping()
        if pong:
          discard s.trySend(&"{data}\r\n")
        else:
          s.close()
    except:
      error &"{getThreadId()}.{qtopic.name} failed to send data"
      error getCurrentExceptionMsg()


proc unsubscribe*(qtopic: ref QTopic, subscriber: ref Subscriber): void =
  withLock subscLock:
    var idle = false
    let droppedConn = qtopic.subscriptions.filter(s => s.isDisconnected())
    if droppedConn.len == qtopic.subscriptions.len:
      idle = true
      for (i, s) in enumerate(qtopic.subscriptions):
        if s.isDisconnected():
          info &"{subscriber.runnerId()} unsubscribe & remove from subscriptions"
          qtopic.subscriptions.delete(i)
    else:
      for (i, s) in enumerate(qtopic.subscriptions.filter(s => s.isDisconnected())):
        if s.connectionId == subscriber.connectionId:
          info &"{subscriber.runnerId()} unsubscribe from subscriptions"
          s.close()
          break
    info &"{subscriber.runnerId()} exit unsubscribe, remaining: {qtopic.subscriptions.len}"


proc subscribe*(qtopic: ref QTopic, subscriber: ref Subscriber): void =
  var qsubs: ref Subscriber
  withLock subscLock:
    qtopic.subscriptions.add(subscriber)
    for s in qtopic.subscriptions:
      if s.connectionId == subscriber.connectionId:
        qsubs = s
        break
    info &"{getThreadId()}.{qtopic.name} subscriptions size: {qtopic.subscriptions.len}"
  try:
    spawn qsubs.run()
    while true:
      let pong = qsubs.ping()
      if not pong:
        break
      var numOfData = 0
      var recvData = ""
      withLock storeLock:
        numOfData = qtopic.store.peek()
        if numOfData > 0:
          recvData = qtopic.store.recv()

      withLock subscLock:
        if recvData != "":
          # &"\n\n{getThreadId()} before push: {qtopic.subscriptions.len}"
          for sbr in qtopic.subscriptions:
            sbr.push(recvData)
  except:
    error &"{getThreadId()}.{qtopic.name} {getCurrentExceptionMsg()}"
  finally:
    info &"{getThreadId()}.{qtopic.name} {subscriber.runnerId()} is exiting pubsub loop"


proc initQTopic*(name: string, capacity: int,
    connType: ConnectionType = BROKER): ref QTopic =
  var qtopic: ref QTopic = (ref QTopic)(name: name)
  qtopic.qchannel.open()
  qtopic.retryStore.open()
  withLock storeLock:
    qtopic.topicConnectionType = connType
    qtopic.store.open(capacity)
  withLock subscLock:
    qtopic.subscriptions = newSeq[ref Subscriber]()
  return qtopic

proc initQTopicUnlimited*(name: string, connType: ConnectionType = BROKER): ref QTopic =
  var qtopic: ref QTopic = (ref QTopic)(name: name)
  qtopic.topicConnectionType = connType
  qtopic.qchannel.open()
  qtopic.retryStore.open()
  withLock storeLock:
    qtopic.store.open()
  withLock subscLock:
    qtopic.subscriptions = newSeq[ref Subscriber]()
  return qtopic


