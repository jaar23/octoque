import std/rdstdin
import threadpool, net, strutils


proc acqConn(serverAddr: string, serverPort: int, line: string): Socket =
  var conn = net.dial(serverAddr, Port(serverPort))
  conn.send(line & "\n")
  var resp = conn.recvLine()
  if resp.strip() == "PROCEED":
    return conn
  else:
    echo "error: " & resp
    return nil


proc repl(serverAddr: string, serverPort: int): void =
  echo "start repl session"
  var headerLine: string
  var dataLine: string
  var acqConn = true
  var conn: Socket
  while true:
    if conn != nil:
      let dataOk = readLineFromStdin("\n", dataLine)
      if not dataOk: break
      conn.send(dataLine & "\n")
      var dataResp = conn.recvLine()
      echo dataResp
      conn = nil
    else:
      let ok = readLineFromStdin("\n", headerLine)
      if not ok: break
      if headerLine.len > 0:
        conn = acqConn(serverAddr, serverPort, headerLine)
  echo "exit repl session"

proc replStart*(address: string, port: int): void =
  spawn repl(address, port)
