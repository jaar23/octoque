import server/[qserver, repl], store/qtopic
import octolog, os, strutils, times, strformat
import argparse, threadpool, cpuinfo


var serverOpts = newParser:
  option("-i", "--interactive", default = some("n"),
      help = "start server with interactive mode")
  option("-b", "--brokerthread", default = some("1"),
      help = "listener thread for queue with broker type")
  option("-l", "--logfile", help = "log file name, you can define the file path here too")
  option("-k", "--usefilelogger", default = some("y"),
      help = "keep log to file, default yes when logfile enabled")
  option("-a", "--address", default = some("0.0.0.0"), help = "server address")
  option("-p", "--port", default = some("6789"), help = "server port")
  option("-t", "--max-topic", default = some("8"),
      help = "maximum topic running on this queue server, default is 8")
  help("{prog} is a simple queue system with broker and pubsub implementation.\n")


## TODO: init from config file
proc main() =
  var args = commandLineParams()
  var opts = serverOpts.parse(args)
  var useconsolelogger = if opts.interactive == "y": false else: true
  var logfile = if opts.logfile_opt.isSome: opts.logfile else: now().format("yyyyMMddHHmm")
  var usefilelogger = if opts.usefilelogger == "n": false else: true
  let minPoolSize = countProcessors() * (opts.max_topic.parseInt() * 2) + 8
  ## 8 default
  ## 1 for main thread
  ## 1 for logging
  ## 1 for default queue
  ## 1 for repl
  ## 4 request processing
  setMinPoolSize(minPoolSize)
  octologStart(filename = logfile, usefilelogger = usefilelogger,
               useconsolelogger = useconsolelogger)
  info &"minimum threads in this startup: {minPoolSize}"
  info &"octoque is started {opts.address}:{opts.port}"
  if opts.interactive == "y":
    replStart(opts.address, opts.port.parseInt())
  let server = newQueueServer(opts.address, opts.port.parseInt(),
      opts.max_topic.parseInt().uint8())
  server.addQueueTopic("default", BROKER)
  #server.addQueueTopic("pubsub", PUBSUB)
  var numOfThread = opts.brokerthread.parseInt()
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
