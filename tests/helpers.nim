import unittest, strutils, tables, osproc

import gene/types
import gene/parser
# import gene/interpreter
# import gene/serdes
import gene/vm

# Uncomment below lines to see logs
# import logging
# addHandler(newConsoleLogger())

# proc test(frame: Frame, self: Value, args: Value): Value =
#   1

# proc test2(frame: Frame, self: Value, args: Value): Value =
#   self.instance_props["a"].int + args.gene_children[0].int + args.gene_children[1].int

proc init_all*() =
  # if not VM.is_nil() and VM.thread_id > 0:
  #   cleanup_thread(VM.thread_id)

  # let thread_id = get_free_thread()
  # init_thread(thread_id)
  init_app_and_vm()
  # VM.thread_id = thread_id
  # VM.gene_ns.ns["test1"] = new_gene_native_method(test)
  # VM.gene_ns.ns["test2"] = new_gene_native_method(test2)

converter seq_to_gene*(self: seq[int]): Value =
  result = new_gene_vec()
  for item in self:
    result.vec.add(item)

converter seq_to_gene*(self: seq[string]): Value =
  result = new_gene_vec()
  for item in self:
    result.vec.add(item)

proc cleanup*(code: string): string =
  result = code
  result.stripLineEnd
  if result.contains("\n"):
    result = "\n" & result

proc test_parser*(code: string, result: Value) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    check read(code) == result

proc test_parser*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    var parser = new_parser()
    callback parser.read(code)

proc test_parse_archive*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    var parser = new_parser()
    callback parser.read_archive(code)

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

# proc test_interpreter*(code: string) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     discard eval(code, "test_code")

# proc test_interpreter*(code: string, result: Value) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     check eval(code, "test_code") == result

# proc test_interpreter*(code: string, callback: proc(result: Value)) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     callback eval(code, "test_code")

# proc test_interpreter_error*(code: string) =
#   var code = cleanup(code)
#   test "Interpreter / eval - error expected: " & code:
#     try:
#       discard eval(code, "test_code")
#       fail()
#     except ParseError:
#       discard

proc test_parse_document*(code: string, callback: proc(result: Document)) =
  var code = cleanup(code)
  test "Parse document: " & code:
    callback read_document(code)

# proc test_core*(code: string) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     discard eval(code)

# proc test_core*(code: string, result: Value) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     check eval(code) == result

# proc test_core*(code: string, callback: proc(result: Value)) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     callback eval(code)

# proc test_match*(pattern: string, input: string, callback: proc(result: MatchResult)) =
#   var pattern = cleanup(pattern)
#   var input = cleanup(input)
#   test "Pattern Matching: \n" & pattern & "\n" & input:
#     var p = read(pattern)
#     var i = read(input)
#     var m = new_match_matcher()
#     m.parse(p)
#     var result = m.match(i)
#     callback(result)

# proc test_import_matcher*(code: string, callback: proc(result: ImportMatcherRoot)) =
#   var code = cleanup(code)
#   test "Import: " & code:
#     var v = read(code)
#     var m = new_import_matcher(v)
#     callback m

# proc test_args*(schema, input: string, callback: proc(r: ArgMatchingResult)) =
#   var schema = cleanup(schema)
#   var input = cleanup(input)
#   test schema & "\n" & input:
#     var m = new_cmd_args_matcher()
#     m.parse(read(schema))
#     var r = m.match(input)
#     callback r

# proc test_file*(file: string) =
#   test "Tests " & file & ":":
#     init_all()
#     discard eval(read_file(file))

# proc test_jsgen*(code: string, result: Value) =
#   var code = cleanup(code)
#   test "JS generation: " & code:
#     init_all()
#     var generated = eval(code, "test_code").to_s
#     # if exists_env("SHOW_JS"):
#     #   echo "--------------------"
#     #   echo generated
#     #   echo()
#     var file = "/tmp/test.js"
#     write_file(file, generated)
#     # if exists_env("UGLIFY_JS"):
#     #   echo "--------------------"
#     #   var ret = exec_cmd(get_env("UGLIFY_JS") & " -b width=120 " & file)
#     #   if ret != 0:
#     #     discard exec_cmd("cat " & file)
#     #   echo "===================="
#     var (output, _) = exec_cmd_ex("/usr/local/bin/node " & file)
#     check output == result

# proc test_jsgen*(code: string, callback: proc(result: Value)) =
#   var code = cleanup(code)
#   test "JS generation: " & code:
#     init_all()
#     var generated = eval(code, "test_code").to_s
#     # if exists_env("SHOW_JS"):
#     #   echo "--------------------"
#     #   echo generated
#     #   echo()
#     var file = "/tmp/test.js"
#     write_file(file, generated)
#     # if exists_env("UGLIFY_JS"):
#     #   echo "--------------------"
#     #   var ret = exec_cmd(get_env("UGLIFY_JS") & " -b width=120 " & file)
#     #   if ret != 0:
#     #     discard exec_cmd("cat " & file)
#     #   echo "===================="
#     var (output, _) = exec_cmd_ex("/usr/local/bin/node " & file)
#     callback(output)

# proc test_serdes*(code: string, result: Value) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     var value = eval(code, "test_code")
#     var s = serialize(value).to_s
#     var value2 = deserialize(s)
#     check value2 == result

# proc test_serdes*(code: string, callback: proc(result: Value)) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     var value = eval(code, "test_code")
#     var s = serialize(value).to_s
#     var value2 = deserialize(s)
#     callback(value2)

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
