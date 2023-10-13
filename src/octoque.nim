import server/[qserver, repl], store/qtopic
import octolog, os, strutils, times, strformat
import argparse, threadpool, cpuinfo


var serverOpts = newParser:
  command("run"):
    flag("-d", "--detach", help = "running in detached mode")
    flag("-i", "--interactive", help = "start server with interactive mode")
    option("-a", "--address", default = some("0.0.0.0"),
        help = "server address")
    option("-p", "--port", default = some("6789"), help = "server port")
    option("-b", "--brokerthread", default = some("1"),
          help = "listener thread for queue with broker type")
    option("-c", "--configfile", help = "configuration file")
    option("-l", "--logfile", help = "log file name, you can define the file path here too")
    option("-k", "--usefilelogger", default = some("y"),
        help = "keep log to file, default yes when logfile enabled")
    option("-t", "--max-topic", default = some("8"),
        help = "maximum topic running on this queue server, default is 8")
  command("adm"):
    command("create"):
      option("-u", "--username", help = "username", required = true)
      option("-p", "--password", help = "user's password")
      option("-t", "--topic", help = "topic that is authorized to access",
          multiple = true)
      option("-r", "--role", help = "user's role")
    command("update"):
      option("-u", "--username", help = "username", required = true)
      option("-p", "--password", help = "user's password")
      option("-t", "--topic", help = "topic that is authorized to access",
          multiple = true)
      option("-r", "--role", help = "user's role")
    command("remove"):
      option("-u", "--username", help = "username", required = true)
      option("-t", "--topic", help = "topic that is authorized to access",
          multiple = true)
      option("-r", "--role", help = "user's role")
  help("{prog} is a simple queue system with broker and pubsub implementation.\n")



## TODO: init from config file
proc main() =
  var args = commandLineParams()
  var opts = serverOpts.parse(args)

  if opts.adm.isSome:
    let adm = opts.adm.get
    if adm.create.isSome:
      echo "create user"
    elif adm.update.isSome:
      echo "update user"
    elif adm.remove.isSome:
      echo "remove user"
  elif opts.run.isSome:
    let run = opts.run.get
    var logfile = if run.logfile_opt.isSome: run.logfile else: now().format("yyyyMMddHHmm")
    var usefilelogger = if run.usefilelogger == "n": false else: true
    ## 8 default
    ## 1 for main thread
    ## 1 for logging
    ## 1 for default queue
    ## 1 for repl
    ## 4 request processing
    var minPoolSize = countProcessors() * (run.max_topic.parseInt() *
        run.brokerthread.parseInt()) + 8

    ## maximum threadpool size is 256
    if minPoolSize > 256:
      info &"threadpool size is {minPoolSize}, set to default 256"
      minPoolSize = 256
    setMinPoolSize(minPoolSize)
    octologStart(filename = logfile, usefilelogger = usefilelogger,
                 useconsolelogger=not run.interactive)
    info &"minimum threads in this startup: {minPoolSize}"
    info &"octoque is started {run.address}:{run.port}"
    if run.interactive:
      replStart(run.address, run.port.parseInt())
    let server = newQueueServer(run.address, run.port.parseInt(),
        run.max_topic.parseInt().uint8())
    server.addQueueTopic("default", BROKER)
    #server.addQueueTopic("pubsub", PUBSUB)
    var numOfThread = run.brokerthread.parseInt()
    server.start(numOfThread)
    info &"octoque is terminated"
    octologStop()



when isMainModule:
  try:
    main()
  except ShortCircuit as err:
    if err.flag == "argparse_help":
      echo err.help
      quit(1)
  except CatchableError:
    stderr.writeLine getCurrentExceptionMsg()
    quit(1)
