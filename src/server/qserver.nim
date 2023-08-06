import ../store/queue
import std/[net, options, strutils, strformat], threadpool


type 
  QueueCommand* = enum
    GET = "GET",
    PUT = "PUT",
    CLEAR = "CLEAR",
    NEW = "NEW"

  QueueServer* = object
    address: string
    port: int
    queue: ref Queue

  QueueRequest = object
    command: QueueCommand
    topic: string
    data: Option[string]

  QueueResponse = object
    status: string
    code: int
    message: string
    data: string

  ParseError* = object of CatchableError
  ProcessError* = object of CatchableError

proc initQueueServer* (address: string, port: int, topics: varargs[string]): QueueServer =
  var qserver = QueueServer(address: address, port: port)
  var queue = initQueue(topics)
  qserver.queue = queue
  qserver.queue.startListener()
  return qserver


proc toStrResponse(resp: QueueResponse): string = 
  var respStr = &"status {resp.status}\r\ncode {resp.code}\r\nmessage {resp.message}\r\n{resp.data}"
  return respStr


proc parseRequest(server: QueueServer, reqData: string): QueueRequest = 
  var queueReq = QueueRequest()
  try:
    var dataArr = reqData.split(" ")
    var data = ""
    #echo $dataArr
    if dataArr.len >= 3:
      data = dataArr[2..dataArr.len - 1].join(" ")
      #raise newException(ParseError, "Invalid request part")
    elif dataArr.len <= 1:
      raise newException(ParseError, "Invalid request part")
    queueReq.topic = dataArr[1]
    case dataArr[0]
    of $QueueCommand.GET:
      #echo "GETTING"
      queueReq.command = GET
      queueReq.data = none(string)
    of $QueueCommand.PUT:
      #echo "PUTTING"
      queueReq.command = PUT
      queueReq.data = some(data)
    of $QueueCommand.CLEAR:
      #echo "CLEARING"
      queueReq.command = CLEAR
    of $QueueCommand.NEW:
      #echo "NEWING"
      queueReq.command = NEW
    else:
      echo "OH NOOO"
      raise newException(ParseError, "Invalid queue command")
  except ParseError:
    let e = getCurrentException()
    echo "Failed to parse command: " & e.msg
    echo "request data:", $reqData

  return queueReq


proc processRequest(server: QueueServer, connection: Socket, request: QueueRequest): void = 
  var queueResp = QueueResponse()
  defer:
    connection.send(queueResp.toStrResponse())
    connection.close()

  try:
    case request.command
    of QueueCommand.GET:
      let dataOpt = server.queue.dequeue(request.topic)
      if dataOpt.isSome:
        queueResp.code = 0
        queueResp.status = "ok"
        queueResp.message = "successfully dequeue from " & request.topic
        queueResp.data = dataOpt.get
        echo $queueResp
      else:
        queueResp.code = 10
        queueResp.status = "ok"
        queueResp.message = "successfully dequeue from " & request.topic
        queueResp.data = ""
    of QueueCommand.PUT:
      if request.data.isSome:
        var numberOfMsg: Option[int] = server.queue.enqueue(request.topic, request.data.get)
        queueResp.code = 0
        queueResp.status = "ok"
        queueResp.message = "successfully enqueue to " & request.topic
        queueResp.data = $numberOfMsg
        echo "sucess..."
      else:
        raise newException(ProcessError, "No data to enqueue")
    of QueueCommand.CLEAR:
      echo "not implemented"
      queueResp.code = 0
      queueResp.status = "error"
      queueResp.message = "not implemented"
    of QueueCommand.NEW:
      echo "not implemented"
      queueResp.code = 0
      queueResp.status = "error"
      queueResp.message = "not implemented"
    # else:
    #   raise newException(ProcessError, "Failed to process request")
  except ProcessError:
    let e = getCurrentException()
    echo e.msg
    queueResp.code = 99
    queueResp.status = "error"
    queueResp.message = "Failed to process request: " & e.msg
    queueResp.data = ""
    echo $request


proc execute(server: QueueServer, client: Socket): void {.thread.} =
    var recvLine = client.recvLine()
    if recvLine.len > 0:
      var request = server.parseRequest(recvLine)
      server.processRequest(client, request)
    else:
      echo "Invalid request: ", recvLine


proc start* (server: QueueServer): void =
  let socket = newSocket()
  socket.bindAddr(Port(server.port))
  socket.listen()

  var address = server.address
  while true:
    var client: Socket
    socket.acceptAddr(client, address)
    #echo "Cliented connected from: ", address
    spawn server.execute(client)
    #let recvData = client.recvLine()
    #var recvdata = client.recv(1024)
    #echo "received: \n", recvData
  
  sync()
  socket.close()


