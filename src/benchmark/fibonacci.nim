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
  var vm_data = new_vm_data(ns)
  vm_data.code_mgr.data[compiled.id] = compiled
  vm_data.cur_block = compiled
  VM.data = vm_data

  let start = cpuTime()
  let result = VM.exec()
  echo "Time: " & $(cpuTime() - start)
  echo "fib(24) = " & $result
