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

  # Benchmark pure arithmetic operations
  let code = fmt"""
    (var sum 0)
    (var i 0)
    (while (< i {iterations})
      (sum = (+ sum i))
      (i = (+ i 1)))
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
  let expected = (n.int64 * (n.int64 - 1)) div 2
  
  echo fmt"Result: sum(0..{n - 1}) = {int_result}"
  echo fmt"Expected: {expected}"
  echo fmt"Time: {duration:.6f} seconds"
  
  # Show operations per second
  let ops = (n * 2).float / duration  # 2 arithmetic ops per iteration
  echo fmt"Performance: {ops:.0f} arithmetic operations/second"