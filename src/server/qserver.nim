import ../store/queue, ../store/qtopic
import std/[net, options, strutils, strformat]
import std/asyncdispatch, std/asyncnet


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
    running: bool

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


proc newQueueServer* (address: string, port: int): QueueServer =
  var qserver = QueueServer(address: address, port: port)
  qserver.queue = newQueue()
  qserver.running = false
  return qserver


proc initQueueServer* (address: string, port: int, topics: varargs[string], workerNumber: int): QueueServer =
  var qserver = QueueServer(address: address, port: port)
  var queue = initQueue(topics)
  qserver.queue = queue
  qserver.queue.startListener(workerNumber)
  qserver.running = true
  return qserver


proc addQueueTopic* (qserver: QueueServer, topicName: string, connType: ConnectionType = BROKER, capacity: int = 0): void =
  qserver.queue.addTopic(topicName, connType, capacity)


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


proc processRequest(server: QueueServer, connection: AsyncSocket, request: QueueRequest) {.async.}= 
  var queueResp = QueueResponse()
  defer:
    await connection.send(queueResp.toStrResponse())
    connection.close()

  try:
    case request.command
    of QueueCommand.GET:
      let dataOpt = server.queue.dequeue(request.topic)
      echo $dataOpt
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
      # echo "not implemented"
      let cleared = server.queue.clearqueue(request.topic)
      queueResp.code = if cleared.isSome: 0 else: 4
      queueResp.status = if cleared.isSome: $cleared.get else: $false
      if cleared.isSome: 
        if cleared.get == true: 
          queueResp.message = "store resetted" 
        else: 
          queueResp.message = "failed to reset store" 
      else: 
        queueResp.message = "failed to reset store, queue topic might not exist"
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


proc execute(server: QueueServer, client: AsyncSocket) {.thread async.} =
    var recvLine = await client.recvLine()
    if recvLine.len > 0:
      var request = server.parseRequest(recvLine)
      await server.processRequest(client, request)
    #else:
      #echo "Invalid request: ", recvLine


proc start* (server: QueueServer) {.async.} =
  if server.running == false:
    server.queue.startListener()
  var socket = newAsyncSocket(buffered=false)
  socket.setSockOpt(OptReuseAddr, true)
  socket.bindAddr(Port(server.port))
  socket.listen()

  var address = server.address
  while true:
    var client: AsyncSocket = await socket.accept()
    #await socket.acceptAddr(client, address)
    #echo "Cliented connected from: ", address
    await server.execute(client)
  
  #sync()
  socket.close()


