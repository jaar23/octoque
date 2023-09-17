import ../store/queue, ../store/qtopic
import message, errcode
import net, options, strutils, strformat, threadpool 
import octolog


type
  # QueueCommand* = enum
  #   GET = "GET",
  #   PUT = "PUT",
  #   CLEAR = "CLEAR",
  #   NEW = "NEW",
  #   SUB = "SUB",
  #   COUNT = "COUNT"

  QueueServer* = object
    address: string
    port: int
    queue: ref Queue
    running: bool

  # QueueRequest = object
  #   command: QueueCommand
  #   topic: string
  #   data: Option[string]

  QueueResponse* = object
    status: string
    code: int
    message: string
    data: string

  ParseError* = object of CatchableError
  ProcessError* = object of CatchableError


proc newQueueServer*(address: string, port: int): QueueServer =
  var qserver = QueueServer(address: address, port: port)
  qserver.queue = newQueue()
  qserver.running = true
  return qserver


proc initQueueServer*(address: string, port: int, topics: varargs[string],
    workerNumber: int): QueueServer =
  var qserver = QueueServer(address: address, port: port)
  var queue = initQueue(topics)
  qserver.queue = queue
  qserver.queue.startListener(workerNumber)
  qserver.running = true
  return qserver


proc addQueueTopic*(qserver: QueueServer, topicName: string,
    connType: ConnectionType = BROKER, capacity: int = 0): void =
  qserver.queue.addTopic(topicName, connType, capacity)


proc newQueueResponse*(status: string, code: int, message: string,
    data: string): QueueResponse =
  var queueResp = QueueResponse()
  queueResp.code = 0
  queueResp.status = "ok"
  queueResp.message = "push to subscriber"
  queueResp.data = data
  return queueResp


proc toStrResponse*(resp: QueueResponse): string =
  var respStr = &"status {resp.status}\r\ncode {resp.code}\r\nmessage {resp.message}\r\n{resp.data}"
  return respStr


# proc parseRequest(server: QueueServer, reqData: string): QueueRequest =
#   var queueReq = QueueRequest()
#   try:
#     var dataArr = reqData.split(" ")
#     var data = ""
#     if dataArr.len >= 3:
#       data = dataArr[2..dataArr.len - 1].join(" ")
#     elif dataArr.len <= 1:
#       raise newException(ParseError, "invalid request part")
#
#     queueReq.topic = dataArr[1]
#     case dataArr[0]
#     of $QueueCommand.GET:
#       queueReq.command = GET
#       queueReq.data = some(data)
#     of $QueueCommand.PUT:
#       queueReq.command = PUT
#       queueReq.data = some(data)
#     of $QueueCommand.CLEAR:
#       queueReq.command = CLEAR
#     of $QueueCommand.NEW:
#       queueReq.command = NEW
#     of $QueueCommand.SUB:
#       queueReq.command = SUB
#     of $QueueCommand.COUNT:
#       queueReq.command = COUNT
#     else:
#       info &"invalid queue command: {dataArr[0]}"
#       raise newException(ParseError, "invalid queue command")
#   except ParseError:
#     error getCurrentExceptionMsg()
#
#   return queueReq


