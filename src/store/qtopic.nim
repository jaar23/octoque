import std/options, std/net, std/locks, strformat, threadpool, os
import subscriber
import sequtils
import std/enumerate
import sugar
#import topic

var
  lock: Lock

type
  ConnectionType* = enum
    BROKER, PUBSUB

  QTopic* = object
    name: string
    qchannel: Channel[string]
    store {.guard: lock.}: Channel[string]
    subscriptions: seq[ref Subscriber]
    topicConnectionType: ConnectionType
    capacity: int


proc name*(qtopic: ref QTopic): string = qtopic.name

proc connectionType*(qtopic: ref QTopic): ConnectionType = qtopic.topicConnectionType

proc storeData (qtopic: ref QTopic, data: string): void =
  withLock lock:
    let sent = qtopic.store.trySend(data)
    if sent:
      echo "message sent: ", sent
    else:
      echo "send failed, retrying..."
      qtopic.qchannel.send(data)
    echo "current store size: " & $qtopic.store.peek()


proc recv*(qtopic: ref QTopic): Option[string] =
  withLock lock:
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
  withLock lock:
    qtopic.store.close()
    qtopic.store.open()
    return qtopic.store.ready()


proc listen*(qtopic: ref QTopic): void {.thread.} =
  echo $getThreadId() & ": " & qtopic.name & " is listening"
  while true:
  # while qtopic.qchannel.peek() > 0:
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
  withLock lock:
    return self.store.peek()


proc publish*(qtopic: ref QTopic, data: string): (seq[ref Subscriber], bool) =
  var idle = false
  var lostClient = newSeq[ref Subscriber]()
  try:
    for s in qtopic.subscriptions:
      if s.isDisconnected():
        idle = true
        break
      else:
        idle = false
      let pong = s.ping()
      if pong:
        if data.len > 0:
          echo "send data..."
          let sent = s.trySend(&"{data}\r\n")
          echo sent
        else:
          echo "no data"
      else:
        echo "disconnected....."
        lostClient.add(s)
  except:
    echo "failed to send data"
    echo getCurrentExceptionMsg()
  finally:
    return (lostClient, idle)


proc unsubscribe*(qtopic: ref QTopic, subscriber: ref Subscriber): void =
  echo "unsubscribe " & $subscriber.connectionId
  for (i, s) in enumerate(qtopic.subscriptions):
    if s.connectionId == subscriber.connectionId:
      qtopic.subscriptions.delete(i)
      break


proc subscribe*(qtopic: ref QTopic, subscriber: ref Subscriber): void =
#proc subscribe*(qtopic: ref QTopic, subscriber: Socket): void =
 #echo "new subscriber: " & $subscriber
  qtopic.subscriptions.add(subscriber)
  try:
    while true:
      var numOfData = 0
      withLock lock:
        numOfData = qtopic.store.peek()
      echo "num of data\t" & $numOfData
      var recvData = "\n"
      if numOfData > 0:
        #echo "send num of data"
        withLock lock:
          recvData = qtopic.store.recv()
      let (droppedConn, idle) = qtopic.publish(recvData)
      if idle:
        break
      if droppedConn.len > 0:
        for s in droppedConn:
          qtopic.unsubscribe(s)

      sleep(1000)
    #subscriber.close()
  except:
    echo getCurrentExceptionMsg()
  finally:
    subscriber.close()
    qtopic.unsubscribe(subscriber)
    echo "exiting pubsub loop..."


#  spawn qtopic.pingClient(subscriber)
  #for s in qtopic.subscriptions:
  #  echo $s
  #  discard s.send("0")


# proc publish*(qtopic: ref QTopic, data: string) =
#   echo "new message to publish"
#   for s in qtopic.subscriptions:
#     if data.len > 0: 
#       var respStr = &"status ok\r\ncode 0\r\nmessage publish to subscriber\r\n{data}"
#       echo respStr
#       #discard s.send(respStr)
#       #discard s.send(respStr)
#       #discard s.send(respStr)
#
#       #qtopic.qchannel.send(respStr)
#     #await s.send(data)


# proc pblisten*(qtopic: ref QTopic): Future[void] {.thread.} =
#   echo $getThreadId() & ": " & qtopic.name & " is listening for pubsub connection"
#   while true:
#     let recvData = qtopic.qchannel.recv()
#     echo "[qtopic] --->" & recvData
#     if recvData.len > 0:
#       echo "receiving some data from publisher..."
#       #qtopic.publish(recvData)
#       echo "published"


proc initQTopic*(name: string, capacity: int,
    connType: ConnectionType = BROKER): ref QTopic =
  withLock lock:
    var qtopic: ref QTopic = (ref QTopic)(name: name)
    qtopic.topicConnectionType = connType
    qtopic.store.open(capacity)
    return qtopic


proc initQTopicUnlimited*(name: string, connType: ConnectionType = BROKER): ref QTopic =
  var qtopic: ref QTopic = (ref QTopic)(name: name)
  qtopic.topicConnectionType = connType
  qtopic.qchannel.open()
  withLock lock:
    qtopic.store.open()
  return qtopic


# proc testClosure* (total: int, handler: (x: int, y: int) -> int): void =
#   var ix = 3
#   var iy = 2
#   var itotal = handler(ix, iy)
#   echo total, "==", itotal
