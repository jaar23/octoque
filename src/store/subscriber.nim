import std/[asyncnet, asyncdispatch]
import uuid4

type
  Subscriber* = object
    connection: AsyncSocket
    connectionId*: Uuid


proc newSubscriber* (conn: AsyncSocket): Subscriber =
  result = Subscriber()
  result.connectionId = uuid4()
  result.connection = conn


proc notify* (subscriber: Subscriber): Future[void] {.async.} = 
  await subscriber.connection.send("new message...")


proc send* (subscriber: Subscriber, data: string): Future[void] {.async.} =
  await subscriber.connection.send(data)
