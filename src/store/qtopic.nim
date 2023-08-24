import std/options, std/net, std/locks, std/asyncnet, std/asyncdispatch
import subscriber
import topic

var 
  lock: Lock

type 
  ConnectionType* = enum
    BROKER, PUBSUB

  QTopic* = object of Topic
    qchannel: Channel[string]
    store {.guard: lock}: Channel[string]
    subscriptions: seq[Subscriber]
    topicConnectionType: ConnectionType
    capacity: int


proc name* (qtopic: ref QTopic): string = qtopic.name

proc connectionType* (qtopic: ref QTopic): ConnectionType = qtopic.topicConnectionType

proc storeData (qtopic: ref QTopic, data: string): void = 
  withLock lock:
    let sent = qtopic.store.trySend(data)
    if sent:
      echo "message sent: ", sent
    else:
      echo "send failed, retrying..."
      qtopic.qchannel.send(data)


proc recv* (qtopic: ref QTopic): Option[string] =
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


proc send* (qtopic: ref QTopic, data: string): void =
  qtopic.qchannel.send(data)


proc clear* (qtopic: ref QTopic): bool = 
  withLock lock:
    qtopic.store.close()
    qtopic.store.open()
    return qtopic.store.ready()


proc listen* (qtopic: ref QTopic): void {.thread.} = 
  echo $getThreadId() & ": " & qtopic.name & " is listening"
  while true:
  # while qtopic.qchannel.peek() > 0:
    let recvData = qtopic.readNext()
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


proc size* (self: ref QTopic): int = 
  withLock lock:
    return self.store.peek()
 

proc subscribe* (qtopic: ref QTopic, subscriber: Subscriber): void = 
  echo "new subscriber: " & $subscriber.connectionId
  qtopic.subscriptions.add(subscriber)


proc publish* (qtopic: ref QTopic, data: string) {.async.} =
  for s in qtopic.subscriptions:
    await s.send(data)


proc pblisten* (qtopic: ref QTopic): Future[void] {.thread, async.} =
  echo $getThreadId() & ": " & qtopic.name & " is listening for pubsub connection"
  while true:
    let recvData = qtopic.readNext()
    await qtopic.publish(recvData)
    echo "published"


proc initQTopic* (name: string, capacity: int, connType: ConnectionType = BROKER): ref QTopic = 
  withLock lock:
    var qtopic: ref QTopic = (ref QTopic)()
    qtopic.name= name
    qtopic.topicConnectionType = connType
    qtopic.store.open(capacity)
    return qtopic


proc initQTopicUnlimited* (name: string, connType: ConnectionType = BROKER): ref QTopic = 
  var qtopic: ref QTopic = (ref QTopic)()
  qtopic.name= name
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
