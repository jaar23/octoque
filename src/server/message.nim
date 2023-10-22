## message format
## parse message
## [HEADER]
## [PROTOCOL][KEEP ALIVE][LENGTH][STREAM/BATCH]
## [COMMAND][TOPIC]
## [PAYLOAD]
import strutils, errcode
from ../store/qtopic import ConnectionType

type
  QCommand* = enum
    GET = "GET"
    PUT = "PUT"
    PUTACK = "PUTACK"
    PUBLISH = "PUBLISH"
    SUBSCRIBE = "SUBSCRIBE"
    UNSUBSCRIBE = "UNSUBSCRIBE"
    PING = "PING"
    CLEAR = "CLEAR"
    NEW = "NEW"
    DISPLAY = "DISPLAY"
    CONNECT = "CONNECT"
    DISCONNECT = "DISCONNECT"
    ACKNOWLEDGE = "ACKNOWLEDGE"

  Protocol* = enum
    OTQ,
    CUSTOM

  TransferMethod* = enum
    STREAM,
    BATCH

  ## not the best design, changes is required here
  QHeader* = object
    protocol*: Protocol
    transferMethod*: TransferMethod = BATCH
    payloadRows*: uint8 = 1 # number of payload rows
    numberOfMsg*: uint8 = 1 # number of messages
    command*: QCommand
    topic*: string
    topicSize*: int = 0
    connectionType*: ConnectionType = BROKER
    lifespan*: int = 0
    numberofThread*: uint = 1
    username*: string
    password*: string
    #length*: uint32
    # keepAlive*: uint32

  ParseError* = object of CatchableError


proc parseQCommand(command: string): QCommand {.raises: ParseError.} =
  let cmd = command.strip()
  case cmd.toUpperAscii()
  of "GET":
    result = GET
  of "PUT":
    result = PUT
  of "PUTACK":
    result = PUTACK
  of "PUBLISH":
    result = PUBLISH
  of "SUBSCRIBE":
    result = SUBSCRIBE
  of "UNSUBSCRIBE":
    result = UNSUBSCRIBE
  of "PING":
    result = PING
  of "CLEAR":
    result = CLEAR
  of "DISPLAY":
    result = DISPLAY
  of "CONNECT":
    result = CONNECT
  of "DISCONNECT":
    result = DISCONNECT
  of "NEW":
    result = NEW
  of "ACKNOWLEDGE":
    result = ACKNOWLEDGE
  else:
    raise newException(ParseError, "Invalid command")


proc parseProtocol(protocol: string): Protocol {.raises: ParseError.} =
  let ptl = protocol.strip()
  case ptl.toUpperAscii()
  of "OTQ":
    result = OTQ
  of "CUSTOM":
    result = CUSTOM
  else:
    raise newException(ParseError, "Invalid Protocol")


proc parseTransferMethod(mtd: string): TransferMethod {.raises: ParseError.} =
  let mtd = mtd.strip()
  case mtd.toUpperAscii()
  of "BATCH":
    result = BATCH
  of "STREAM":
    result = STREAM
  else:
    raise newException(ParseError, "Invalid transfer method")


proc parseTopicConnectionType(topicType: string): ConnectionType {.raises: ParseError.} =
  let ttype = topicType.strip()
  case ttype.toUpperAscii():
  of "BROKER":
    result = BROKER
  of "PUBSUB":
    result = PUBSUB
  else:
    raise newException(ParseError, "Invalid connection type, accept only BROKER, PUBSUB")


#OTQ PUT default 1 BATCH 11
proc parseQHeader*(line: string): QHeader {.raises: [ParseError, ValueError].} =
  result = QHeader()
  let lineArr = line.split(" ")
  result.protocol = if lineArr.len > 0:
    parseProtocol(lineArr[0]) else: raise newException(ParseError, "Missing protocol")
  result.command = if lineArr.len > 1:
    parseQCommand(lineArr[1]) else: raise newException(ParseError, "Missing command")

  if result.command == DISCONNECT:
    return result
  else:
    result.topic = if lineArr.len > 2:
      lineArr[2].strip() else: raise newException(ParseError, "Missing topic name")

  if result.command == GET:
    result.numberOfMsg = if lineArr.len > 3:
      lineArr[3].parseInt().uint8() else: raise newException(ParseError, "Missing number of message to retrieve")
    result.transferMethod = if lineArr.len > 4:
      parseTransferMethod(lineArr[4]) else: raise newException(ParseError, "Missing  transfer method")

  if result.command == PUT or result.command == PUTACK or result.command == PUBLISH:
    result.payloadRows = if lineArr.len > 3:
      lineArr[3].parseInt().uint8() else: raise newException(ParseError, "Missing number of payload message")
    result.transferMethod = if lineArr.len > 4:
      parseTransferMethod(lineArr[4]) else: raise newException(ParseError, "Missing transfer method")
    if lineArr.len > 5:
      result.lifespan = lineArr[5].parseInt()

  if result.command == NEW:
    if lineArr.len < 3:
      raise newException(ParseError, "Missing connection type for new topic")
    result.connectionType = parseTopicConnectionType(lineArr[3])
    if lineArr.len > 4:
      if lineArr[4].startsWith("T") or lineArr[4].startsWith("t"):
        let numberOfThread = lineArr[4].substr(1, lineArr[4].len - 1)
        result.numberofThread = numberOfThread.parseInt().uint()
      else:
        result.topicSize = lineArr[4].parseInt()
    if lineArr.len > 5:
      if lineArr[5].startsWith("T") or lineArr[5].startsWith("t"):
        let numberOfThread = lineArr[5].substr(1, lineArr[5].len - 1)
        result.numberofThread = numberOfThread.parseInt().uint()
      else:
        raise newException(ParseError, "Invalid number of thread format, number always starts with T")

  if result.command == CONNECT:
    if lineArr.len < 3:
      raise newException(ParseError, $MISSING_PARAMETER & ", username or password")
    result.username = lineArr[2]
    result.password = lineArr[3]


  # long running connection required keep alive
  # TODO: evaluate if long running connection is required
  # result.keepAlive = lineArr[3].parseInt().uint32()



