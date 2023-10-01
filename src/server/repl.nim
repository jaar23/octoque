import rdstdin,terminal
import threadpool, net, strutils


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
  var command = ""
  while running:
    if conn != nil:
      if command == "PUT":
        stdout.write "data    >"
        dataLine = readLine(stdin)
        #if not dataOk: break
        if dataLine == "quit": 
          running = false
          break
        conn.send(dataLine & "\n")
      var dataResp = conn.recvLine()
      if dataResp.strip().len == 0:
        stdout.writeLine "result  >empty response"
      else:
        stdout.writeLine "result  >" & dataResp
      conn = nil
    else:
      stdout.write "command >"
      #let ok = readLineFromStdin("\n", headerLine)
      headerLine = readLine(stdin)
      #if not ok: break
      if headerLine == "quit": 
        running = false
        break
      if headerLine.len > 0:
        conn = acqConn(serverAddr, serverPort, headerLine)
        if headerLine.toUpperAscii().contains("PUT") or 
        headerLine.toUpperAscii().contains("PUB"):
          command = "PUT"
        elif headerLine.toUpperAscii().contains("PING"):
          var resp = conn.recvLine()
          #stdout.write "data   >"
          stdout.writeLine "result  >" & resp
        else:
          command = "GET"
  echo "exit repl session"
  quit(0)

proc replStart*(address: string, port: int): void =
  spawn repl(address, port)
