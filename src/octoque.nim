import server/qserver, store/qtopic
import octolog, os, strutils


## TODO: init from config file
proc main() =
  let server = newQueueServer("0.0.0.0", 6789)
  server.addQueueTopic("default", BROKER)
  server.addQueueTopic("pubsub", PUBSUB)
  var numOfThread = 2
  if paramCount() > 0:
    numOfThread = paramStr(1).parseInt()
  server.start(numOfThread)


when isMainModule:
  octologStart()
  info "octobus is started at 0.0.0.0:6789"
  main()
  info "server terminated"
  octologStop()
