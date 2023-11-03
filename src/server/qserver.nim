import ../store/queue, ../store/qtopic
import message, errcode, auth
import net, options, strutils, strformat, threadpool, sugar, sequtils
import octolog

# 4mb maximum 
const MAX_CONNLINE_LENGTH = 4_000_000

type
  QueueServer* = object
    address: string
    port: int
    queue: ref Queue
    running: bool
    authStore: Auth

  QueueResponse* = object
    status: string
    code: int
    message: string
    data: string

  ParseError* = object of CatchableError
  ProcessError* = object of CatchableError


proc newQueueServer*(address: string, port: int,
    topicSize: uint8 = 8): QueueServer =
  var qserver = QueueServer(address: address, port: port)
  qserver.queue = newQueue(topicSize)
  qserver.running = true
  qserver.authStore = getAuth()
  return qserver


proc initQueueServer*(address: string, port: int, topics: varargs[string],
                      workerNumber: int, topicSize: uint8 = 8): QueueServer =
  var qserver = QueueServer(address: address, port: port)
  var queue = initQueue(topics, topicSize)
  qserver.queue = queue
  qserver.queue.startListener(workerNumber)
  qserver.running = true
  qserver.authStore = getAuth()
  return qserver


proc addQueueTopic*(qserver: QueueServer, topicName: string,
    connType: ConnectionType = BROKER, capacity: int = 0): void =
  qserver.queue.addTopic(topicName, connType, capacity)


## check if user has access to topic
## check if user has correct role to access (rwnc)
##TODO: check queue state before PROCEED
##TODO: check qtopic state before proceed
proc proceedCheck(server: QueueServer, username, role, topic: string,
    accessMode: AccessMode): bool =
  if server.authStore.userHasAccess(username, topic):
    info "authorized access"
    return true
  if server.authStore.roleHasAccess(role, topic, accessMode):
    info "authorized access"
    return true
  return false


proc proceed(server: QueueServer, client: Socket, message = "PROCEED"): void =
  client.send(message & "\r\L")


proc decline(server: QueueServer, client: Socket, reason: string): void =
  client.send("DECLINE:" & reason & "\n")


proc endofresp(server: QueueServer, client: Socket): void =
  client.send("ENDOFRESP\r\L")


proc connect(server: QueueServer, client: Socket, qheader: QHeader): (string, bool) =
  let user: seq[User] = server.authStore.users.filter(u => u.username ==
      qheader.username)
  if user.len != 1:
    error "Server error, duplicate user found. Try remove one user from auth.yaml file"
    return ("", false)
  return (user[0].role, verifyPassowrd(qheader.password, user[0].passwordHash))


proc response(server: QueueServer, client: Socket, msgSeq: Option[seq[
    string]]): void =
  if msgSeq.isSome and msgSeq.get.len > 0:
    for msg in msgSeq.get:
      client.send(msg & "\r\L")


proc store(server: QueueServer, client: Socket, qheader: QHeader): void =
  if qheader.transferMethod == BATCH:
    for row in 0..<qheader.payloadRows.int():
      let msg = client.recvLine(maxLength=MAX_CONNLINE_LENGTH)
      let stored = server.queue.enqueue(qheader.topic, msg)
      if stored.isSome and qheader.command == PUTACK:
        client.send("SUCCESS\r\L" & $stored.get)
      elif stored.isNone and qheader.command == PUTACK:
        client.send("FAIL\r\L" & $stored.get)
  elif qheader.transferMethod == STREAM:
    echo "not implemented"


proc ping(server: QueueServer, client: Socket, topic: string): void =
  let topicOpt = server.queue.find(topic)
  if topicOpt.isSome:
    client.send("PONG\r\L")
  else: client.send("NOT FOUND\r\L")


proc clear(server: QueueServer, client: Socket, qheader: QHeader): void =
  let cleared = server.queue.clearqueue(qheader.topic)
  if cleared.isSome and cleared.get:
    client.send("CLEARED\r\L")
  else:
    client.send("FAIL\r\L")


proc subscribe(server: QueueServer, client: Socket, topicName: string): void =
  try:
    let topic = server.queue.find(topicName)
    if topic.isSome and topic.get.connectionType() == PUBSUB:
      server.queue.subscribe(topicName, client)
    else:
      raise newException(CatchableError, "Topic is not subscribable")
  except:
    server.decline(client, getCurrentExceptionMsg())


proc unsubscribe(server: QueueServer, client: Socket, topicName: string): void =
  let line = client.recvLine().strip()
  server.queue.unsubscribe(topicName, line)


