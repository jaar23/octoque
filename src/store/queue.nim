import qtopic, std/options, threadpool, subscriber, net


type QueueState = enum
  RUNNING, PAUSED, STOPPED, STARTED


type
  Queue* = object
    topics*: seq[ref QTopic]
    state: QueueState


proc newQueue*(): ref Queue =
  var queue = (ref Queue)(state: QueueState.STARTED)
  queue.topics = newSeq[ref QTopic]()
  return queue

proc initQueue*(topicNames: varargs[string]): ref Queue =
  var queue = (ref Queue)(state: QueueState.STARTED)
  for name in items(topicNames):
    var topic = qtopic.initQTopicUnlimited(name)
    queue.topics.add(topic)
  return queue

proc initQueue*(topics: varargs[ref QTopic]): ref Queue =
  var queue = (ref Queue)(state: QueueState.STARTED)
  for topic in items(topics):
    queue.topics.add(topic)
  return queue


proc addTopic*(queue: ref Queue, topic: ref QTopic): void = queue.topics.add(topic)


proc addTopic*(queue: ref Queue, topicName: string,
    connType: ConnectionType = BROKER, capacity: int = 0): void =
  if capacity > 0:
    var qtopic = initQTopic(topicName, capacity, connType)
    queue.topics.add(qtopic)
  else:
    var qtopic = initQTopicUnlimited(topicName, connType)
    queue.topics.add(qtopic)


proc find (self: ref Queue, topicName: string): Option[ref QTopic] =
  result = none(ref QTopic)
  if topicName == "":
    return result
  for q in self.topics:
    if q.name == topicName:
      result = some(q)
      break


proc enqueue*(self: ref Queue, topicName: string, data: string): Option[int] =
  var numOfMessage = 0
  var topic: Option[ref QTopic] = self.find(topicName)
  if topic.isSome:
    topic.get.send(data)
    numOfMessage = topic.get.size()
  else:
    return none(int)
  return some(numOfMessage)


proc dequeue*(self: ref Queue, topicName: string, batchNum: int = 1): Option[
    seq[string]] =
  var topic: Option[ref QTopic] = self.find(topicName)
  var outData = newSeq[string]()
  if topic.isSome:
    for n in 0..batchNum - 1:
      var data: Option[string] = topic.get.recv()
      if data.isSome:
        outData.add(data.get)

    result = some(outData)
  else:
    return none(seq[string])


proc clearqueue*(queue: ref Queue, topicName: string): Option[bool] =
  var topic: Option[ref QTopic] = queue.find(topicName)
  if topic.isSome:
    let cleared = topic.get.clear()
    return some(cleared)
  else:
    return none(bool)


proc countqueue*(queue: ref Queue, topicName: string): int =
  var topic: Option[ref QTopic] = queue.find(topicName)
  if topic.isSome:
    let count = topic.get.size()
    return count
  else:
    return 0

proc startListener*(queue: ref Queue, numOfThread: int = 3): void =
  for t in 0 .. queue.topics.len - 1:
    if queue.topics[t].connectionType == ConnectionType.PUBSUB:
      spawn queue.topics[t].listen()
    else:
      for n in 0 .. numOfThread - 1:
        spawn queue.topics[t].listen()


# proc publish*(queue: ref Queue, topicName: string, data: string): Option[bool] =
#   var topic: Option[ref QTopic] = queue.find(topicName)
#   if topic.isSome:
#     #topic.get.publish(data)
#     return some(true)
#   else:
#     return none(bool)


proc subscribe*(queue: ref Queue, topicName: string,
    connection: Socket): void {.thread.} =
  echo "pubsub running on " & $getThreadId()
  var topic: Option[ref QTopic] = queue.find(topicName)
  var subscriber = newSubscriber(connection, $getThreadId())
  try:
    if topic.isSome:
      if topic.get.connectionType != PUBSUB:
        echo "topic is not subscribable"
      else:
        echo "-----------------------------------------\n\n"
        echo $subscriber & "\n"
        topic.get.subscribe(subscriber)
        echo $getThreadId() & " exit..."
    else:
      echo "topic not found"
  except:
    echo getCurrentExceptionMsg()
  finally:
    if topic.isSome:
      echo $getThreadId() & " exit thread"
      topic.get.unsubscribe(subscriber)

# proc subscribe2* (queue: ref Queue, topicName: string, client: AsyncSocket) {.thread, async.} =
#   var topic: Option[ref QTopic] = queue.find(topicName)
#   if topic.isSome:
#     if topic.get.connectionType != PUBSUB:
#       echo "topic is not subscribable"
#       await client.send("topic is not subscribable\n")
#       client.close()
#     else:
#       topic.get.subscribe(subscriber)
#       #echo "new subscriber..."
#       return some(true)
#   else:
#     echo "topic not found"
#     await client.send("client not found")
#     client.close()


