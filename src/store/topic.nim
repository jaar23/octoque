

type
  Topic* = object of RootObj
    name*: string
    channel*: Channel[string]


# proc `name=`* (t: ref Topic, name: string) {.inline.}= 
#   t.name = name
#
#
# proc name* (topic: ref Topic): string {.inline.} = 
#   return topic.name


proc queueInChannel* (topic: ref Topic): int =
  return topic.channel.peek()
