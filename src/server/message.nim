## message format
## parse message
## [HEADER]
## [PROTOCOL][KEEP ALIVE][LENGTH][STREAM/BATCH]
## [COMMAND][TOPIC]
## [PAYLOAD]
import strutils

type
  QCommand* = enum
    GET         = "GET"
    PUT         = "PUT"
    PUTACK      = "PUTACK"
    PUBLISH     = "PUBLISH"
    SUBSCRIBE   = "SUBSCRIBE"
    UNSUBSCRIBE = "UNSUBSCRIBE"
    PING        = "PING"
    CLEAR       = "CLEAR"
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
    length*: uint32
    transferMethod*: TransferMethod
    payloadRows*: uint8 # number of payload rows
    numberOfMsg*: uint8 # number of messages
    command*: QCommand
    topic*: string
    # keepAlive*: uint32

  ParseError* = object of CatchableError


proc parseQCommand(command: string): QCommand {.raises: ParseError.} =
  let cmd = command.strip()
  case cmd
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
  #of "CONNECT":
  #  result = CONNECT
  #of "DISCONNECT":
  #  result = DISCONNECT
  of "ACKNOWLEDGE":
    result = ACKNOWLEDGE
  else:
    raise newException(ParseError, "invalid command")


proc parseProtocol(protocol: string): Protocol {.raises: ParseError.} =
  let ptl = protocol.strip()
  case ptl
  of "OTQ":
    result = OTQ
  of "CUSTOM":
    result = CUSTOM
  else:
    raise newException(ParseError, "invalid Protocol")


proc parseTransferMethod(mtd: string): TransferMethod {.raises: ParseError.} =
  let mtd = mtd.strip()
  case mtd
  of "BATCH":
    result = BATCH
  of "STREAM":
    result = STREAM
  else:
    raise newException(ParseError, "invalid transfer method")
  

#OTQ PUT default 1 BATCH 11
#hello world
#XXXXXXXXXXXXXX
proc parseQHeader*(line: string): QHeader {.raises: [ParseError, ValueError].} =
  result =  QHeader()
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
    result.length = lineArr[5].parseInt().uint32()
  # long running connection required keep alive
  # TODO: evaluate if long running connection is required
  # result.keepAlive = lineArr[3].parseInt().uint32()
  


