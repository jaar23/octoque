## message format
## parse message
## [HEADER]
## [PROTOCOL][KEEP ALIVE][LENGTH][STREAM/BATCH]
## [COMMAND][TOPIC]
## [PAYLOAD]
import strutils
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
    #CONNECT     = "CONNECT"
    #DISCONNECT  = "DISCONNECT"
    ACKNOWLEDGE = "ACKNOWLEDGE"

  Protocol* = enum
    OTQ,
    CUSTOM

  TransferMethod* = enum
    STREAM,
    BATCH

  QHeader* = object
    protocol*: Protocol
    transferMethod*: TransferMethod
    payloadRows*: uint8 = 1# number of payload rows
    numberOfMsg*: uint8 = 1# number of messages
    command*: QCommand
    topic*: string
    topicSize*: int = 0
    connectionType*: ConnectionType = BROKER
    lifespan*: int = 0
    numberofThread: uint = 2
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
  #of "CONNECT":
  #  result = CONNECT
  #of "DISCONNECT":
  #  result = DISCONNECT
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
#hello world
#XXXXXXXXXXXXXX
#TODO more elegant way to parse different command message
proc parseQHeader*(line: string): QHeader {.raises: [ParseError, ValueError].} =
  result = QHeader()
  let lineArr = line.split(" ")
  result.protocol = parseProtocol(lineArr[0])
  result.command = parseQCommand(lineArr[1])
  result.topic = lineArr[2].strip()

  if result.command == GET:
    result.numberOfMsg = lineArr[3].parseInt().uint8()
    result.transferMethod = parseTransferMethod(lineArr[4])

  if result.command == PUT or result.command == PUTACK:
    result.payloadRows = lineArr[3].parseInt().uint8()
    result.transferMethod = parseTransferMethod(lineArr[4])
    if lineArr.len > 5:
      result.lifespan = lineArr[5].parseInt()

  if result.command == NEW:
    if lineArr.len < 3:
      raise newException(ParseError, "Missing connection type for new topic")
    result.connectionType = parseTopicConnectionType(lineArr[3])
    if lineArr.len > 4:
      result.topicSize = lineArr[4].parseInt()
    if lineArr.len > 5:
      result.numberofThread = lineArr[5].parseInt().uint()
  # long running connection required keep alive
  # TODO: evaluate if long running connection is required
  # result.keepAlive = lineArr[3].parseInt().uint32()



