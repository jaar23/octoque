import uuid4
import net
import strformat
import octolog


type
  QClient* = object
    threadId*: int
    connection: Socket
    connectionId: Uuid
    disconnected*: bool = false
    channel: Channel[string]


proc newQClient*(conn: Socket, threadId: int): ref QClient =
  result = (ref QClient)()
  result.connectionId = uuid4()
  result.connection = conn
  result.threadId = threadId
  result.channel.open()


proc runnerId*(qclient: ref QClient): string =
  &"{qclient.threadId}.{qclient.connectionId}"


proc connectionId*(qclient: ref QClient): string =
  $qclient.connectionId

proc push*(qclient: ref QClient, data: string): void =
  debug &"{qclient.runnerId()} push new message, {data}"
  qclient.channel.send(data)


proc notify*(qclient: ref QClient): void =
  qclient.connection.send("1\n")


proc send*(qclient: ref QClient, msg: string): void =
  qclient.connection.send(msg)


proc trySend*(qclient: ref QClient, data: string): bool =
  if qclient.disconnected:
    return false
  else:
    let sent = qclient.connection.trySend(data)
    if not sent:
      qclient.disconnected = true
    return sent


proc publish*(qclient: ref QClient): void =
  if qclient.channel.peek() >  0:
    let recvData = qclient.channel.recv()
    let sent: bool = qclient.trySend(recvData)
    if not sent:
      debug &"{qclient.runnerId()} failed to send message"
  else:
    return


proc close*(qclient: ref QClient): void =
  info &"{qclient.runnerId()} connection close..."

  if qclient.disconnected:
    return
  qclient.disconnected = true
  qclient.connection.close()


proc ping*(qclient: ref QClient): bool =
  let sent = qclient.connection.trySend("\n")
  if not sent:
    qclient.disconnected = true
    return false
  let ack = qclient.connection.recvLine()
  if ack != "":
    qclient.disconnected = false
    return true
  else:
    qclient.disconnected = true
    return false


proc isDisconnected*(qclient: ref QClient): bool =
  qclient.disconnected


proc `$`*(qclient: ref QClient): string =
  result = &"{qclient.runnerId()} is "
  if qclient.disconnected:
    result &= "disconnected"
  else:
    result &= "connected"


proc run*(qclient: ref QClient) {.thread.} =
  qclient.threadId = getThreadId()
  info $qclient
  defer:
    qclient.close()
    info &"{qclient.runnerId()} exit run"
  try:
    while not qclient.disconnected:
      if not qclient.isDisconnected():
        let pong = qclient.ping()
        if not pong:
          break
        qclient.publish()
      else:
        echo $qclient
        break
  except:
    error &"{qclient.runnerId()} {getCurrentExceptionMsg()}"


