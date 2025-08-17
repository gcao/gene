when isMainModule:
  import times, os, strformat, strutils

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  var iterations = "1000000"
  var args = command_line_params()
  if args.len > 0:
    iterations = args[0]

  init_app_and_vm()

  # Benchmark pure arithmetic operations - just do a lot of additions
  let code = fmt"""
    (var a 1)
    (var b 2)
    (var sum 0)
    (var n 0)
    (while (< n {iterations})
      (sum = (+ sum a))
      (sum = (+ sum b))
      (n = (+ n 1)))
    sum
  """

  let compiled = compile(read_all(code))

  let ns = new_namespace("arithmetic")
  VM.frame.update(new_frame(ns))
  VM.cu = compiled
  VM.trace = get_env("TRACE") == "1"

  let start = cpuTime()
  let result = VM.exec()
  let duration = cpuTime() - start
  
  # Convert result to int properly
  let int_result = result.to_int()
  let n = iterations.parseInt()
  let expected = n.int64 * 3  # sum = (1 + 2) * n
  
  echo fmt"Result: {int_result}"
  echo fmt"Expected: {expected}"
  echo fmt"Time: {duration:.6f} seconds"
  
  # Show operations per second
  let ops = (n * 3).float / duration  # 3 arithmetic ops per iteration
  echo fmt"Performance: {ops:.0f} arithmetic operations/second"