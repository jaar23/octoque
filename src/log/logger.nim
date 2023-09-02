import octolog, logging
import times, locks

var loggerLock: Lock
var logger {.guard: loggerLock.}: ref Octolog

proc initLogger*() =
  withLock loggerLock:
    logger = newOctolog()
    logger.start()


proc registerLogHandler*(): void =
  var clogger = newConsoleLogger(fmtStr="[$datetime][$levelname] - $appname: ")
  var flogger = newFileLogger(now().format("yyyyMMddHHmm") & ".log", levelThreshold=lvlAll)
  addHandler(clogger)
  addHandler(flogger)
  


# template info*(message: string): void =
#   withLock loggerLock:
#     logger.info(message)

export loggerLock
export log
export warn
export error
export debug
export info
export notice
export fatal
