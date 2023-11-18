# To run these tests, simply execute `nimble test` or `nim c -r tests/test_parser.nim`

import unittest, options, tables, unicode, times, nre

import gene/types
import gene/parser

import ./helpers

# 0b... Bin
# 0x... Hex
# (#Base64 ...)  Base64

# Parser options:
# A map of name->stack is used to store parser options
# A cache of computed options are stored, and refreshed whenever any of below commands is found.
# (#Set name value)
# (#Unset name...) - will clear non-pushed top value of the stack
# (#Reset name...) - will clear all non-pushed values of the stack
# (#Push name value)
# Set vs Push:
# Options are applicable to end of document or until it's changed by further Set/Unset/....
# Options are applicable to gene/array/map and will be removed automatically
# Push is recommended over Set

# Usecases:
# (#Set x 1) (#Get x) -> 1
# [(#Set x 1)] (#Get x) -> 1

# (#Push x 1) (#Get x) -> 1
# [(#Push x 1)] (#Get x) -> nil

# [(#Push x 1) (#Set x 2)] (#Get x) -> 2
# ...

# Parsing from a stream (like a log file that is being written to continually, or an incoming socket)
# Parsing can be interrupted in these cases - what is the best way to stop?

test_parser "nil", NIL
test_parser "true", TRUE
test_parser "false", FALSE

# test_parser "10", 10
# test_parser "-1", -1
# test_parser "10e10", 10e10
# test_parser "+5.0E5", +5.0E5

# test_parser "\\\\", '\\'
# test_parser "\\s", 's'
# test_parser "\\space", ' '
# test_parser "\\t", 't'
# test_parser "\\tab", '\t'
# test_parser "\\n", 'n'
# test_parser "\\newline", '\n'
# test_parser "\\r", 'r'
# test_parser "\\return", '\r'
# test_parser "\\f", 'f'
# test_parser "\\formfeed", '\f'
# test_parser "\\b", 'b'
# test_parser "\\backspace", '\b'
# test_parser "\\中", "中".runeAt(0)

# test_parser "\\\"nil\"", new_gene_symbol("nil")
# test_parser "\\\"true\"", new_gene_symbol("true")
# test_parser "\\\"false\"", new_gene_symbol("false")
# test_parser "\\'nil'", new_gene_symbol("nil")

# test_parser "\"test\"", "test"
# test_parser ",\"test\",", "test"
# test_parser "'test'", "test"
# test_parser ",'test',", "test"

# test_parser "a", new_gene_symbol("a")
# test_parser "A", new_gene_symbol("A")
# test_parser "/", new_gene_symbol("/")
# test_parser "+a", new_gene_symbol("+a")
# test_parser "#a", new_gene_symbol("#a")
# test_parser "a#b", new_gene_symbol("a#b")
# test_parser "a:b", new_gene_symbol("a:b")
# test_parser "a\\ b", new_gene_symbol("a b")
# test_parser "a\\/b", new_gene_symbol("a/b")
# test_parser "n/A", new_gene_complex_symbol(@["n", "A"])
# test_parser "n\\/A/B", new_gene_complex_symbol(@["n/A", "B"])
# test_parser "n/m/A", new_gene_complex_symbol(@["n", "m", "A"])
# test_parser "/A", new_gene_complex_symbol(@["", "A"])
# test_parser "^a", new_gene_symbol("^a")
# test_parser "symbol-👋", new_gene_symbol("symbol-👋")
# test_parser "+foo+", new_gene_symbol("+foo+")

# test_parser "#/b/", proc(r: Value) =
#   check r.kind == VkRegex
#   check "ab".find(r.regex).get().captures[-1] == "b"
#   check "AB".find(r.regex).is_none()

# test_parser "#/(a|b)/", proc(r: Value) =
#   check r.kind == VkRegex
#   check "ab".find(r.regex).get().captures[-1] == "a"
#   check "AB".find(r.regex).is_none()

# test_parser "#/a\\/b/", proc(r: Value) =
#   check r.kind == VkRegex
#   check "a/b".find(r.regex).get().captures[-1] == "a/b"

