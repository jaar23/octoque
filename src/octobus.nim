import server/qserver, store/qtopic
import log/logger


## TODO: init from config file
proc main() =
  #initLogger()
  let server = newQueueServer("127.0.0.1", 6789)
  server.addQueueTopic("default")
  server.addQueueTopic("pubsub", PUBSUB)
  server.start()


when isMainModule:
  registerLogHandler()
  info "octobus is started at 127.0.0.1:6789"
  main()
  info "server terminated"
  
