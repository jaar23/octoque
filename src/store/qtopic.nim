import std/[options, net, locks, strformat, enumerate, sequtils, sugar, os]
import subscriber
import uuid4


var
  storeLock: Lock
  subscLock: Lock

type
  ConnectionType* = enum
    BROKER, PUBSUB

  QTopic* = object
    name: string
    qchannel: Channel[string]
    store {.guard: storeLock.}: Channel[string]
    subscriptions {.guard: subscLock.}: seq[ref Subscriber]
    topicConnectionType: ConnectionType
    capacity: int


proc name*(qtopic: ref QTopic): string = qtopic.name

proc connectionType*(qtopic: ref QTopic): ConnectionType = qtopic.topicConnectionType

proc storeData (qtopic: ref QTopic, data: string): void =
  withLock storeLock:
    let sent = qtopic.store.trySend(data)
    if sent:
      echo "message sent: ", sent
    else:
      echo "send failed, retrying..."
      qtopic.qchannel.send(data)
    echo "current store size: " & $qtopic.store.peek()


proc recv*(qtopic: ref QTopic): Option[string] =
  withLock storeLock:
    if qtopic.store.peek() > 0:
      let recvData = qtopic.store.recv()
      return some(recvData)
    else:
      return none(string)
  # let recv = self.channel.tryRecv()
  # if recv.dataAvailable:
  #   return some(recv.msg)
  # else:
  #   return none(string)


proc send*(qtopic: ref QTopic, data: string): void =
  qtopic.qchannel.send(data)


proc clear*(qtopic: ref QTopic): bool =
  withLock storeLock:
    qtopic.store.close()
    qtopic.store.open()
    return qtopic.store.ready()


proc listen*(qtopic: ref QTopic): void {.thread.} =
  echo $getThreadId() & ": " & qtopic.name & " is listening"
  while true:
    let recvData = qtopic.qchannel.recv()
    #echo "recv Data: " & recvData
    qtopic.storeData(recvData)
    echo $getThreadId() & " processed message"

# proc listen* (qtopic: ref QTopic, handler: (socket: Socket, data: string) -> bool): void =
#   echo qtopic.name & " is listening..."
  # while self.channel.peek() > 0:
  #   let recv = self.channel.tryRecv()
  #   if recv.dataAvailable:
  #     echo recv.msg
  # echo self.name, " channel is close"


proc size*(self: ref QTopic): int =
  withLock storeLock:
    return self.store.peek()


proc publish*(qtopic: ref QTopic, data: string): void =
  #var idle = false
  #var lostClient = newSeq[ref Subscriber]()
  withLock subscLock:
    try:
      # let droppedConn = qtopic.subscriptions.filter(s => s.isDisconnected())
      # echo &"droppedConn :{droppedConn.len} == {qtopic.subscriptions.len}" 
      # if droppedConn.len == qtopic.subscriptions.len:
      #   idle = true

      for s in qtopic.subscriptions.filter(s => not s.isDisconnected()):
        # if s.isDisconnected():
        #   idle = true
        #   echo $s
        #   continue
        # else:
        #   echo $s
        #   idle = false
        let pong = s.ping()
        if pong:
          discard s.trySend(&"{data}\r\n")
        else:
          echo &"[{s.threadId}] {$s.connectionId} disconnected....."
          s.close()
          #lostClient.add(s)
        #echo &"is idle: {idle}"
    except:
      echo "failed to send data"
      echo getCurrentExceptionMsg()
    # finally:
    #   return (lostClient, idle)


proc unsubscribe*(qtopic: ref QTopic, subscriber: ref Subscriber): void =
  withLock subscLock:
    var idle = false
    let droppedConn = qtopic.subscriptions.filter(s => s.isDisconnected())
    #echo &"droppedConn :{droppedConn.len} == {qtopic.subscriptions.len}" 
    if droppedConn.len == qtopic.subscriptions.len:
      idle = true
      for (i, s) in enumerate(qtopic.subscriptions):
        if s.isDisconnected():
          echo &"[{subscriber.threadId}] unsubscribe & remove {$subscriber.connectionId}"
          qtopic.subscriptions.delete(i)
    else: 
      for (i, s) in enumerate(qtopic.subscriptions.filter(s => s.isDisconnected())):
        if s.connectionId == subscriber.connectionId:
          echo &"[{subscriber.threadId}] unsubscribe {$subscriber.connectionId}"
          s.close()
          #qtopic.subscriptions.delete(i)
          break
    echo &"[{subscriber.threadId}] exit unsubscribe, remaining: {qtopic.subscriptions.len}"
        #else:
        #echo $s

# proc findSubscriber(qtopic: ref QTopic, connId: uuid4): ref Subscriber =
#   withLock subscLock:
#     for s in qtopic.subscriptions:
#       if s.connectionId == connId:
#         result = s
#         break


proc subscribe*(qtopic: ref QTopic, subscriber: ref Subscriber): void =
  # echo "before"
  # for s in qtopic.subscriptions:
  #   echo "is closed: " & $s.isDisconnected
  #   echo $s.connectionId
  var qsubs: ref Subscriber
  withLock subscLock:
    qtopic.subscriptions.add(subscriber)
    for s in qtopic.subscriptions:
      if s.connectionId == subscriber.connectionId:
        qsubs = s
        break

  try:
    while true:
      # var numOfSubs = 0
      # withLock subscLock:
      #   numOfSubs = qtopic.subscriptions.len
      # if numOfSubs == 0:
      #   break
      # ping the client before send any message
      let pong = qsubs.ping()
      if not pong:
        break
      var numOfData = 0
      var recvData = "\n"
      withLock storeLock:
        numOfData = qtopic.store.peek()
        if numOfData > 0:
           recvData = qtopic.store.recv()
      qtopic.publish(recvData)
      # stop if no more subscription
      #echo &"[{qsubs.threadId}] is idle: {idle}"
      # if idle:
      #   break
      # remove subscriptions if it dropped
      # if droppedConn.len > 0:
      #   for s in droppedConn:
      #     echo "--> from subcribe\n"
      #     s.close()
      #     qtopic.unsubscribe(s)
      #withLock subscLock:
      #numOfConn = qtopic.subscriptions.len
  except:
    echo getCurrentExceptionMsg()
  finally:
    #qsubs.close()
    #qtopic.unsubscribe(subscriber)
    echo &"[{subscriber.threadId}] {$subscriber.connectionId} is exiting pubsub loop...\n"


proc initQTopic*(name: string, capacity: int,
    connType: ConnectionType = BROKER): ref QTopic =
  var qtopic: ref QTopic = (ref QTopic)(name: name)
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
  withLock storeLock:
    qtopic.store.open()
  withLock subscLock:
    qtopic.subscriptions = newSeq[ref Subscriber]()

  return qtopic


