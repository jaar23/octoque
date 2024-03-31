import os, strutils
import illwill


type
  App = object
    tb: TerminalBuffer
    width: int
    height: int
    fgColor: ForegroundColor
    bgColor: BackgroundColor
    command: string
    result: string
  

proc boxWidth*(app: var App): int = 
  return toInt(toFloat(app.width) * 0.95)


proc commandPanel*(app: var App, w = app.boxWidth(), h: int): void =
  app.tb.drawRect(w, h, 0, 0, doubleStyle=true)


proc boxPanel*(app: var App): void =
  var bb = newBoxBuffer(app.tb.width, app.tb.height)
  bb.drawRect(20, 3, 32, 5, doubleStyle=true)
  bb.drawRect(24, 2, 28, 6)
  app.tb.setForegroundColor(fgBlue)
  app.tb.write(bb)



proc linePanel*(app: var App): void =
  app.tb.setForegroundColor(fgYellow)
  app.tb.drawHorizLine(2, 14, 14, doubleStyle=true)
  app.tb.drawVertLine(4, 13, 15, doubleStyle=true)
  app.tb.drawVertLine(6, 13, 15)
  app.tb.drawVertLine(10, 13, 16)
  app.tb.drawHorizLine(4, 12, 15, doubleStyle=true)

  app.tb.write(7, 17, fgWhite, "(6)")


proc helpText(app: var App, y: int): void =
  app.tb.write(1, y, fgWhite, "Press ? for help, Shift + Q to exit")


proc mainPanel*(app: var App): void =
  app.tb.setForegroundColor(fgWhite, true)
  app.commandPanel(h=2)
  app.commandPanel(h=22)
  app.helpText(23)
  app.tb.write(2, 1, resetStyle, " > ", fgGreen, $app.command)


proc render(app: var App): void =
  app.mainPanel()
  app.tb.display()


proc execCommand(app: var App, command: string): void =
  echo "enter"
  app.tb.clear()
  app.mainPanel()
  #app.tb.setCursorYPos(3)
  app.tb.write(2, 3, fgWhite, command)
  #app.tb.clear()
  #app.tb.display()
  #return




proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)


proc run*(app: var App): void =
  illwillInit(fullscreen=true)
  setControlCHook(exitProc)
  hideCursor()

  app.mainPanel()
  while true:
    var key = getKey()
    case key
    of Key.None: discard
    of Key.Escape, Key.ShiftQ: exitProc()
    of Key.B: app.boxPanel()
    of Key.L: app.linePanel()
    of Key.ShiftC: 
      app.command = ""
      app.tb.clear()
    of Key.Enter: 
      app.execCommand(app.command)
    of Key.Backspace:
      app.command = app.command.substr(0, app.command.len - 2)
      app.tb.clear()
      #app.tb.write(2, 1, resetStyle, "command > ", fgGreen, $app.command)
    of Key.Space:
      app.command = app.command & " "
    else:
      if app.command.len <= app.width - 12:
        app.command = app.command & key.repr()
      #app.tb.write(8, 4, ' '.repeat(31))
      app.mainPanel()
 
    # app.tb.write(2, 4, app.command)
    app.render()
    sleep(20)

var app = App(width: 120, tb: newTerminalBuffer(120, terminalHeight()))
app.run()

