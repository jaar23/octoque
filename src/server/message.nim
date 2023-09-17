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
    CONNECT     = "CONNECT"
    DISCONNECT  = "DISCONNECT"
    ACKNOWLEDGE = "ACKNOWLEDGE"
  
  Protocol* = enum
    OTQ,
    CUSTOM

  TransferMethod* = enum
    STREAM,
    BATCH

  QHeader* = object
    protocol*: Protocol
    keepAlive*: uint32
    length*: uint32
    transferMethod*: TransferMethod
    payloadRows*: uint8
    batchNumber*: uint8
    command*: QCommand
    topic*: string

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
  of "CONNECT":
    result = CONNECT
  of "DISCONNECT":
    result = DISCONNECT
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
  

#OTQ  BATCH 1 3600 4000000 PUT DEFAULT 2
#XXXXXXXXXXXXXX
proc parseQHeader*(line: string): QHeader {.raises: [ParseError, ValueError].} =
  result =  QHeader()
  let lineArr = line.split(" ")
  result.protocol = parseProtocol(lineArr[0])
  result.transferMethod = parseTransferMethod(lineArr[1])
  result.payloadRows = lineArr[2].parseInt().uint8()
  result.keepAlive = lineArr[3].parseInt().uint32()
  result.length = lineArr[4].parseInt().uint32()
  result.command = parseQCommand(lineArr[5])
  result.topic = lineArr[6].strip()
  result.batchNumber = lineArr[7].parseInt().uint8()
  


