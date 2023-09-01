import uuid4
import net
import strformat

type
  Subscriber* = object
    threadId*: string
    connection: Socket
    connectionId*: Uuid
    disconnected*: bool = false


proc newSubscriber*(conn: Socket, threadId: string): ref Subscriber =
  result = (ref Subscriber)()
  result.connectionId = uuid4()
  result.connection = conn
  result.threadId = threadId


proc notify*(subscriber: ref Subscriber): void =
  subscriber.connection.send("1\n")


proc send*(subscriber: ref Subscriber, data: string): void =
  subscriber.connection.send(data)


proc trySend*(subscriber: ref Subscriber, data: string): bool =
  if subscriber.disconnected:
    return false
  else:
    let sent = subscriber.connection.trySend(data)
    if not sent:
      subscriber.disconnected = true
    return sent


proc close*(subscriber: ref Subscriber): void =
  echo &"[{subscriber.threadId}] {$subscriber.connectionId} connection close..."

  if subscriber.disconnected:
    return
  subscriber.disconnected  = true
  subscriber.connection.close()


proc ping*(subscriber: ref Subscriber): bool =
  let sent = subscriber.connection.trySend("\n")
  if not sent:
    subscriber.disconnected = true
    return false
  let ack = subscriber.connection.recvLine()
  if ack != "":
    subscriber.disconnected = false
    return true
  else:
    subscriber.disconnected = true
    return false


proc isDisconnected*(subscriber: ref Subscriber): bool = subscriber.disconnected


proc `$`*(subscriber: ref Subscriber): string =
  result = &"[{subscriber.threadId}] {$subscriber.connectionId} is "
  if subscriber.disconnected: 
    result &= "disconnected"
  else:
    result &= "connected"

# proc timeout*(subscriber: Subscriber): bool =
#   subscriber.connection.
# proc closed(socket: Socket): bool =
#   return socket.closed

# proc isClose*(subscriber: Subscriber): void =
#   subscriber.connection.closed