# # i: ignore case
# # m: multi-line mode, ^ and $ matches beginning and end of each line
# test_parser "#/b/i", proc(r: Value) =
#   check r.kind == VkRegex
#   check "ab".find(r.regex).get().captures[-1] == "b"
#   check "AB".find(r.regex).get().captures[-1] == "B"

# test_parser "2020-12-02", new_gene_date(2020, 12, 02)
# test_parser "2020-12-02T10:11:12Z",
#   new_gene_datetime(init_date_time(02, cast[Month](12), 2020, 10, 11, 12, utc()))
# test_parser "10:11:12", new_gene_time(10, 11, 12)

# test_parser "{}", Table[string, Value]()
# test_parser "{^a 1}", {"a": new_gene_int(1)}.toTable

# test_parser "{^a^b 1}", {"a": new_gene_map({"b": new_gene_int(1)}.toTable)}.toTable
# test_parser "{^a^^b}", {"a": new_gene_map({"b": new_gene_bool(true)}.toTable)}.toTable
# test_parser "{^a^!b}", {"a": new_gene_map({"b": new_gene_bool(false)}.toTable)}.toTable
# test_parser "{^a^b 1 ^a^c 2}", {"a": new_gene_map({"b": new_gene_int(1), "c": new_gene_int(2)}.toTable)}.toTable
# test_parser "{^a^^b ^a^c 2}", {"a": new_gene_map({"b": new_gene_bool(true), "c": new_gene_int(2)}.toTable)}.toTable
# # test_parser "{^a^b 1 ^a {^c 2}}", {"a": new_gene_map({"b": new_gene_int(1), "c": new_gene_int(2)}.toTable)}.toTable
# test_parser_error "{^a^b 1 ^a 2}"
# test_parser_error "{^a^b 1 ^a {^c 2}}"

# test_parser "(_ ^a^b 1)", proc(r: Value) =
#   assert r.gene_props["a"].map["b"] == 1
# test_parser "(_ ^a^^b 1)", proc(r: Value) =
#   assert r.gene_props["a"].map["b"] == new_gene_bool(true)
#   assert r.gene_children[0] == 1

# test_parser "[]", new_gene_vec()
# test_parser "[,]", new_gene_vec()
# test_parser "[1 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))
# test_parser "[1, 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))

# test_parser "#[]", new_gene_set()
# # This should work
# # test_parser "#[1 2]", new_gene_set(new_gene_int(1), new_gene_int(2))

# test_parser ",a", new_gene_symbol("a")
# test_parser "a,", new_gene_symbol("a")

# test_parser "1 2 3", 1

# test_parser "()", proc(r: Value) =
#   check r.gene_type == nil
#   check r.gene_props.len == 0
#   check r.gene_children.len == 0

# test_parser "(())", proc(r: Value) =
#   check r.kind == VkGene
#   check r.gene_children.len == 0
#   check r.gene_type.kind == VkGene
#   check r.gene_type.gene_children.len == 0

# test_parser "(1 2 3)", proc(r: Value) =
#   check r.gene_type == 1
#   check r.gene_children == @[2, 3]

# test_parser "(nil 2 3)", proc(r: Value) =
#   check r.gene_type.kind == VkNil
#   check r.gene_children == @[2, 3]

# test_parser """
#   (_ 1 "test")
# """, proc(r: Value) =
#   check r.gene_children[0] == 1
#   check r.gene_children[1] == "test"

# test_parser "(1 ^a 2 3 4)", proc(r: Value) =
#   check r.gene_type == 1
#   check r.gene_props == {"a": new_gene_int(2)}.toTable
#   check r.gene_children == @[3, 4]

# test_parser "(1 2 ^a 3 4)", proc(r: Value) =
#   check r.gene_type == 1
#   check r.gene_props == {"a": new_gene_int(3)}.toTable
#   check r.gene_children == @[2, 4]

# test_parser "(1 ^^a 2 3)", proc(r: Value) =
#   check r.gene_type == 1
#   check r.gene_props == {"a": new_gene_bool(true)}.toTable
#   check r.gene_children == @[2, 3]

