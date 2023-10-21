import qtopic, std/options, threadpool, subscriber, net, strformat, sequtils, sugar
import octolog
from uuid4 import initUuid
import ../server/errcode

type
  QueueState = enum
    RUNNING, PAUSED, STOPPED, STARTED

  Queue* = object
    topics*: seq[ref QTopic]
    state: QueueState
    topicSize: uint8

  QueueError* = object of CatchableError


proc find*(self: ref Queue, topicName: string): Option[ref QTopic] =
  result = none(ref QTopic)
  if topicName == "":
    return result
  for q in self.topics:
    if q.name == topicName:
      result = some(q)
      break

proc addTopic*(queue: ref Queue, topic: ref QTopic): void {.raises: QueueError.} =
  info("new topic\t" & topic.name & "\t(0)\t" & $topic.connectionType)
  if queue.topics.len > queue.topicSize.int():
    raise newException(QueueError, $EXCEED_ALLOWED_TOPIC &
        " , maximum topic size is " & $queue.topicSize)
  if queue.find(topic.name).isSome(): raise newException(QueueError,
      $TOPIC_EXISTED)
  queue.topics.add(topic)


proc addTopic*(queue: ref Queue, topicName: string,
    connType: ConnectionType = BROKER, capacity: int = 0): void =
  info(&"new topic\t{topicName}\t({capacity})\t{connType}")
  if queue.topics.len > queue.topicSize.int():
    raise newException(QueueError, $EXCEED_ALLOWED_TOPIC &
        " , maximum topic size is " & $queue.topicSize)
  if queue.find(topicName).isSome(): raise newException(QueueError,
      $TOPIC_EXISTED)

  if capacity > 0:
    var qtopic = initQTopic(topicName, capacity, connType)
    queue.topics.add(qtopic)
  else:
    var qtopic = initQTopicUnlimited(topicName, connType)
    queue.topics.add(qtopic)


proc hasTopic*(queue: ref Queue, topicName: string): bool =
  queue.topics.filter(q => q.name == topicName).len > 0


proc enqueue*(self: ref Queue, topicName: string, data: string): Option[int] =
  debug(&"enqueue new message to {topicName}")
  var numOfMessage = 0
  var topic: Option[ref QTopic] = self.find(topicName)
  if topic.isSome:
    topic.get.send(data)
    numOfMessage = topic.get.size()
  else:
    info(&"topic not found, {topicName}")
    return none(int)
  return some(numOfMessage)


proc dequeue*(self: ref Queue, topicName: string, batchNum: uint8 = 1): Option[
    seq[string]] =
  debug(&"dequeue {batchNum} of message from {topicName}")
  var topic: Option[ref QTopic] = self.find(topicName)
  var outData = newSeq[string]()
  if topic.isSome:
    for n in 0..<batchNum.int():
      var data: Option[string] = topic.get.recv()
      if data.isSome:
        outData.add(data.get)
    result = some(outData)
  else:
    info(&"topic not found, {topicName}")
    return none(seq[string])


proc clearqueue*(queue: ref Queue, topicName: string): Option[bool] =
  debug(&"clear message in {topicName}")
  var topic: Option[ref QTopic] = queue.find(topicName)
  if topic.isSome:
    let cleared = topic.get.clear()
    return some(cleared)
  else:
    info(&"topic not found, {topicName}")
    return none(bool)


proc countqueue*(queue: ref Queue, topicName: string): int =
  debug(&"count number of message in {topicName}")
  var topic: Option[ref QTopic] = queue.find(topicName)
  if topic.isSome:
    let count = topic.get.size()
    return count
  else:
    info(&"topic not found, {topicName}")
    return 0


proc startListener*(queue: ref Queue, numOfThread: int = 2): void =
  info(&"BROKER topic has {numOfThread} worker(s)")
  info(&"PUBSUB topic has 1 worker")
  for t in 0 ..< queue.topics.len:
    if queue.topics[t].connectionType == ConnectionType.PUBSUB:
      spawn queue.topics[t].listen()
    else:
      for n in 0 ..< numOfThread:
        spawn queue.topics[t].listen()
  info(&"topic is currently listening for requests")


proc startTopicListener*(queue: ref Queue, topicName: string,
    numOfThread: int = 2): void =
  info(&"BROKER topic has {numOfThread} worker(s)")
  info(&"PUBSUB topic has 1 worker")
  let topic = queue.find(topicName)
  if topic.isSome:
    if topic.get.connectionType == BROKER:
      for t in 0..<numOfThread:
        spawn topic.get.listen()
    else:
      spawn topic.get.listen()
  info(&"topic({topicName}) is currently listening for requests")


proc subscribe*(queue: ref Queue, topicName: string,
    connection: Socket): void {.raises: CatchableError.} =
  defer:
    info "synchronizing remaining threads"
    sync()
    info "thread synchronized"

  info(&"pubsub running on {getThreadId()}")
  var topic: Option[ref QTopic] = queue.find(topicName)
  var subscriber = newSubscriber(connection, $getThreadId())
  try:
    if topic.isSome:
      if topic.get.connectionType != PUBSUB:
        error(&"{topicName} is not subscribable")
        raise newException(CatchableError, &"{topicName} is not subscribable")
      else:
        info($subscriber)
        topic.get.subscribe(subscriber)
        info(&"{getThreadId()} exit...")
        subscriber.close()
    else:
      info(&"{topicName} not found")
      raise newException(CatchableError, &"{topicName} not found")
  except:
    raise newException(CatchableError, getCurrentExceptionMsg())
  finally:
    if topic.isSome:
      info(&"{getThreadId()} exit thread")
      topic.get.unsubscribe(subscriber)


proc unsubscribe*(queue: ref Queue, topicName: string, connId: string): void =
  var connectionId = initUuid(connId)
  var topic: Option[ref QTopic] = queue.find(topicName)
  try:
    if topic.isSome:
      topic.get.unsubscribe(connectionId)
  except:
    error(getCurrentExceptionMsg())


proc newQueue*(topicSize: uint8 = 8): ref Queue =
  info("initialize new queue")
  var queue = (ref Queue)(state: QueueState.STARTED)
  queue.topics = newSeq[ref QTopic]()
  queue.topicSize = topicSize.uint8()
  return queue


proc initQueue*(topicNames: varargs[string],
                topicSize: uint8 = 8): ref Queue {.raises: QueueError.} =
  info("initialize new queue with topics")
  var queue = (ref Queue)(state: QueueState.STARTED)
  queue.topicSize = topicSize
  if topicNames.len > topicSize.int():
    raise newException(QueueError, $EXCEED_ALLOWED_TOPIC &
        " maximum topic size is " & $topicSize)
  for name in items(topicNames):
    var topic = qtopic.initQTopicUnlimited(name)
    queue.addTopic(topic)
  return queue


proc initQueue*(topics: varargs[ref QTopic],
                topicSize: uint8 = 8): ref Queue {.raises: QueueError.} =
  info("initialize new queue with topics")
  var queue = (ref Queue)(state: QueueState.STARTED)
  queue.topicSize = topicSize
  if topics.len > topicSize.int():
    raise newException(QueueError, $EXCEED_ALLOWED_TOPIC &
        " maximum topic size is " & $topicSize)
  for topic in items(topics):
    queue.addTopic(topic)
  return queue


