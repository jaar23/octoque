import server/qserver, store/qtopic
import octolog


## TODO: init from config file
proc main() =
  let server = new_queue_server("127.0.0.1", 6789)
  server.addQueueTopic("default")
  server.addQueueTopic("pubsub", PUBSUB)
  server.start()


when isMainModule:
  octologStart()
  info "octobus is started at 127.0.0.1:6789"
  main()
  info "server terminated"
  octologStop()
