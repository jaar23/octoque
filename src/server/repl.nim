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
    #conn.send("OTQ UNSUBSCRIBE\n")
    handleQuit()
    quit(0)
  setControlCHook(handleCtrlC)
  stdoutInfo "ctrl+c to exit subscribe\n"
  while true and conn != nil:
    #echo "sub recv"
    #echo "b unsubscribe?" & $unsubscribe
    let recvData = conn.recvLine()
    #echo "sub send"
    if recvData.strip().len > 0:
      #echo "sub have data"
      if recvData.strip().startsWith("DECLINE"):
        handleDecline(recvData)
      elif recvData.strip().endsWith("ENDOFRESP"):
        return
      else:
        handleResult(recvData)
    else:
      conn.send("REPLPONG\n")
    #echo "unsubscribe?" & $unsubscribe
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
    # echo $getThreadId() & "waiting for feedback"
    var dataResp = conn.recvLine()
    # echo $getThreadId() & "'" & $dataResp & "'"
    if dataResp.strip() != "":
      if dataResp.startsWith("DECLINE"):
        handleDecline(dataResp)
      elif dataResp.strip().endsWith("ENDOFRESP"):
        break
      elif dataResp.strip() == "PROCEED":
        continue
      else:
        handleResult(dataResp)
  #echo "exit reading"


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


# proc disconnect(conn: var Socket): void =
#   conn.close()
#

# proc prepareSend(conn: Socket, line: string): bool =
#   conn.send(line & "\n")
#   var resp = conn.recvLine()
#   if resp.strip().len == 0:
#     return false
#   if resp.strip() == "PROCEED":
#     return true
#   elif resp.startsWith("DECLINE"):
#     handleDecline(resp)
#     return false
#   # elif resp.strip() == "PONG":
#   #   handleResult(resp)
#   #   return true
#   else:
#     return true


proc sendCommand(conn: var Socket, qheader: var QHeader): void {.raises: CatchableError.} =
  while true:
    stdoutCmd "command > "
    var commandLine = readLine(stdin)
    echo "command: " & commandLine
    if commandLine != "":
      commandHistory.add(commandLine)
      if commandLine.toLowerAscii() == "quit":
        handleQuit()
      elif commandLine.toLowerAscii() == "history":
        for h in commandHistory:
          handleResult(h)
        # return false
      elif commandLine.toLowerAscii() == "help":
        handleHelp()
        # return false
      qheader = parseQHeader(commandLine)
      conn.send(commandLine & "\r\L")
      break
  # if qheader.command == UNSUBSCRIBE:
  #   handleResult("this command does not support in repl mode")
  #   return false
  # elif qheader.command == PING:    
  #   conn.send(commandLine & "\n")
  #   #readResult(conn)
  #   return true
  # elif qheader.command == DISCONNECT:
  #   conn.send(commandLine & "\n")
  #   readResult(conn)
  #   conn = nil
  #   connected = false
  #   return false
  # else:
  #   return prepareSend(conn, commandLine)

proc sendPayload(conn: var Socket, qheader: QHeader): void =
  let proceed = conn.recvLine()
  echo "proceed?" & proceed
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
  #var proceed = false
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
          # proceed = sendCommand(conn, qheader)
          # if not proceed:
          #   continue
          state = "result"
        elif state == "result":
          echo qheader
          if qheader.command == PUT or qheader.command == PUTACK or
              qheader.command == PUBLISH:
            # for row in 0.uint8()..<qheader.payloadRows:
            #   stdoutData "data    > "
            #   var dataLine = readLine(stdin)
            #   if dataLine.toLowerAscii() == "quit":
            #     break
            #   conn.send(dataLine & "\n")
            sendPayload(conn, qheader)
            readResult(conn)
          elif qheader.command == SUBSCRIBE:
            handleSubscribe(conn)
          else:
            #echo "core rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrread"
            readResult(conn)
          state = "command"
        else:
          stdoutError "error   > "
          stdoutWrite "unknown state"
    except:
      handleDecline("DECLINE:" & getCurrentExceptionMsg())
  handleQuit()

# proc repl(serverAddr: string, serverPort: int): void =
#   echo "start repl session"
#   var headerLine: string
#   var dataLine: string
#   #var acqConn = true
#   var conn: Socket
#   var running = true
#   var qheader: QHeader
#   var state = "command"
#   while running:
#     if state != "command" and conn != nil:
#       if qheader.command == PUT or qheader.command == PUTACK:
#         for row in 0.uint8()..<qheader.payloadRows:
#           stdoutData "data    > "
#           dataLine = readLine(stdin)
#           if dataLine.toLowerAscii() == "quit":
#             running = false
#             break
#           conn.send(dataLine & "\n")
#       if qheader.command == DISPLAY:
#         if qheader.topic == "*":
#           qheader.numberOfMsg = 999
#         else:
#           qheader.numberOfMsg = 6
#       if qheader.command == PUTACK:
#         qheader.numberOfMsg = 2
#       readResult(conn, qheader.numberOfMsg)
#       #conn = nil
#       state = "command"
#     else:
#       stdoutCmd "command > "
#       headerLine = readLine(stdin)
#       if headerLine.toLowerAscii() == "quit":
#         running = false
#         break
#       else:
#         try:
#           qheader = parseQHeader(headerLine)
#           if qheader.command == PING:
#             var conn = net.dial(serverAddr, Port(serverPort))
#             conn.send(headerLine & "\n")
#             var resp = conn.recvLine()
#             if resp.startsWith("DECLINE"):
#               handleDecline(resp)
#             else:
#               stdoutResult "result  > "
#               stdoutWrite resp
#             state = "command"
#           elif qheader.command == PUBLISH or qheader.command == UNSUBSCRIBE or
#           qheader.command == SUBSCRIBE:
#             stdoutResult "result  > "
#             stdoutWrite "this command does not support in repl currently"
#             state = "command"
#           elif qheader.command == CONNECT:
#             conn = net.dial(serverAddr, Port(serverPort))
#             conn.send(headerLine & "\n")
#             var resp = conn.recvLine()
#             if resp != "PROCEED":
#               conn = nil
#             else:
#               stdoutResult "result > "
#               stdoutWrite "CONNECTED"
#           else:
#             discard prepareSend(conn, headerLine)
#             state = "result"
#         except:
#           stdoutError "error   > "
#           stdoutWrite getCurrentExceptionMsg()
#           state = "command"
#
#   echo "exit repl session"
#   quit(0)

proc replStart*(address: string, port: int) =
  replExecutor(address, port)
