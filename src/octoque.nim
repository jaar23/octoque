import server/[qserver, repl], store/qtopic
import octolog, os, strutils, times, strformat
import argparse


var serverOpts = newParser:
  option("-i", "--interactive", default = some("n"), help="start server with interactive mode")
  option("-b", "--brokerthread", default = some("2"), help="listener thread for queue with broker type")
  option("-l", "--logfile", help="log file name, you can define the file path here too")
  option("-k", "--usefilelogger", default = some("y"), help="keep log to file, default yes when logfile enabled")
  option("-a", "--address", default = some("0.0.0.0"), help="server address")
  option("-p", "--port", default = some("6789"), help="server port")
  help("{prog} is a simple queue system with broker and pubsub implementation.\n")


## TODO: init from config file
proc main() =
  var args = commandLineParams()
  var opts = serverOpts.parse(args)
  var useconsolelogger = if opts.interactive == "y": false else: true
  var logfile = if opts.logfile_opt.isSome: opts.logfile else: now().format("yyyyMMddHHmm")
  var usefilelogger = if opts.usefilelogger == "n": false else: true

  octologStart(filename = logfile, usefilelogger = usefilelogger, 
               useconsolelogger=useconsolelogger)
  info &"octoque is started {opts.address}:{opts.port}"
  if opts.interactive == "y":
    replStart(opts.address, opts.port.parseInt())
  let server = newQueueServer(opts.address, opts.port.parseInt())
  server.addQueueTopic("default", BROKER)
  server.addQueueTopic("pubsub", PUBSUB)
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
