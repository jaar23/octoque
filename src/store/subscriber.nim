import uuid4
import net

type
  Subscriber* = object
    connection: Socket
    connectionId*: Uuid


proc newSubscriber*(conn: Socket): Subscriber =
  result = Subscriber()
  result.connectionId = uuid4()
  result.connection = conn


proc notify*(subscriber: Subscriber): void =
  subscriber.connection.send("1\n")


proc send*(subscriber: Subscriber, data: string): void =
  subscriber.connection.send(data)


proc trySend*(subscriber: Subscriber, data: string): bool =
  return subscriber.connection.trySend(data)


proc close*(subscriber: Subscriber): void = 
  echo "connection close..."
  subscriber.connection.close()


proc ping*(subscriber: Subscriber): bool =
  let sent = subscriber.connection.trySend("\n")
  if not sent:
    return false
  let ack = subscriber.connection.recvLine()
  if ack != "":
    return true
  else:
    return false

# proc timeout*(subscriber: Subscriber): bool =
#   subscriber.connection.
# proc closed(socket: Socket): bool =
#   return socket.closed

# proc isClose*(subscriber: Subscriber): void = 
#   subscriber.connection.closed
