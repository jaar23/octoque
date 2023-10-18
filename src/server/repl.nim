## ===============================================
## rewrite to call connect to acquire connection
## maintain connection and making calls to qserver
## connect
## putack -> proceed -> data -> success
## put -> proceed -> data -> success
## get -> proceed -> data -> success
##
## ===============================================

import threadpool, net, strutils, terminal, message


var connected = false
const version = "v0.1.0"
const replMessage = """
     ooo    ccc  ttttt   ooo    qqq    u   u  eeeee
    o   o  c       t    o   o  q   q   u   u  e
    o   o  c       t    o   o  q   q   u   u  eeeee
    o   o  c       t    o   o  q  qq   u   u  e
     ooo    ccc    t     ooo    qqq q   uuu   eeeee
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
  stdoutResult "exit repl mode, bye \n"
  stdoutWrite ""
  connected = false
  quit(0)


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

proc acqConn(conn: var Socket, serverAddr: string, serverPort: int): bool =
  stdoutCmd "command > "
  var connLine = readLine(stdin)

  commandHistory.add(connLine)
  conn = net.dial(serverAddr, Port(serverPort))
  if connLine.toLowerAscii() == "quit":
    handleQuit()
  elif connLine == "help":
    handleHelp()
    return false
  conn.send(connLine & "\n")
  var resp = conn.recvLine()
  if resp.strip() == "CONNECTED":
    handleResult(resp)
    connected = true
    return true
  else:
    handleDecline(resp)
    connected = false
    return false

proc prepareSend(conn: Socket, line: string): bool =
  conn.send(line & "\n")
  var resp = conn.recvLine()
  if resp.strip().len == 0:
    return false
  if resp.strip() == "PROCEED":
    return true
  elif resp.startsWith("DECLINE"):
    handleDecline(resp)
    return false
  else:
    return true


proc sendCommand(conn: Socket, qheader: var QHeader): bool {.raises: CatchableError.} =
  stdoutCmd "command > "
  var commandLine = readLine(stdin)
  commandHistory.add(commandLine)
  if commandLine.toLowerAscii() == "quit":
    handleQuit()
  elif commandLine.toLowerAscii() == "history":
    for h in commandHistory:
      handleResult(h)
    return false
  elif commandLine.toLowerAscii() == "help":
    handleHelp()
    return false
  qheader = parseQHeader(commandLine)
  if qheader.command == PING:
    conn.send(commandLine & "\n")
    var resp = conn.recvLine()
    if resp.startsWith("DECLINE"):
      handleDecline(resp)
    else:
      handleResult(resp)
  elif qheader.command == PUBLISH or qheader.command == UNSUBSCRIBE or
  qheader.command == SUBSCRIBE:
    handleResult("this command does not support in repl currently")
  else:
    return prepareSend(conn, commandLine)

  
proc readResult(conn: Socket, numberOfMsg: uint8 = 1) =
  while true:
    var dataResp = conn.recvLine()
    if dataResp.startsWith("DECLINE"):
      handleDecline(dataResp)
    elif dataResp.endsWith("ENDOFRESP"):
      break
    elif dataResp.strip() == "PROCEED":
      continue
    elif dataResp.strip().len > 0:
      handleResult(dataResp)


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
  var proceed = false
  commandHistory = newSeq[string]()
  while true:
    try:
      if conn == nil and connected == false:
        discard acqConn(conn, serverAddr, serverPort)
      else: 
        if state == "command":
          proceed = sendCommand(conn, qheader)
          if not proceed:
            continue
          state = "result"
        elif state == "result":
          if qheader.command == PUT or qheader.command == PUTACK:
            for row in 0.uint8()..<qheader.payloadRows:
              stdoutData "data    > "
              var dataLine = readLine(stdin)
              if dataLine.toLowerAscii() == "quit":
                break
              conn.send(dataLine & "\n")
          readResult(conn, qheader.numberOfMsg)
          state = "command"
        else:
          stdoutError "error   > "
          stdoutWrite "unknown state"
          #handleDecline("DECLINE:unknown state")
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
  spawn replExecutor(address, port)
