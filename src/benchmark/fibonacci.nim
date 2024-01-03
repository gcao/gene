when isMainModule:
  import tables, times, os, strformat

  import ../gene/types
  import ../gene/parser
  import ../gene/compiler
  import ../gene/vm

  var n = "24"
  var args = command_line_params()
  if args.len > 0:
    n = args[0]

  init_app_and_vm()

  let code = fmt"""
    (fn fib n
      (if (n < 2)
        n
      else
        ((fib (n - 1)) + (fib (n - 2)))
      )
    )
    (fib {n})
  """

  let compiled = compile(read_all(code))

  let ns = new_namespace("fibonacci")
  VM.frame.update(new_frame(ns))
  VM.code_mgr.data[compiled.id] = compiled
  VM.cur_block = compiled
  VM.trace = get_env("TRACE") == "1"

  let start = cpuTime()
  let result = VM.exec()
  echo "Time: " & $(cpuTime() - start)
  echo fmt"fib({n}) = " & $result
