import subscriber
import uuid4
import strformat

type
  PubSubTopic* = object
    name*: string
    gid: Uuid
    subscriber: ref Subscriber
    channel: Channel[string]


proc newPubSubTopic*(name: string, subscriber: ref Subscriber): ref PubSubTopic =
  var pbtopic = (ref PubSubTopic)()
  pbtopic.name = name
  pbtopic.channel.open()
  pbtopic.gid = uuid4.uuid4()
  pbtopic.subscriber = subscriber


proc push*(pbtopic: ref PubSubTopic, data: string): bool =
  try:
    let inQ = pbtopic.channel.trySend(data)
    if inQ:
      echo "data in queue"
    else:
      echo "failed to queue data"
    return inQ
  except:
    echo getCurrentExceptionMsg()


proc subscribe*(pbtopic: ref PubSubTopic) {.thread.} =
  try:
    echo &"[{getThreadId()}] serving {pbtopic.gid}"
    while true:
      let pubData = pbtopic.channel.recv()
      if pubData != "":
        let sent = pbtopic.subscriber.trySend(pubData)
        echo &"message sent: {sent}" 
      else:
        discard pbtopic.subscriber.trySend("\n")
  except:
    echo getCurrentExceptionMsg()
  finally:
    echo "exiting"

