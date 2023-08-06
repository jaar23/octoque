import std/options, std/net, std/locks

var 
  lock: Lock

type QTopic* = object
  name: string
  qchannel: Channel[string]
  store {.guard: lock}: Channel[string]
  capacity: int

proc name* (self: ref QTopic): string = 
  return self.name


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


proc listen* (qtopic: ref QTopic): void {.thread.} = 
  while qtopic.qchannel.peek() > 0:
    let recvData = qtopic.qchannel.recv()
    qtopic.storeData(recvData)

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
 

proc initQTopic* (name: string, capacity: int): ref QTopic = 
  withLock lock:
    var qtopic = (ref QTopic)(name: name)
    qtopic.store.open(capacity)
    return qtopic


proc initQTopicUnlimited* (name: string): ref QTopic = 
  var qtopic = (ref QTopic)(name: name)
  qtopic.qchannel.open()
  withLock lock:
    qtopic.store.open()
  return qtopic


# proc testClosure* (total: int, handler: (x: int, y: int) -> int): void = 
#   var ix = 3
#   var iy = 2
#   var itotal = handler(ix, iy)
#   echo total, "==", itotal
