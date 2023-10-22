import options, net, locks, strformat, sequtils, sugar, os
import std/enumerate, std/deques
import subscriber
import uuid4
import threadpool
import octolog
import segfaults

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
    store {.guard: storeLock.}: Deque[string]
    subscriptions {.guard: subscLock.}: seq[ref Subscriber]
    topicConnectionType: ConnectionType
    capacity: int


proc name*(qtopic: ref QTopic): string =
  qtopic.name


proc connectionType*(qtopic: ref QTopic): ConnectionType =
  qtopic.topicConnectionType


proc storeData (qtopic: ref QTopic, data: string): void =
  defer:
    storeCond.signal()
  withLock storeLock:
    if qtopic == nil:
      #debug "!!! waiting qtopic to store new data !!!!"
      storeCond.wait(storeLock)
    qtopic.store.addLast(data)
    debug "store new data into " & qtopic.name


proc recv*(qtopic: ref QTopic): Option[string] =
  defer:
    storeCond.signal()
  if qtopic == nil:
    #debug "!!! waiting qtopic to recv!!!!"
    storeCond.wait(storeLock)
  withLock storeLock:
    if qtopic.store.len == 0:
      return none(string)
    else:
      let recvData = qtopic.store.popFirst()
      return some(recvData)


proc send*(qtopic: ref QTopic, data: string): void =
  debug &"{getThreadId()}.{qtopic.name} send to qchannel"
  qtopic.qchannel.send(data)


proc clear*(qtopic: ref QTopic): bool =
  defer:
    storeCond.signal()
  if qtopic == nil:
    #debug "!!! waiting qtopic to clear msg !!!!"
    storeCond.wait(storeLock)
  info &"{getThreadId()}.{qtopic.name} clear message"
  withLock storeLock:
    qtopic.store.clear()
    return qtopic.store.len == 0


proc listen*(qtopic: ref QTopic): void {.thread.} =
  defer:
    storeCond.signal()
  info &"{getThreadId()}.{qtopic.name} listening"
  while true:
    let recvData = qtopic.qchannel.recv()
    debug $getThreadId() & "." & qtopic.name & " store new message, " & recvData
    if qtopic == nil:
      storeCond.wait(storeLock)
    qtopic.storeData(recvData)


proc size*(self: ref QTopic): int =
  defer:
    storeCond.signal()
  if self == nil:
    #debug "!!! waiting queue topic !!!"
    storeCond.wait(storeLock)
  withLock storeLock:
    debug "store len: " & $self.store.len
    return self.store.len


proc publish*(qtopic: ref QTopic, data: string): void =
  defer:
    storeCond.signal()
  if qtopic == nil:
    #debug "!!!! waiting qtopic to publish !!!"
    storeCond.wait(storeLock)
  info &"{getThreadId()}.{qtopic.name} publish to subscriber"
  withLock subscLock:
    try:
      for s in qtopic.subscriptions.filter(s => not s.isDisconnected()):
        #let pong = s.ping()
        #if pong:
        discard s.trySend(&"{data}\n")
        #else:
        #  s.close()
    except:
      error &"{getThreadId()}.{qtopic.name} failed to send data"
      error getCurrentExceptionMsg()


proc unsubscribe*(qtopic: ref QTopic, subscriber: ref Subscriber): void =
  defer:
    subscCond.signal()
    storeCond.signal()
  if qtopic == nil:
    #debug "!!! waiting qtopic to unsubscribe!!!"
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
    #debug "!!! waiting qtopic to subscribe !!!!"
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
      let pong = qsubs.ping()
      if not pong:
        break
      var recvData = ""
      withLock storeLock:
        if qtopic.store.len == 0:
          sleep(100)
        else:
          recvData = qtopic.store.popFirst()
      #debug "recvData is " & recvData
      if recvData == "":
        sleep(100)
      else:
        withLock subscLock:
          if recvData != "":
            #subscCond.wait(subscLock)
            for sbr in qtopic.subscriptions:
              sbr.push(recvData)
            subscCond.signal()
  except:
    error &"{getThreadId()}.{qtopic.name} {getCurrentExceptionMsg()}"
  finally:
    info &"{getThreadId()}.{qtopic.name} {subscriber.runnerId()} is exiting pubsub loop"


proc initQTopic*(name: string, capacity: int,
    connType: ConnectionType = BROKER): ref QTopic =
  var qtopic: ref QTopic = (ref QTopic)(name: name, capacity: capacity)
  qtopic.qchannel.open()
  initCond storeCond
  initLock storeLock
  initCond subscCond
  initLock subscLock
  withLock storeLock:
    qtopic.topicConnectionType = connType
    qtopic.store = initDeque[string]()
  withLock subscLock:
    qtopic.subscriptions = newSeq[ref Subscriber]()
  return qtopic

proc initQTopicUnlimited*(name: string, connType: ConnectionType = BROKER): ref QTopic =
  var qtopic: ref QTopic = (ref QTopic)(name: name)
  qtopic.topicConnectionType = connType
  qtopic.qchannel.open()
  initCond storeCond
  initLock storeLock
  initCond subscCond
  initLock subscLock
  withLock storeLock:
    qtopic.store = initDeque[string]()
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

