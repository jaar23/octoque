import qtopic, std/options, threadpool, pbtopic

type QueueState = enum
  RUNNING,PAUSED,STOPPED,STARTED


type Queue* = object
  topics*: seq[ref QTopic]
  pbtopics*: seq[ref PubSubTopic]
  state: QueueState


proc initQueue* (topicNames: varargs[string]): ref Queue =
  var queue = (ref Queue)(state:QueueState.STARTED)
  for name in items(topicNames):
    var topic = qtopic.initQTopicUnlimited(name)
    queue.topics.add(topic)
  return queue


proc find (self: ref Queue, topicName: string): Option[ref QTopic] = 
  result = none(ref QTopic)
  if topicName == "":
    return result
  #echo "looking for: |", topicName ,"|"
  for q in 0.. self.topics.len - 1: 
    #echo "topic seq", q
    #echo $self.topics[q].name
    if self.topics[q].name() == topicName:
      result = some(self.topics[q])
      break
  


proc enqueue* (self: ref Queue, topicName: string, data: string): Option[int] = 
  var numOfMessage = 0
  var topic: Option[ref QTopic] = self.find(topicName)
  if topic.isSome:
    topic.get.send(data)
    numOfMessage = topic.get.size()
  else:
    return none(int)
  return some(numOfMessage)


proc dequeue* (self: ref Queue, topicName: string): Option[string] = 
  var topic: Option[ref QTopic] = self.find(topicName)
  if topic.isSome:
    var data: Option[string] = topic.get.recv()
    if data.isSome:
      result = some(data.get)
    else: 
      result = some("")
  else:
    return none(string)


proc clearqueue* (queue: ref Queue, topicName: string): Option[bool] = 
  var topic: Option[ref QTopic] = queue.find(topicName)
  if topic.isSome:
    let cleared = topic.get.clear()
    return some(cleared)
  else:
    return none(bool)


proc startListener* (queue: ref Queue, numOfThread: int = 3): void = 
  #echo "topic size: ", queue.topics.len
  for t in 0.. queue.topics.len - 1:
    for n in 0.. numOfThread - 1:
      spawn queue.topics[t].listen()
