import 
  server/qserver, store/qtopic
import asyncdispatch

# proc closureProc (x: int, y: int): int =
#   return x + y
#

## TODO: init from config file
proc main() {.async.} = 
  var topics = @["default", "alter"]
  var pbtopics = @[""]
  #let server = initQueueServer("127.0.0.1", 6789, topics, 2)
  let server = newQueueServer("127.0.0.1", 6789)
  server.addQueueTopic("default")
  server.addQueueTopic("pubsub", PUBSUB)
  await server.start()
  

when isMainModule:
  echo "octobus is started at 127.0.0.1:6789"
  asyncCheck main()
  runForever()
  echo "Server terminated"
  #testClosure(5, closureProc)
  # var qtopic = initQTopic("default")
  # var qtopic2 = initQTopic("alter")
  # let startTime = cpuTime()
  # spawn qtopic.producer()
  # spawn qtopic2.producer()
  # sync(
  # while qtopic.channel.peek() > 0:
  #   sleep(3000)
  #   qtopic.consumer()
  # echo qtopic.channel.peek()
  # var running = true
  # while running:
  #   spawn qtopic.consumer()
  #   spawn qtopic2.consumer()
  #   sync()
  #   if qtopic.channel.peek() == 0 and  qtopic2.channel.peek() == 0:
  #     echo "no more message"
  #     running = false
  #   else:
  #     echo "default: ", qtopic.channel.peek()
  #     echo "alter: ", qtopic2.channel.peek()
  # echo "took ", cpuTime() - startTime, "s to finish"
  # echo "bye..."
  # channel.open()
  # spawn producer()
  # spawn consumer()
  # spawn consumer()
  # spawn producer()
  # sync()
