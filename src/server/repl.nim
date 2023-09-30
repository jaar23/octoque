import std/rdstdin
import threadpool


proc repl(): void =
  echo "start repl session"
  var line: string
  while true:
    let ok = readLineFromStdin("\n", line)
    if not ok: break
    if line.len > 0:
      echo line
  echo "exit repl session"

proc replStart*(): void = 
  spawn repl()
