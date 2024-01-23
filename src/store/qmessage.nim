import times, marshal, base64

type
  QMessage* = object
    id: int
    topic: string
    queueDateTime: float64
    dequeueDateTime: float64
    data: string
    length: int
    base64Encoded: bool


proc toJSON*(qmsg: ref QMessage): string =
  return $$qmsg[]


proc deqMessage*(qmsg: ref QMessage): string =
  qmsg.dequeueDateTime = getTime().toUnixFloat()
  return qmsg.toJSON()


proc length*(qmsg: ref QMessage): int = qmsg.length


proc data*(qmsg: ref QMessage): string = qmsg.data


proc newQMessage*(topic: string, data: string,
    base64Encode: bool): ref QMessage =
  let length = data.len
  let queueDateTime = getTime().toUnixFloat()
  let id = getTime().toUnix()
  var qdata = if base64Encode: encode(data) else: data
  var qmsg: ref QMessage = (ref QMessage)(
    id: id,
    topic: topic,
    data: qdata,
    queueDateTime: queueDateTime,
    length: length,
    dequeueDateTime: 0
  )
  return qmsg


