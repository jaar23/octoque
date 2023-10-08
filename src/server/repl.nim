import threadpool, net, strutils, terminal
import message


template stdoutCmd (msg: string) =
  stdout.setForegroundColor(fgYellow)
  stdout.write msg
  stdout.resetAttributes()


template stdoutData (msg: string) =
  stdout.setForegroundColor(fgDefault)
  stdout.write msg
  stdout.resetAttributes()


template stdoutResult (msg: string) =
  stdout.setForegroundColor(fgGreen)
  stdout.write msg
  stdout.resetAttributes()


template stdoutError (msg: string) =
  stdout.setForegroundColor(fgRed)
  stdout.write msg
  stdout.resetAttributes()


template stdoutWrite (msg: string) =
  stdout.resetAttributes()
  stdout.writeLine msg


proc handleDecline(resp: string) =
    let errMsg = resp.split(":")
    stdoutError "error   > "
    stdoutWrite errMsg[1]
 

proc acqConn(serverAddr: string, serverPort: int, line: string): Socket =
  var conn = net.dial(serverAddr, Port(serverPort))
  conn.send(line & "\n")
  var resp = conn.recvLine()
  if resp.strip().len == 0:
    return nil
  if resp.strip() == "PROCEED":
    return conn
  elif resp.startsWith("DECLINE"):
    handleDecline(resp)
  else:
    return nil


proc readResult(conn: Socket, numberOfMsg: uint8) = 
  for numOfMsg in 0.uint8..<numberOfMsg:
    var dataResp = conn.recvLine()
    if dataResp.strip().len > 0:
      stdoutResult "result  > "
      stdoutWrite dataResp


proc repl(serverAddr: string, serverPort: int): void =
  echo "start repl session"
  var headerLine: string
  var dataLine: string
  var acqConn = true
  var conn: Socket
  var running = true
  var qheader: QHeader
  while running:
    if conn != nil:
      if qheader.command == PUT or qheader.command == PUTACK:
        for row in 0.uint8()..<qheader.payloadRows:
          stdoutData "data    > "
          dataLine = readLine(stdin)
          if dataLine == "quit": 
            running = false
            break
          conn.send(dataLine & "\n")
      if qheader.command == DISPLAY:
        if qheader.topic == "*":
          qheader.numberOfMsg = 999
        else:
          qheader.numberOfMsg = 6
      readResult(conn, qheader.numberOfMsg)
      conn = nil
    else:
      stdoutCmd "command > "
      headerLine = readLine(stdin)
      if headerLine == "quit": 
        running = false
        break
      else:
        try:
          qheader = parseQHeader(headerLine)
          if qheader.command == PING:
            var conn = net.dial(serverAddr, Port(serverPort))
            conn.send(headerLine & "\n")
            var resp = conn.recvLine()
            if resp.startsWith("DECLINE"):
              handleDecline(resp)
            else:
              stdoutResult "result  > "
              stdoutWrite resp
          elif qheader.command == PUBLISH or qheader.command == UNSUBSCRIBE or 
          qheader.command == SUBSCRIBE:
            stdoutResult "result  > "
            stdoutWrite "this command does not support in repl currently"
          else:
            conn = acqConn(serverAddr, serverPort, headerLine)
        except:
          stdoutError "error   > "
          stdoutWrite getCurrentExceptionMsg()

  echo "exit repl session"
  quit(0)

proc replStart*(address: string, port: int): void =
  spawn repl(address, port)
