# Package

version       = "0.1.0"
author        = "Guoliang Cao"
description   = "Gene - a general purpose language"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
installExt    = @["nim"]
bin           = @["gene"]

# Dependencies
requires "nim >= 1.4.0"

task test, "Runs the test suite":
  exec "nim c -r tests/test_types.nim"
  exec "nim c -r tests/test_parser.nim"
  exec "nim c -r tests/test_vm.nim"
  exec "nim c -r tests/test_vm_namespace.nim"
