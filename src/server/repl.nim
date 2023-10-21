## ===============================================
## rewrite to call connect to acquire connection
## maintain connection and making calls to qserver
## connect
## putack -> proceed -> data -> success
## put -> proceed -> data -> success
## get -> proceed -> data -> success
##
## ===============================================

import net, strutils, terminal, message


var connected = false
const version = "v0.1.0"
const replMessage = """
    ooo    ccc  ttttt   ooo    qqq    u   u  eeeee
   o   o  c       t    o   o  q   q   u   u  e
   o   o  c       t    o   o  q   q   u   u  eeeee
   o   o  c       t    o   o  q q q   u   u  e
    ooo    ccc    t     ooo    qq q    uuu   eeeee
"""
const lastUpdated = "17 October 2023"
var commandHistory {.threadvar.}: seq[string]


template stdoutCmd (msg: string) =
  stdout.setForegroundColor(fgYellow)
  stdout.write msg
  stdout.resetAttributes()


template stdoutInfo (msg: string) =
  stdout.setForegroundColor(fgBlue)
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


proc handleResult(resp: string) =
  stdoutResult "result  > "
  stdoutWrite resp


proc handleDecline(resp: string) =
  let errMsg = resp.split(":")
  stdoutError "error   > "
  stdoutWrite errMsg[1]


proc handleQuit() =
  stdoutResult "\nexit repl mode, bye \n"
  stdoutWrite ""
  connected = false
  quit(0)


proc handleSubscribe(conn: var Socket) =
  proc handleCtrlC() {.noconv.} =
    handleQuit()
    quit(0)
  setControlCHook(handleCtrlC)
  stdoutInfo "ctrl+c to exit subscribe\n"
  while true and conn != nil:
    let recvData = conn.recvLine()
    if recvData.strip().len > 0:
      if recvData.strip().startsWith("DECLINE"):
        handleDecline(recvData)
      elif recvData.strip().endsWith("ENDOFRESP"):
        return
      else:
        handleResult(recvData)
    else:
      conn.send("REPLPONG\n")
  unsetControlCHook()


proc handleHelp() =
  stdoutResult "Exmple command\n"
  echo ""
  stdoutResult "CONNECT\n"
  stdoutWrite "format: <otq> <CONNECT> <username> <password>"
  stdoutWrite "'otq connect admin password', login into queue manager"
  echo ""
  stdoutResult "DISPLAY\n"
  stdoutWrite "format: <otq> <DISPLAY> <topic>"
  stdoutWrite "'otq display default', to display the default topic"
  stdoutWrite "'otq display *', to display all topics"
  echo ""
  stdoutResult "PING\n"
  stdoutWrite "format: <otq> <PING> <topic>"
  stdoutWrite "'otq ping default', check connection to default topic"
  echo ""
  stdoutResult "PUT, PUTACK\n"
  stdoutWrite "format: <otq> <PUT, PUTACK> <topic> <number-of-message> <batch>"
  stdoutWrite "'otq put default 1 batch', put one message to default topic with batch mode"
  echo ""
  stdoutResult "GET\n"
  stdoutWrite "format: <otq> <GET> <topic> <number-of-message> <batch>"
  stdoutWrite "'otq get default 1 batch', get one message from default topic with batch mode"
  echo ""
  stdoutResult "NEW\n"
  stdoutWrite "format: <otq> <NEW> <topic> <connection-type>"
  stdoutWrite "'otq new topic1 broker, new topic named topic1 with broker mode"
  stdoutWrite "'otq new topic2 pubsub, new topic named topic2 with pubsub mode"
  echo ""
  stdoutResult "CLEAR\n"
  stdoutWrite "format: <otq> <CLEAR> <topic>"
  stdoutWrite "'otq clear default', clear all message inside default topic"
  echo ""


proc readResult(conn: Socket) =
  while true:
    var dataResp = conn.recvLine()
    if dataResp.strip() != "":
      if dataResp.startsWith("DECLINE"):
        handleDecline(dataResp)
      elif dataResp.strip().endsWith("ENDOFRESP"):
        break
      elif dataResp.strip() == "PROCEED":
        continue
      else:
        handleResult(dataResp)


proc acqConn(conn: var Socket, serverAddr: string, serverPort: int): bool =
  while true:
    stdoutCmd "command > "
    var connLine = readLine(stdin)
    if connLine.len > 0:
      if connLine.toLowerAscii() == "quit":
        handleQuit()
        break
      elif connLine == "help":
        handleHelp()
        return false
      commandHistory.add(connLine)
      conn = net.dial(serverAddr, Port(serverPort))
      conn.send(connLine & "\n")
      var resp = conn.recvLine()
      if resp.strip() == "CONNECTED":
        handleResult(resp)
        connected = true
      else:
        handleDecline(resp)
        connected = false
      readResult(conn)
      return connected



proc sendCommand(conn: var Socket, qheader: var QHeader): void {.raises: CatchableError.} =
  while true:
    stdoutCmd "command > "
    var commandLine = readLine(stdin)
    if commandLine != "":
      commandHistory.add(commandLine)
      if commandLine.toLowerAscii() == "quit":
        handleQuit()
      elif commandLine.toLowerAscii() == "history":
        for h in commandHistory:
          handleResult(h)
        continue
      elif commandLine.toLowerAscii() == "help":
        handleHelp()
        continue
      qheader = parseQHeader(commandLine)
      conn.send(commandLine & "\r\L")
      break


proc sendPayload(conn: var Socket, qheader: QHeader): void =
  let proceed = conn.recvLine()
  #echo "proceed?" & proceed
  if proceed.strip() == "PROCEED":
    for row in 0.uint8()..<qheader.payloadRows:
      stdoutData "data    > "
      var dataLine = readLine(stdin)
      if dataLine.toLowerAscii() == "quit":
        break
      conn.send(dataLine & "\n")
  else:
    handleDecline(proceed)



proc replExecutor(serverAddr: string, serverPort: int): void =
  stdoutResult "-----------------------------------------------------\n"
  stdoutResult replMessage
  stdoutResult "-----------------------------------------------------\n"
  echo version & ", " & lastUpdated
  stdoutData "octoque is running on " & hostOS
  stdoutInfo " (" & serverAddr & ":" & $serverPort & ")\n"
  echo ""
  echo "Welcome to octoque REPL. Type 'help' for list of "
  echo "available command, 'history' for display the commands "
  echo "has sent out."
  echo "Type quit or Ctrl-C to exit octoque."
  echo ""

  var conn: Socket = nil
  var qheader: QHeader
  var state = "command"
  commandHistory = newSeq[string]()
  while true:
    try:
      if conn == nil and connected == false:
        let acq = acqConn(conn, serverAddr, serverPort)
        if not acq: conn = nil
      else:
        if state == "command":
          qheader = new(QHeader)[]
          sendCommand(conn, qheader)
          state = "result"
        elif state == "result":
          #echo qheader
          if qheader.command == PUT or qheader.command == PUTACK or
              qheader.command == PUBLISH:
            sendPayload(conn, qheader)
            readResult(conn)
          elif qheader.command == SUBSCRIBE:
            handleSubscribe(conn)
          else:
            readResult(conn)
          state = "command"
        else:
          stdoutError "error   > "
          stdoutWrite "unknown state"
    except:
      handleDecline("DECLINE:" & getCurrentExceptionMsg())
  handleQuit()


proc replStart*(address: string, port: int) =
  replExecutor(address, port)
