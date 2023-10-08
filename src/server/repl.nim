import threadpool, net, strutils
import message

proc acqConn(serverAddr: string, serverPort: int, line: string): Socket =
  var conn = net.dial(serverAddr, Port(serverPort))
  conn.send(line & "\n")
  var resp = conn.recvLine()
  if resp.strip().len == 0:
    return nil
  if resp.strip() == "PROCEED":
    return conn
  else:
    return nil


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
          stdout.write "data    > "
          dataLine = readLine(stdin)
          if dataLine == "quit": 
            running = false
            break
          conn.send(dataLine & "\n")
      for numOfMsg in 0.uint8..<qheader.numberOfMsg:
        var dataResp = conn.recvLine()
        if dataResp.strip().len > 0:
          stdout.writeLine "result  > " & dataResp
      conn = nil
    else:
      stdout.write "command > "
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
            stdout.writeLine "result  > " & resp
          elif qheader.command == PUBLISH or qheader.command == UNSUBSCRIBE or 
          qheader.command == SUBSCRIBE:
            stdout.writeLine "result  > " & "this command does not support in repl currently"
          else:
            conn = acqConn(serverAddr, serverPort, headerLine)
        except:
          stdout.writeLine "error   > " & getCurrentExceptionMsg()

  echo "exit repl session"
  quit(0)

proc replStart*(address: string, port: int): void =
  spawn repl(address, port)
