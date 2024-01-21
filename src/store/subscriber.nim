import uuid4
import net
import strformat
import octolog

# TODO: adding subscriber specified detail
# ip_addr, deq.log
type
  Subscriber* = object
    threadId*: string
    connection: Socket
    connectionId*: Uuid
    disconnected*: bool = false
    channel: Channel[string]


proc newSubscriber*(conn: Socket, threadId: string): ref Subscriber =
  result = (ref Subscriber)()
  result.connectionId = uuid4()
  result.connection = conn
  result.threadId = threadId
  result.channel.open()


proc runnerId*(subscriber: ref Subscriber): string =
  &"{subscriber.threadId}.{subscriber.connectionId}"


proc push*(subscriber: ref Subscriber, data: string): void =
  debug &"{subscriber.runnerId()} push new message, {data}"
  subscriber.channel.send(data)


proc notify*(subscriber: ref Subscriber): void =
  subscriber.connection.send("1\n")


# TODO: connection to recvline in order to ack message
proc trySend*(subscriber: ref Subscriber, data: string): bool =
  if subscriber.disconnected:
    return false
  else:
    #debug "sending data >>>>" & data
    let sent = subscriber.connection.trySend(data & "\n")
    if not sent:
      subscriber.disconnected = true
    return sent


proc publish*(subscriber: ref Subscriber): void =
  #if subscriber.channel.peek() > 0:
  let recvData = subscriber.channel.recv()
  let sent: bool = subscriber.trySend(recvData)
  if not sent:
    debug &"{subscriber.runnerId()} failed to send message"
  #else:
  #  return


proc close*(subscriber: ref Subscriber): void =
  info &"{subscriber.runnerId()} connection close..."

  if subscriber.disconnected:
    return
  subscriber.disconnected = true
  subscriber.connection.close()
  subscriber.channel.close()
  subscriber.connection = nil


proc ping*(subscriber: ref Subscriber): bool =
  # debug &"{subscriber.runnerId()} ping subscriber"
  # defer:
  #   if result:
  #     debug &"{subscriber.runnerId()} ping successfully"
  #   else:
  #     debug &"{subscriber.runnerId()} ping failed"

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


proc isDisconnected*(subscriber: ref Subscriber): bool =
  subscriber.disconnected


proc `$`*(subscriber: ref Subscriber): string =
  result = &"{subscriber.runnerId()} is "
  if subscriber.disconnected:
    result &= "disconnected"
  else:
    result &= "connected"


proc run*(subscriber: ref Subscriber) {.thread.} =
  subscriber.threadId = $getThreadId()
  info $subscriber
  defer:
    subscriber.close()
    #info &"{subscriber.runnerId()} exit run"
  try:
    while not subscriber.disconnected and subscriber.connection != nil:
      if not subscriber.isDisconnected():
        # let pong = subscriber.ping()
        # if not pong:
        #debug "publishing..."
        #   break
        subscriber.publish()
      else:
        echo $subscriber
        debug "exit subscription loop"
        break
  except:
    error &"{subscriber.runnerId()} {getCurrentExceptionMsg()}"
  finally:
    info &"{subscriber.runnerId()} closing subscription"
    subscriber.close()