# proc processRequest(server: QueueServer, connection: Socket,
#     request: QueueRequest): void =
#   var queueResp = QueueResponse()
#   defer:
#     if queueResp.status != "disconnected":
#       connection.send(queueResp.toStrResponse())
#     connection.close()
#     info "done processed"
#
#   try:
#     case request.command
#     of QueueCommand.GET:
#       let batchNum: int = if request.data.get != "": request.data.get.parseInt() else: 1
#       let dataSeq = server.queue.dequeue(request.topic, batchNum)
#       echo $dataSeq
#       if dataSeq.isSome and dataSeq.get.len > 0:
#         queueResp.code = 0
#         queueResp.status = "ok"
#         queueResp.message = "successfully dequeue from " & request.topic
#         if dataSeq.get.len == 1:
#           queueResp.data = dataSeq.get[0]
#         else:
#           for n in 0..dataSeq.get.len - 1:
#             queueResp.data &= dataSeq.get[n]
#             queueResp.data &= ",\r\n"
#         echo $queueResp
#       else:
#         queueResp.code = 10
#         queueResp.status = "ok"
#         queueResp.message = "successfully dequeue from " & request.topic
#         queueResp.data = ""
#     of QueueCommand.PUT:
#       if request.data.isSome:
#         var numberOfMsg: Option[int] = server.queue.enqueue(request.topic,
#             request.data.get)
#         queueResp.code = 0
#         queueResp.status = "ok"
#         queueResp.message = "successfully enqueue to " & request.topic
#         queueResp.data = $numberOfMsg
#       else:
#         raise newException(ProcessError, "no data to enqueue")
#     of QueueCommand.SUB:
#       server.queue.subscribe(request.topic, connection)
#       info "pubsub connection exiting"
#       queueResp.status = "disconnected"
#       queueResp.code = 11
#       queueResp.message = "disconnected from pubsub connection"
#     of QueueCommand.CLEAR:
#       let cleared = server.queue.clearqueue(request.topic)
#       queueResp.code = if cleared.isSome: 0 else: 4
#       queueResp.status = if cleared.isSome: $cleared.get else: $false
#       if cleared.isSome:
#         if cleared.get == true:
#           queueResp.message = "store resetted"
#         else:
#           queueResp.message = "failed to reset store"
#       else:
#         queueResp.message = "failed to reset store, queue topic might not exist"
#     of QueueCommand.COUNT:
#       let count = server.queue.countqueue(request.topic)
#       queueResp.code = 0
#       queueResp.status = "ok"
#       queueResp.message = "queue topic remains with " & $count & " message"
#       queueResp.data = $count
#     of QueueCommand.NEW:
#       warn("not implemented")
#       queueResp.code = 0
#       queueResp.status = "error"
#       queueResp.message = "not implemented"
#   except ProcessError:
#     let e = getCurrentException()
#     error(e.msg)
#     queueResp.code = 99
#     queueResp.status = "error"
#     queueResp.message = "Failed to process request: " & e.msg
#     queueResp.data = ""
#     error("failed to process request: " & $request)


proc procced(server: QueueServer, client: Socket): void =
  client.send("PROCEED\n")


proc response(server: QueueServer, client: Socket, msgSeq: Option[seq[string]]): void =
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



# parse custom command to otq command
proc execute(server: QueueServer, client: Socket): void {.thread.} = 
  try:
    let headerLine = client.recvLine()
  
    if headerLine.len != 0:
      #parse header
      let qheader = parseQHeader(headerLine)
     
      if qheader.protocol != OTQ:
        raise newException(ProcessError, $NOT_IMPLEMENTED)
      if not server.queue.hasTopic(qheader.topic):
        raise newException(ProcessError, $TOPIC_NOT_FOUND)

      # parse successfully
      server.procced(client)

      case qheader.command:
      of GET:
        let msgSeq = server.queue.dequeue(qheader.topic, qheader.batchNumber)
        server.response(client, msgSeq)
      of PUT, PUTACK:
        server.store(client, qheader)
      of PUBLISH:
        echo "not implemented"
      of SUBSCRIBE:
        server.queue.subscribe(qheader.topic, client)
      of UNSUBSCRIBE:
        echo "not implemented"
      of PING:
        server.ping(client)
      of CLEAR:
        server.clear(client, qheader)
      of CONNECT:
        echo "not implemented"
      of DISCONNECT:
        echo "not implemented"
      of ACKNOWLEDGE:
        server.procced(client)
  except:
    let errMsg = getCurrentExceptionMsg()
    client.send(errMsg)
  finally:
    client.close()


# proc execute(server: QueueServer, client: Socket): void {.thread.} =
#   var recvLine = client.recvLine()
#   if recvLine.len > 0:
#     var request = server.parseRequest(recvLine)
#     #debug($request)
#     server.processRequest(client, request)


proc start*(server: QueueServer, numOfThread: int): void =
  if server.running != false:
    server.queue.startListener(numOfThread)
  let socket = newSocket()
  socket.bindAddr(Port(server.port))
  socket.listen()
  info(&"server is listening on 0.0.0.0: {server.port}")

  while true:
    var client: Socket
    #var address = ""
    #socket.acceptAddr(client, address)
    socket.accept(client)
    info("processing client request from " & $client.getPeerAddr())
    spawn server.execute(client)
  socket.close()
  notice("terminating server")


