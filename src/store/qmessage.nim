import times, marshal, base64

type
  QMessage* = object
    id: int
    topic: string
    queuedDateTime: float64
    consumedDateTime: float64
    data: string
    length: int
    base64Encoded: bool
    clientIp: string

proc id*(qmsg: QMessage): int = qmsg.id

proc topic*(qmsg: QMessage): string = qmsg.topic

proc length*(qmsg: QMessage): int = qmsg.length

proc data*(qmsg: QMessage): string = qmsg.data

proc queuedDateTime*(qmsg: QMessage): float64 = qmsg.queuedDateTime

proc consumedDateTime*(qmsg: QMessage): float64 = qmsg.consumedDateTime

proc base64Encoded*(qmsg: QMessage): bool = qmsg.base64Encoded

proc clientIp*(qmsg: QMessage): string = qmsg.clientIp

proc toJSON*(qmsg: QMessage): string =
  return $$qmsg

proc topic*(qmsg: ref QMessage): string = qmsg.topic

proc length*(qmsg: ref QMessage): int = qmsg.length

proc data*(qmsg: ref QMessage): string = qmsg.data

proc queuedDateTime*(qmsg: ref QMessage): float64 = qmsg.queuedDateTime

proc toJSON*(qmsg: ref QMessage): string =
  return $$qmsg[]


proc deqMessage*(qmsg: ref QMessage): string =
  qmsg.consumedDateTime = getTime().toUnixFloat()
  return qmsg.toJSON()




proc newQMessageRef*(id: int, topic: string, data: string,
                     queuedDateTime: float, base64Encode: bool): ref QMessage =
  let length = data.len
  var qdata = if base64Encode: encode(data) else: data
  var qmsg: ref QMessage = (ref QMessage)(
    id: id,
    topic: topic,
    data: qdata,
    queuedDateTime: queuedDateTime,
    length: length,
    consumedDateTime: 0
  )
  return qmsg


proc newQMessage*(topic: string, id: int, data: string, queuedDateTime: float,
    consumedDateTime: float, base64Encode: bool): QMessage =
  let length = data.len
  let id = getTime().toUnix()
  var qdata = if base64Encode: encode(data) else: data
  var qmsg: QMessage = QMessage(
    id: id,
    topic: topic,
    data: qdata,
    queuedDateTime: queuedDateTime,
    length: length,
    consumedDateTime: consumedDateTime
  )
  return qmsg


