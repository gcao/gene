when isMainModule:
  import times, os, strformat

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
  VM.cu = compiled
  VM.trace = get_env("TRACE") == "1"

  let start = cpuTime()
  let result = VM.exec()
  let duration = cpuTime() - start
  
  # Convert result to int properly
  let int_result = result.to_int()
  
  echo fmt"Result: fib({n}) = {int_result}"
  echo fmt"Time: {duration:.6f} seconds"
  
  # Show operations per second for comparison
  if n == "24":
    # fib(24) requires 75025 recursive calls
    let ops = 75025.0 / duration
    echo fmt"Performance: {ops:.0f} function calls/second"