# test_parser "(1 ^!a 2 3)", proc(r: Value) =
#   check r.gene_type == 1
#   check r.gene_props == {"a": Value(kind: VkNil)}.toTable()
#   check r.gene_children == @[2, 3]

# test_parser "{^^x ^!y ^^z}", proc(r: Value) =
#   check r.kind == VkMap
#   check r.map == {"x": new_gene_bool(true), "y": Value(kind: VkNil), "z": new_gene_bool(true)}.toTable

# test_parser ":foo", proc(r: Value) =
#   check r.kind == VkQuote
#   check r.quote == new_gene_symbol("foo")

# test_parser "%foo", proc(r: Value) =
#   check r.kind == VkUnquote
#   check r.unquote == new_gene_symbol("foo")
#   check r.unquote_discard == false

# test_parser "%_foo", proc(r: Value) =
#   check r.kind == VkUnquote
#   check r.unquote == new_gene_symbol("foo")
#   check r.unquote_discard == true

# # TODO: %_ is not allowed on gene type and property value
# # (%_foo)         should throw error
# # (a ^name %_foo) should throw error
# # {^name %_foo}   should throw error

# # test_parser "#_ [foo bar]", proc(r: Value) =
# #   check r == nil

# test_parser "1/2", proc(r: Value) =
#   check r.kind == VkRatio
#   check r.ratio_num == BiggestInt(1)
#   check r.ratio_denom == BiggestInt(2)

# test_parser "{^ratio -1/2}", proc(r: Value) =
#   check r.kind == VkMap
#   check r.map["ratio"] == new_gene_ratio(-1, 2)

# test_parser_error """
#   # Gene properties should not be mixed with children like below
#   (a ^b b c ^d d) # b & d are properties but are separated by c
# """

# test_parser_error "{^ratio 1/-2}"

# test_parser "0!11", proc(r: Value) =
#   check r.kind == VkByte
#   check r.byte_bit_size == 2
#   check r.byte == 3

# test_parser "0!11110000", proc(r: Value) =
#   check r.kind == VkByte
#   check r.byte_bit_size == 8
#   check r.byte == 240

# test_parser "0!1111~ 0000", proc(r: Value) =
#   check r.kind == VkByte
#   check r.byte_bit_size == 8
#   check r.byte == 240

# test_parser "0!000011110000", proc(r: Value) =
#   check r.kind == VkBin
#   check r.bin_bit_size == 12
#   check r.bin == @[uint8(15), uint8(0)]

# test_parser "0*a0", proc(r: Value) =
#   check r.kind == VkByte
#   check r.byte_bit_size == 8
#   check r.byte == 160

# test_parser "0*A0", proc(r: Value) =
#   check r.kind == VkByte
#   check r.byte_bit_size == 8
#   check r.byte == 160

# test_parser "0*a003", proc(r: Value) =
#   check r.kind == VkBin
#   check r.bin_bit_size == 16
#   check r.bin == @[uint8(160), uint8(3)]

# test_parser "0*a0~ 03", proc(r: Value) =
#   check r.kind == VkBin
#   check r.bin_bit_size == 16
#   check r.bin == @[uint8(160), uint8(3)]

# test_parser "0#ABCD", proc(r: Value) =
#   check r.kind == VkBin
#   check r.bin_bit_size == 24
#   check r.bin == @[uint8(0), uint8(16), uint8(131)]

# test_parser "0#AB~ CD", proc(r: Value) =
#   check r.kind == VkBin
#   check r.bin_bit_size == 24
#   check r.bin == @[uint8(0), uint8(16), uint8(131)]

