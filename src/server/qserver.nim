import ../store/queue, ../store/qtopic
import message, errcode, auth
import net, options, strutils, strformat, threadpool, sugar, sequtils
import octolog


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


proc procced(server: QueueServer, client: Socket, message = "PROCEED"): void =
  client.send(message & "\n")


proc decline(server: QueueServer, client: Socket, reason: string): void =
  client.send("DECLINE:" & reason & "\n")


proc endofresp(server: QueueServer, client: Socket): void =
  client.send("ENDOFRESP\n")


## TODO: authentication with file based authentication
proc connect(server: QueueServer, client: Socket, qheader: QHeader): bool =
  let user: seq[User] = server.authStore.users.filter(u => u.username == qheader.username)
  if user.len != 1:
    error "Server error, duplicate user found. Try remove one user from auth.yaml file"
    return false
  return verifyPassowrd(qheader.password, user[0].passwordHash)
  

## TODO disconnect current connection
# proc disconnect(server: var QueueServer): void =


proc response(server: QueueServer, client: Socket, msgSeq: Option[seq[
    string]]): void =
  if msgSeq.isSome and msgSeq.get.len > 0:
    for msg in msgSeq.get:
      client.send(msg & "\n")


proc store(server: QueueServer, client: Socket, qheader: QHeader): void =
  if qheader.transferMethod == BATCH:
    for row in 0..<qheader.payloadRows.int():
      let msg = client.recvLine()
      let stored = server.queue.enqueue(qheader.topic, msg)
      if stored.isSome and qheader.command == PUTACK:
        client.send("SUCCESS\n" & $stored.get)
      elif stored.isNone and qheader.command == PUTACK:
        client.send("FAIL\n" & $stored.get)
  elif qheader.transferMethod == STREAM:
    echo "not implemented"


proc ping(server: QueueServer, client: Socket): void =
  client.send("PONG\n")


proc clear(server: QueueServer, client: Socket, qheader: QHeader): void =
  let cleared = server.queue.clearqueue(qheader.topic)
  if cleared.isSome and cleared.get:
    client.send("CLEARED\n")
  else:
    client.send("FAIL\n")


proc subscribe(server: QueueServer, client: Socket, topicName: string): void =
  debug $getThreadId() & "into subscribe"
  server.queue.subscribe(topicName, client)


proc unsubscribe(server: QueueServer, client: Socket, topicName: string): void =
  let line = client.recvLine().strip()
  server.queue.unsubscribe(topicName, line)


proc newtopic(server: QueueServer, client: Socket, topicName: string,
    capacity: int, connectionType: ConnectionType): void =
  var topic: ref QTopic
  if capacity > 0:
    topic = initQTopic(topicName, capacity, connectionType)
  else:
    topic = initQTopicUnlimited(topicName, connectionType)
  server.queue.addTopic(topic)
  server.queue.startTopicListener(topic.name, 1)
  client.send("SUCCESS\n")


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
  var connected = false
  try:
    while true:
      let headerLine = client.recvLine()
      info "incoming: " & headerLine
      info "connected: " & $connected
      if headerLine.len != 0:
        #parse header
        let qheader = parseQHeader(headerLine)
        debug "qheader: " & $qheader
        if qheader.command != CONNECT and not connected:
          server.decline(client, $UNAUTHORIZED_ACCESS)

        if qheader.protocol != OTQ:
          raise newException(ProcessError, $NOT_IMPLEMENTED)
        if not server.queue.hasTopic(qheader.topic) and qheader.topic != "*" and
            qheader.command != NEW and qheader.command != CONNECT:
          raise newException(ProcessError, $TOPIC_NOT_FOUND)
        
        case qheader.command:
        of GET:
          server.procced(client)
          let msgSeq = server.queue.dequeue(qheader.topic, qheader.numberOfMsg)
          server.response(client, msgSeq)
        of PUT, PUTACK, PUBLISH:
          # haven't confirm the behavior of publish, leaving it an alias of PUT
          server.procced(client)
          server.store(client, qheader)
        of SUBSCRIBE:
          server.procced(client)
          debug "proceed subscribe"
          server.subscribe(client, qheader.topic)
        of UNSUBSCRIBE:
          server.unsubscribe(client, qheader.topic)
        of PING:
          server.ping(client)
        of CLEAR:
          server.procced(client)
          server.clear(client, qheader)
        of NEW:
          server.procced(client)
          server.newtopic(client, qheader.topic, qheader.topicSize,
              qheader.connectionType)
        of DISPLAY:
          server.procced(client)
          server.listtopic(client, qheader)
        of ACKNOWLEDGE:
          server.procced(client)
        of CONNECT:
          let authenticated = server.connect(client, qheader)
          if not authenticated:
            server.decline(client, "Unauthorized access")
            break
          else:
            server.procced(client, "CONNECTED")
            connected = true
            info &"connection status: {connected}"
          # of DISCONNECT:
          #   remove session from secure service
          #   echo "not implemented"
      server.endofresp(client)
  except:
    let errMsg = getCurrentExceptionMsg()
    server.decline(client, errMsg)
  finally:
    client.close()


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


