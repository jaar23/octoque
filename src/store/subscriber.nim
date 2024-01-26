import uuid4
import net, os
import strformat, strutils
import octolog, storage_manager

# TODO: adding subscriber specified detail
# ip_addr, deq.log
type
  Subscriber* = object
    threadId*: string
    connection: Socket
    connectionId*: Uuid
    connectionIp*: string
    disconnected*: bool = false
    channel: Channel[string]

  ParseError = object of CatchableError


proc newSubscriber*(conn: Socket, threadId: string): ref Subscriber =
  result = (ref Subscriber)()
  result.connectionId = uuid4()
  result.connection = conn
  result.threadId = threadId
  result.connectionIp = $conn.getPeerAddr()
  result.channel.open()


proc runnerId*(subscriber: ref Subscriber): string =
  &"{subscriber.threadId}.{subscriber.connectionId}"


proc push*(subscriber: ref Subscriber, data: string): void =
  debug &"{subscriber.runnerId()} push new message, {data}"
  subscriber.channel.send(data)


proc notify*(subscriber: ref Subscriber): void =
  subscriber.connection.send("1\n")


proc ping*(subscriber: ref Subscriber): bool =
  ## sleep can be configure in order to control the gap of pubsub
  sleep(10)
  let sent = subscriber.connection.trySend("\r\L")
  if not sent:
    subscriber.disconnected = true
    return false
  #let ack = readUntil(subscriber.connection, "REPLPONG")
  let ack = subscriber.connection.recvLine()
  if ack != "":
    subscriber.disconnected = false
    return true
  else:
    subscriber.disconnected = true
    return false


proc parseAck(subscriber: ref Subscriber, line: string): seq[string]  =
  let ackLine = line.split(" ")
  return ackLine


proc readUntil(conn: Socket, symbol: string): string =
  var data = ""
  var reached = false
  while not reached:
    var recvData = conn.recv(1, timeout=5000)
    data = data & recvData
    if data.contains(symbol):
      reached = true
  return data


proc readUntil(conn: Socket, sw: string, ew: string, continueOn: seq[string]): string =
  var data = ""
  var reached = false
  while not reached:
    var recvData = conn.recv(1, timeout=10000)
    data = data & recvData
    if data.startsWith(sw) and data.endsWith(ew):
      reached = true
    info &"readuntil: {data}"
    if continueOn.contains(data):
      # data = ""
      # discard conn.trySend("PROCEED\r\L")
      break
  return data


proc trySend*(subscriber: ref Subscriber, data: string): bool =
  if subscriber.disconnected:
    return false
  else:
    #debug "sending data >>>>" & data
    let sent = subscriber.connection.trySend(data & "\n")
    if not sent:
      subscriber.disconnected = true
    else:
      let retryLimit = 5
      var retry = 0
      ## TODO: problem at here, either stagnant or either never stop
      while retry < retryLimit:
        # var ack = subscriber.connection.recvLine()
        var ack = readUntil(subscriber.connection, "OTQ ACK", "\r\L", @["REPLPONG\r\L"])
        info &"ack readuntil: {ack}"
        # if not ack.strip().startsWith("ACK"):
        #   retry = retry + 1
        #   continue
        try:
          let ackLine = subscriber.parseAck(ack)
          if ackLine.len != 4:
            info &"expecting ACK but got {ack}"
            retry = retry + 1
            raise newException(ParseError, &"acknowledge having unexpected value, {ack}")
          else:
            let messageId = ackLine[3].strip().parseInt()
            let topic = ackLine[2].strip()
            {.cast(gcsafe).}:
              let parcel = newParcel(messageId, topic, CONSUMED)
              storageManager.manager.sendParcel(parcel)
            retry = retryLimit + 1 
        except:
          error "failed to process message acknowledgement"
          error getCurrentExceptionMsg()
          # retry = retryLimit + 1
    return sent


# proc trySend*(subscriber: ref Subscriber, data: string): bool =
#   if subscriber.disconnected:
#     return false
#   else:
#     #debug "sending data >>>>" & data
#     let sent = subscriber.connection.trySend(data & "\n")
#     if not sent:
#       subscriber.disconnected = true
#     return sent


proc publish*(subscriber: ref Subscriber): void =
  #if subscriber.channel.peek() > 0:
  let recvData = subscriber.channel.recv()
  #let (hasData, recvData) = subscriber.channel.tryRecv()
  #if hasData:
  let sent: bool = subscriber.trySend(recvData)
  if not sent:
    debug &"{subscriber.runnerId()} failed to send message"
  else:
    return
  # else:
  #   sleep(10000)
  #   discard subscriber.ping()


proc close*(subscriber: ref Subscriber): void =
  defer:
    info &"{subscriber.runnerId()} connection close..."
  if subscriber.disconnected:
    return
  subscriber.disconnected = true
  subscriber.connection.close()
  subscriber.channel.close()
  subscriber.connection = nil


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
  try:
    while not subscriber.disconnected and subscriber.connection != nil:
      if not subscriber.isDisconnected():
        subscriber.publish()
        # let pong = subscriber.ping()
        # if not pong:
        #   #debug "publishing..."
        #   break
      else:
        echo $subscriber
        debug "exit subscription loop"
        break
  except:
    error &"{subscriber.runnerId()} {getCurrentExceptionMsg()}"
  finally:
    info &"{subscriber.runnerId()} closing subscription"
    #subscriber.close()