# # Unit conversion
# test_parser """
#   1m # 1m = 1 minute = 60 seconds (1 = 1s = 1 second)
# """, 60
# test_parser """
#   1s
# """, 1
# test_parser """
#   1ms
# """, 0.001
# # test_parser """
# #   (#Unit "m" 1)  # 1m = 1 meter (meter is defined as the default unit for length)
# #   1m
# # """, 1
# test_parser """
#   1m30s
# """, 90
# test_parser """
#   1s500ms
# """, 1.5
# # test_parser """
# #   1m30
# # """, 90
# # Support decorator from the parser. It can appear anywhere except property names.
# # Pros:
# #   Easier to write
# # Cons:
# #   Harder to read ?!
# #
# # #@f a       = (f a)
# # (#@f a)     = ((f a))
# # (#@f #@g a) = ((f (g a)))
# # #@(f a) b   = (((f a) b))
# # {^p #@f a}  = {^p (f a)}

# test_parser """
#   #@f a
# """, proc(r: Value) =
#   check r.kind == VkGene
#   check r.gene_type.str == "f"
#   check r.gene_children[0].str == "a"

# test_parser """
#   #@f #@g a
# """, proc(r: Value) =
#   check r.kind == VkGene
#   check r.gene_type.str == "f"
#   check r.gene_children[0].kind == VkGene
#   check r.gene_children[0].gene_type.str == "g"
#   check r.gene_children[0].gene_children[0].str == "a"

# # test_parser """
# #   #*f
# # """, proc(r: Value) =
# #   check r.kind == VkGene
# #   check r.gene_type.str == "f"

# test_parser """
#   {^p #@f a}
# """, proc(r: Value) =
#   check r.map["p"].kind == VkGene
#   check r.map["p"].gene_type.str == "f"
#   check r.map["p"].gene_children[0].str == "a"

# test_read_all """
#   1 # comment
#   2
# """, proc(r: seq[Value]) =
#   check r[0] == 1
#   check r[1] == 2

# test_read_all """
#   1 ##comment
#   2
# """, proc(r: seq[Value]) =
#   check r[0] == 1
#   check r[1] == 2

# test_read_all "a,b", proc(r: seq[Value]) =
#   check r[0] == new_gene_symbol("a")
#   check r[1] == new_gene_symbol("b")

# test_read_all "1 2", @[new_gene_int(1), new_gene_int(2)]

# test_parser """
#   [
#     1 # test
#   ]
# """, @[1]

# test_parser """
#   #
#   # comment
#   #
#   1
#   #
# """, 1

# test_parser "[a/[1 2]]", proc(r: Value) =
#   check r.vec[0].csymbol[0] == "a"
#   check r.vec[0].csymbol[1] == ""
#   check r.vec[1].vec[0] == 1
#   check r.vec[1].vec[1] == 2

# test_parser """
#   #< comment ># 1
# """, 1

# test_parser """
#   #< #<< comment >># ># 1
# """, 1

# test_parser """
#   #<
#   comment
#   #># 1
# """, 1

# test_parser """
#   #<
#   comment
#   #>## 1
#   2
# """, 2

# test_parser """
#   #<
#   #<<
#   comment
#   #>>#
#   #># 1
# """, 1

# test_parse_document """
#   ^name "Test document"
#   ^version "0.1.0"
# """, proc(r: Document) =
#   check r.props["name"] == "Test document"
#   check r.props["version"] == "0.1.0"
#   check r.children.len == 0

# test_parse_document """
#   ^name "Test document"
#   1 2
# """, proc(r: Document) =
#   check r.props["name"] == "Test document"
#   check r.children == @[1, 2]

# test_parser "\"\"\"a\"\"\"", "a"
# test_parser "[\"\"\"a\"\"\"]", proc(r: Value) =
#   check r.kind == VkVector
#   check r.vec.len == 1
#   check r.vec[0] == "a"

# test_parser "\"\"\"a\"b\"\"\"", "a\"b"

# # Trim whitespaces and new line after opening """
# # E.g. """  \na""" => "a"
# test_parser "\"\"\"  \na\"\"\"", "\na"
# # Trim whitespaces before closing """
# # E.g. """a\n   """ => "a\n"
# test_parser "\"\"\"a\n   \"\"\"", "a\n"

# test_parser """
#   (#File "f" "abc")
# """, proc(r: Value) =
#   check r.kind == VkFile
#   check r.file_name == "f"
#   check r.file_content == "abc"

