import server/[qserver, repl, auth], store/qtopic,
  octolog, os, strutils, times, strformat,
  argparse, threadpool, cpuinfo, terminal

const octoqueTitle = """
-----------------------------------------------------
    ooo    ccc  ttttt   ooo    qqq    u   u  eeeee
   o   o  c       t    o   o  q   q   u   u  e
   o   o  c       t    o   o  q   q   u   u  eeeee
   o   o  c       t    o   o  q q q   u   u  e
    ooo    ccc    t     ooo    qq q    uuu   eeeee
-----------------------------------------------------
"""

proc printTitle (msg: string) =
  stdout.setForegroundColor(fgGreen)
  stdout.write msg
  stdout.resetAttributes()


var serverOpts = newParser:
  command("run"):
    flag("-d", "--detach", help = "running in detached mode")
    flag("-nc", "--noconsolelogger", help = "start server without logging to console")
    flag("-nf", "--nofilelogger", help = "start server without logging to file")
    option("-a", "--address", default = some("0.0.0.0"),
        help = "server address")
    option("-p", "--port", default = some("6789"), help = "server port")
    option("-b", "--brokerthread", default = some("1"),
          help = "listener thread for queue with broker type")
    option("-c", "--configfile", help = "configuration file")
    option("-l", "--logfile", help = "log file name, you can define the file path here too")
    option("-t", "--max-topic", default = some("8"),
        help = "maximum topic running on this queue server, default is 8")
  flag("-s", "--status", help = "check octoque running status")
  command("repl"):
    option("-a", "--address", default = some("0.0.0.0"),
        help = "server address")
    option("-p", "--port", default = some("6789"), help = "server port")
  command("adm"):
    command("create"):
      option("-u", "--username", help = "username", required = true)
      option("-p", "--password", help = "user's password")
      option("-t", "--topic", help = "topic(s) that is authorized to access",
          multiple = true)
      option("-r", "--role", default = some("user"), help = "user's role")
    command("update"):
      flag("-a", "--append", help = "append to user attributes")
      flag("-rp", "--replace", help = "replace to user attributes")
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
  help("{prog} is a simple queue system with broker and pubsub implementation.")


proc graceExit() {.noconv.} =
  # sync()
  # stop all subscriber
  # stop all topic
  # stop queue manager
  # join all threads
  echo "\noctoque is terminated\n"
  quit(0)


## TODO: init from config file
proc main() =
  var args = commandLineParams()
  var opts = serverOpts.parse(args)

  ## administrative command
  ## create, update and remove user
  if opts.adm.isSome:
    octologStart("octoque.adm.log", skipInitLog = true, fmt="")
    let adm = opts.adm.get
    if adm.create.isSome:
      var cru = adm.create.get
      createUser(cru.username, cru.password, cru.role_opt, cru.topic)
    elif adm.update.isSome:
      var updateMode = if adm.update.get.append: Append else: Replace
      var upd = adm.update.get
      updateUser(upd.username, upd.password_opt, upd.role_opt, upd.topic, updateMode)
    elif adm.remove.isSome:
      var rmu = adm.remove.get
      removeUser(rmu.username, rmu.topic)
    octologStop(true)
    quit(0)

  ## running the queue server
  elif opts.run.isSome:
    setControlCHook(graceExit)
    let run = opts.run.get
    var logfile = if run.logfile_opt.isSome: run.logfile else: now().format("yyyyMMddHHmm")
    var logconsole = not run.noconsolelogger
    if run.detach: logconsole = false

    if logconsole:
      printTitle(octoqueTitle)

    octologStart(filename = logfile, usefilelogger = not run.nofilelogger,
                 useconsolelogger = logconsole)
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
    info &"minimum threads in this startup: {minPoolSize}"
    info &"octoque is started {run.address}:{run.port}"
    let server = newQueueServer(run.address, run.port.parseInt(),
        run.max_topic.parseInt().uint8())
    server.addQueueTopic("default", BROKER)
    server.addQueueTopic("pubsub", PUBSUB)
    var numOfThread = run.brokerthread.parseInt()
    server.start(numOfThread)
    octologStop()

  ## running REPL mode
  elif opts.repl.isSome():
    replStart(opts.repl.get.address, opts.repl.get.port.parseInt())


when isMainModule:
  try:
    main()
  except ShortCircuit as err:
    if err.flag == "argparse_help":
      stdout.writeLine err.help
      quit(1)
  except CatchableError:
    stderr.writeLine getCurrentExceptionMsg()
    quit(1)
