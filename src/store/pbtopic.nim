import std/[asyncnet, asyncdispatch]
import subscriber, threadpool, topic

type
  PubSubTopic* = object of Topic
    subscriptions: seq[Subscriber]
    store: Channel[string]


proc initPubSubTopic* (name: string): ref PubSubTopic =
  var pbtopic = (ref PubSubTopic)(name: name)
  pbtopic.channel.open()
  pbtopic.store.open()
  return pbtopic


proc name* (pbtopic: ref PubSubTopic): string =
  return pbtopic.name


proc subscribe* (pbtopic: ref PubSubTopic, subscriber: Subscriber): void = 
  pbtopic.subscriptions.add(subscriber)


proc publish* (pbtopic: ref PubSubTopic, data: string) {.async.} =
  for s in pbtopic.subscriptions:
    await s.send(data)


proc listen* (pbtopic: ref PubSubTopic) {.thread async.} =
  while true:
    let recvData = pbtopic.channel.recv()
    await pbtopic.publish(recvData)
    echo "published"