# test_parser """
#   (#File f "abc") # File name can be a symbol treated as a string literal
# """, proc(r: Value) =
#   check r.kind == VkFile
#   check r.file_name == "f"

# test_parser """
#   (#File "f" 0!11)
# """, proc(r: Value) =
#   check r.kind == VkFile
#   check r.file_name == "f"
#   var content = r.file_content
#   check content.kind == VkByte
#   check content.byte_bit_size == 2
#   check content.byte == 3

# test_parser """
#   (#Dir "d")
# """, proc(r: Value) =
#   check r.kind == VkDirectory
#   check r.dir_name == "d"

# test_parser """
#   (#Dir d) # Dir name can be a symbol treated as a string literal
# """, proc(r: Value) =
#   check r.kind == VkDirectory
#   check r.dir_name == "d"

# test_parser """
#   (#Dir "d"
#     (#File "f" "abc")
#   )
# """, proc(r: Value) =
#   check r.kind == VkDirectory
#   check r.dir_name == "d"
#   check r.dir_members.len == 1
#   var file = r.dir_members["f"]
#   check file.kind == VkFile
#   check file.file_name == "f"
#   check file.file_content == "abc"

# test_parser """
#   (#Gar x
#     (#File f "abc")
#     (#Dir "d"
#       (#File "f2" "def")
#     )
#   )
# """, proc(r: Value) =
#   check r.kind == VkArchiveFile
#   check r.arc_file_name == "x"
#   check r.arc_file_members.len == 2
#   var file = r.arc_file_members["f"]
#   check file.kind == VkFile
#   check file.file_name == "f"
#   check file.file_content == "abc"

# test_parse_archive """
#   (#Dir "d"
#     (#File "f" "abc")
#   )
# """, proc(r: Value) =
#   check r.kind == VkArchiveFile
#   var dir = r.arc_file_members["d"]
#   check dir.dir_name == "d"
#   var file = dir.dir_members["f"]
#   check file.kind == VkFile
#   check file.file_name == "f"
#   check file.file_content == "abc"

# test """Parser / read_stream:
#   1 2
# """:
#   var code = cleanup"""
#     1 2
#   """
#   var data = new_gene_vec()
#   proc handle(value: Value) =
#     data.vec.add(value)
#   var parser = new_parser()
#   parser.read_stream(code, handle)
#   check data == @[1, 2]

# test_parser """
#   (#Ignore) 1
# """, 1

# test_parser """
#   #&x
# """, proc(r: Value) =
#   check r.kind == VkReference
#   check r.reference.name == "x"

# test_parser """
#   (#Ref "x" 1)
# """, proc(r: Value) =
#   check r.kind == VkRefTarget
#   check r.ref_target.name  == "x"
#   check r.ref_target.value == 1

# test_parser """
#   [
#     (#Ref "x" 1)
#     #&x
#   ]
# """, proc(r: Value) =
#   let last = r.vec[^1]
#   check last.kind == VkReference
#   check last.reference.name  == "x"
#   check last.reference.value == 1

# test_parser """
#   [
#     #&x
#     (#Ref "x" 1)
#   ]
# """, proc(r: Value) =
#   let first = r.vec[0]
#   check first.kind == VkReference
#   check first.reference.name  == "x"
#   check first.reference.value == 1

# test_parser_error """
#   [
#     (#Ref "x" 1)
#     (#Ref "x" 2) # Should trigger parser error
#   ]
# """

# # test_parser """
# #   #"#a/b#" # same as ("" a/b)
# # """, "TODO"

# # test_parser """
# #   #"#1#" # same as ("" 1)
# # """, "TODO"

# # test_parser """
# #   #"#true#" # same as ("" true)
# # """, "TODO"

# # test_parser """
# #   #"a#(1 + 2)" # same as ("a" (1 + 2))
# # """, "TODO"

# # test_parser """
# #   #"a#[1 2]" # same as ("a" [1 2])
# # """, "TODO"

# # test_parser """
# #   #"a#{^a b}" # same as ("a" {^a b})
# # """, "TODO"
