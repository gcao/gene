import unittest, tables

import gene/types

import ./helpers

# Keywords:
# nil, true, false, _, not, NaN
# if, then, elif, else
# not, !
# and, or, xor, xand, &&, ||, ||*(xor: a && !b + !a && b), &&* (xand: a && b + !a && !b)
# var
# do
# loop, while, repeat, next, break
# for, in
# module, import, from, of, as
# ns
# class, mixin, method, new, super
# cast
# self
# fn, fnx, fnxx, return
# macro
# match
# enum
# try, catch, ensure, throw
# async, await
# global
# gene, genex
# #...
# $... (e.g. $app, $pkg, $ns, $module, $args)
# +, -, *, /, =, ...
# ==, !=, > >= < <=
# ->, =>

test_vm "nil", NIL
test_vm "1", 1
test_vm "true", true
test_vm "false", false
test_vm "_", PLACEHOLDER
test_vm "\"string\"", "string"
test_vm ":a", "a".to_symbol_value()

test_vm "1 2 3", 3

test_vm "[]", new_array_value()
test_vm "[1 2]", new_array_value(1, 2)

test_vm "{}", new_map_value()
test_vm "{^a 1}", new_map_value({"a".to_key(): 1.to_value()}.to_table())

# test_vm "(:test 1 2)", proc(r: Value) =
#   check r.gene.type == to_symbol_value("test")
#   check r.gene.children[0] == 1
#   check r.gene.children[1] == 2

# test_vm "(range 0 100)", proc(r: Value) =
#   check r.range.start == 0
#   check r.range.end == 100

# test_vm "(0 .. 100)", proc(r: Value) =
#   check r.range.start == 0
#   check r.range.end == 100

test_vm "(1 + 2)", 3
test_vm "(1 - 2)", -1

# Variable tests
test_vm """
  (var i 1)
""", 1

test_vm """
  (var i 1)
  i
""", 1

test_vm """
  (var a 1)
  (var b 2)
  [a b]
""", new_array_value(1, 2)

test_vm """
  (var a 1)
  (var b 2)
  {^a a ^b b}
""", new_map_value({"a".to_key(): 1.Value, "b".to_key(): 2.Value}.to_table)

test_vm """
  (var i 1)
  (i = 2)
  i
""", 2

test_vm """
  (var a (if false 1))
  a
""", NIL

# Control flow tests
test_vm """
  (if false
    1
  )
""", NIL

test_vm """
  (if true
    # do nothing
  else
    1
  )
""", NIL

test_vm """
  (if true
    1
  else
    2
  )
""", 1

test_vm """
  (if false
    1
  else
    2
  )
""", 2

test_vm """
  (do 1 2 3)
""", 3

test_vm """
  (do
    (var i 1)
    i
  )
""", 1

test_vm """
  (loop
    1
    (break)
  )
  2
""", 2

test_vm """
  (loop
    (break 1)
  )
""", 1

# test_vm """
#   (var i 1)
#   (i += 2)
#   i
# """, 3

# test_vm """
#   (var i 3)
#   (i -= 2)
#   i
# """, 1

# test_vm """
#   (var i 1)
# """, 1

# test_vm """
#   ($ns/a = 1)
#   a
# """, 1

# test_vm """
#   (var a [0])
#   (a/0 = 1)
#   a/0
# """, 1

# test_vm """
#   (var a (_ 0))
#   (a/0 = 1)
#   a/0
# """, 1

# test_vm """
#   (var a [1])
#   (a/0 += 1)
#   a/0
# """, 2

# test_vm """
#   ($ns/a = 1)
#   ($ns/a += 1)
#   a
# """, 2

# test_vm """
#   (ns n
#     (ns m)
#   )
#   (n/m/a = 1)
#   n/m/a
# """, 1

# test_vm """
#   (ns n
#     (ns m)
#   )
#   (n/m/a = 1)
#   (n/m/a += 1)
#   n/m/a
# """, 2

test_vm "(1 == 1)", true
test_vm "(1 == 2)", false
test_vm "(1 < 0)", false
test_vm "(1 < 1)", false
test_vm "(1 < 2)", true
test_vm "(1 <= 0)", false
test_vm "(1 <= 1)", true
test_vm "(1 <= 2)", true

test_vm "(true && true)", true
test_vm "(true && false)", false
test_vm "(false && false)", false
test_vm "(true || true)", true
test_vm "(true || false)", true
test_vm "(false || false)", false

# test_vm "(nil || 1)", 1

# test_vm "(var a 1) a", 1
# test_vm "(var a 1) (a = 2) a", 2
# test_vm "(var a) (a = 2) a", 2

# test_vm """
#   (var a 1)
#   (var b 2)
#   [a b]
# """, proc(r: Value) =
#   check r.ref.arr[0] == 1
#   check r.ref.arr[1] == 2

# test_vm """
#   (var a (if false 1))
#   a
# """, NIL

# test_vm """
#   (var a 1)
#   (var b 2)
#   {^a a ^b b}
# """, proc(r: Value) =
#   check r.ref.map["a".to_key()] == 1
#   check r.ref.map["b".to_key()] == 2

# test_vm """
#   (var a 1)
#   (var b 2)
#   (:test ^a a b)
# """, proc(r: Value) =
#   check r.gene.props["a".to_key()] == 1
#   check r.gene.children[0] == 2

# test_vm "(if true 1)", 1
# test_vm "(if true then 1)", 1
# test_vm "(if not false 1)", 1
# test_vm "(if false 1 else 2)", 2
# test_vm """
#   (if false
#     1
#   elif true
#     2
#   else
#     3
#   )
# """, 2