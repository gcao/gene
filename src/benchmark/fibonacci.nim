when isMainModule:
  import tables, times

  import ../gene/types
  import ../gene/parser
  import ../gene/compiler
  import ../gene/vm

  init_app_and_vm()

  var code = """
    (fn fib n
      (if (n < 2)
        n
      else
        ((fib (n - 1)) + (fib (n - 2)))
      )
    )
    (fib 24)
  """

  let compiled = compile(read_all(code))

  var ns = new_namespace("fibonacci")
  VM.frame = new_frame(ns)
  VM.code_mgr.data[compiled.id] = compiled
  VM.cur_block = compiled

  let start = cpuTime()
  let result = VM.exec()
  echo "Time: " & $(cpuTime() - start)
  echo "fib(24) = " & $result
