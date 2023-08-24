

type
  Topic* = object of RootObj
    name*: string
    channel: Channel[string]


proc start* (topic: ref Topic) {.inline.} = topic.channel.open()


proc readNext* (topic: ref Topic): string {.inline.} = topic.channel.recv()


proc peek* (topic: ref Topic): int {.inline.} = topic.channel.peek()