proc newtopic(server: QueueServer, client: Socket, topicName: string,
    capacity: int, connectionType: ConnectionType, numberOfThread: uint): void =
  var topic: ref QTopic
  if capacity > 0:
    topic = initQTopic(topicName, capacity, connectionType)
  else:
    topic = initQTopicUnlimited(topicName, connectionType)
  server.queue.addTopic(topic)
  server.queue.startTopicListener(topic.name, numberOfThread)
  client.send("SUCCESS\r\L")


proc listtopic(server: QueueServer, client: Socket, qheader: QHeader): void =
  let topicName = qheader.topic
  debug "topic name: " & topicName
  if topicName == "*":
    for topic in server.queue.topics:
      client.send($topic & "\n")
  else:
    for topic in server.queue.topics:
      if topic.name == topicName:
        client.send($topic & "\n")
        break


proc execute(server: QueueServer, client: Socket): void {.thread.} =
  defer:
    debug "exit from execution.."
  var connected = false
  var username = ""
  var role = ""
  try:
    while true:
      var unauthorized = false
      let headerLine = client.recvLine()
      info $getThreadId() & " incoming: " & headerLine
      info $getThreadId() & " connected: " & $connected
      if headerLine.len != 0:
        let qheader = parseQHeader(headerLine)
        debug "qheader: " & $qheader
        if qheader.command != CONNECT and not connected:
          server.decline(client, $UNAUTHORIZED_ACCESS)

        if qheader.protocol != OTQ: raise newException(ProcessError,
            $NOT_IMPLEMENTED)
        if not server.queue.hasTopic(qheader.topic) and qheader.topic != "*" and
            qheader.command != NEW and qheader.command != CONNECT and
                qheader.command != DISCONNECT:
          raise newException(ProcessError, $TOPIC_NOT_FOUND)

        case qheader.command:
        of GET:
          if server.proceedCheck(username, role, qheader.topic, TRead):
            server.proceed(client)
            let msgSeq = server.queue.dequeue(qheader.topic,
                qheader.numberOfMsg)
            server.response(client, msgSeq)
          else: unauthorized = true
        of PUT, PUTACK, PUBLISH:
          # TODO: enhance publish to put message to multiple topics
          if server.proceedCheck(username, role, qheader.topic, TWrite):
            server.proceed(client)
            server.store(client, qheader)
          else: unauthorized = true
        of SUBSCRIBE:
          if server.proceedCheck(username, role, qheader.topic, TRead):
            server.proceed(client)
            server.subscribe(client, qheader.topic)
            client.close()
            debug "subscription close"
            break
          else: unauthorized = true
          debug "{getThreadId()} exit from subscribe"
        of UNSUBSCRIBE: server.unsubscribe(client, qheader.topic)
        of PING: server.ping(client, qheader.topic)
        of CLEAR:
          if server.proceedCheck(username, role, qheader.topic, TClear):
            server.proceed(client)
            server.clear(client, qheader)
          else: unauthorized = true
        of NEW:
          if server.proceedCheck(username, role, qheader.topic, TNew):
            server.proceed(client)
            server.newtopic(client, qheader.topic, qheader.topicSize,
              qheader.connectionType, qheader.numberOfThread)
          else: unauthorized = true
        of DISPLAY:
          if server.proceedCheck(username, role, qheader.topic, TRead):
            server.proceed(client)
            server.listtopic(client, qheader)
          else: unauthorized = true
        of ACKNOWLEDGE: server.proceed(client, "ACKNOWLEDGE")
        of CONNECT:
          let (r, authenticated) = server.connect(client, qheader)
          if not authenticated:
            unauthorized = true
            break
          else:
            username = qheader.username
            role = r
            server.proceed(client, "CONNECTED")
            connected = true
            info &"connection status: {connected}"
        of DISCONNECT:
          connected = false
          info "session disconnected"
          break

        if unauthorized: server.decline(client, $UNAUTHORIZED_ACCESS)

      else: 
        break
      server.endofresp(client)

  except:
    let errMsg = getCurrentExceptionMsg()
    server.decline(client, errMsg)
  finally:
    info "session closed"
    client.close()
    connected = false


proc start*(server: QueueServer, numOfThread: int): void =
  if server.running != false:
    server.queue.startListener(numOfThread)
  let socket = newSocket()
  socket.bindAddr(Port(server.port))
  socket.listen()
  info(&"server is listening on 0.0.0.0: {server.port}")

  while true:
    var client: Socket
    socket.accept(client)
    info("processing client request from " & $client.getPeerAddr())
    spawn server.execute(client)
  socket.close()
  notice("terminating server")


