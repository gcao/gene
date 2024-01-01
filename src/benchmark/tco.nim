when isMainModule:
  import tables, os, times, strformat

  import ../gene/types
  import ../gene/parser
  import ../gene/compiler
  import ../gene/vm

  var args = command_line_params()
  if args.len == 0:
    echo "Usage: tco <number>"
    quit(1)

  let n = args[0]
  init_app_and_vm()

  let code = fmt"""
    (fn tco n
      (if (n == 0)
        (return 0)
      )
      (tco (n - 1))
    )
    (tco {n})
  """

  let compiled = compile(read_all(code))

  let ns = new_namespace("fibonacci")
  VM.frame.update(new_frame(ns))
  VM.code_mgr.data[compiled.id] = compiled
  VM.cur_block = compiled
  # VM.trace = true

  let start = cpuTime()
  let result = VM.exec()
  echo "Time: " & $(cpuTime() - start)
  echo fmt"tco({n}) = {$result}"
