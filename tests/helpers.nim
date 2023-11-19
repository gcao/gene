import unittest, strutils, tables, osproc

import gene/types
import gene/parser
import gene/vm

# Uncomment below lines to see logs
# import logging
# addHandler(newConsoleLogger())

converter to_value*(self: seq[int]): Value =
  let r = Reference(kind: VkArray)
  for item in self:
    r.arr.add(item)
  result = r.to_value()

converter seq_to_gene*(self: seq[string]): Value =
  let r = Reference(kind: VkArray)
  for item in self:
    r.arr.add(item.to_value())
  result = r.to_value()

converter to_value*(self: openArray[(string, Value)]): Value =
  new_map(self.to_table())

proc cleanup*(code: string): string =
  result = code
  result.stripLineEnd
  if result.contains("\n"):
    result = "\n" & result

proc init_all*() =
  init_app_and_vm()

proc test_parser*(code: string, result: Value) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    check read(code) == result

proc test_parser*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    var parser = new_parser()
    callback parser.read(code)

proc test_parser_error*(code: string) =
  var code = cleanup(code)
  test "Parser error expected: " & code:
    try:
      discard read(code)
      fail()
    except ParseError:
      discard

proc test_read_all*(code: string, result: seq[Value]) =
  var code = cleanup(code)
  test "Parser / read_all: " & code:
    check read_all(code) == result

proc test_read_all*(code: string, callback: proc(result: seq[Value])) =
  var code = cleanup(code)
  test "Parser / read_all: " & code:
    callback read_all(code)

proc test_vm*(code: string) =
  var code = cleanup(code)
  test "Compilation & VM: " & code:
    init_all()
    discard VM.exec(code, "test_code")

proc test_vm*(code: string, result: Value) =
  var code = cleanup(code)
  test "Compilation & VM: " & code:
    init_all()
    check VM.exec(code, "test_code") == result

proc test_vm*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Compilation & VM: " & code:
    init_all()
    callback VM.exec(code, "test_code")

proc test_vm_error*(code: string) =
  var code = cleanup(code)
  test "Compilation & VM: " & code:
    init_all()
    try:
      discard VM.exec(code, "test_code")
      fail()
    except:
      discard
