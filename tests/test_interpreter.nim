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

# TODO: Fix range implementation
# test_vm "(range 0 100)", proc(r: Value) =
#   check r.ref.range_start == 0.to_value()
#   check r.ref.range_end == 100.to_value()

# test_vm "(0 .. 100)", proc(r: Value) =
#   check r.ref.range_start == 0.to_value()
#   check r.ref.range_end == 100.to_value()

test_vm "(1 + 2)", 3
test_vm "(1 - 2)", -1

# Additional arithmetic tests
test_vm "(2 * 3)", 6
test_vm "(6 / 2)", 3.0
test_vm "(2 > 1)", true
test_vm "(2 >= 2)", true
test_vm "(1 != 2)", true

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
""", new_map_value({"a".to_key(): 1.to_value(), "b".to_key(): 2.to_value()}.to_table)

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

# Additional conditional tests
test_vm "(if true 1)", 1
test_vm "(if false 1 else 2)", 2

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

# Loop with variable modification
test_vm """
  (var i 0)
  (loop
    (i = (i + 1))
    (break)
  )
  i
""", 1

test_vm """
  (var i 1)
  (i += 2)
  i
""", 3

test_vm """
  (var i 3)
  (i -= 2)
  i
""", 1

test_vm """
  (var i 1)
""", 1

test_vm """
  ($ns/a = 1)
  a
""", 1

test_vm """
  (var a [0])
  (a/0 = 1)
  a/0
""", 1

test_vm """
  (var a (_ 0))
  (a/0 = 1)
  a/0
""", 1

test_vm """
  (var a [1])
  (a/0 += 1)
  a/0
""", 2

test_vm """
  ($ns/a = 1)
  ($ns/a += 1)
  a
""", 2

test_vm """
  (ns n
    (ns m)
  )
  (n/m/a = 1)
  n/m/a
""", 1

test_vm """
  (ns n
    (ns m)
  )
  (n/m/a = 1)
  (n/m/a += 1)
  n/m/a
""", 2

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

test_vm "(nil || 1)", 1

# Additional variable tests - single line expressions
test_vm "(var a 1) a", 1
test_vm "(var a 1) (a = 2) a", 2
test_vm "(var a) (a = 2) a", 2

# Simple do block test
test_vm "(do 1 2)", 2

# Test self keyword - returns nil in reference implementation
test_vm "self", NIL

# Array and map validation tests
test_vm """
  (var a 1)
  (var b 2)
  [a b]
""", proc(r: Value) =
  check r.ref.arr[0] == 1.to_value()
  check r.ref.arr[1] == 2.to_value()

test_vm """
  (var a 1)
  (var b 2)
  {^a a ^b b}
""", proc(r: Value) =
  check r.ref.map["a".to_key()] == 1.to_value()
  check r.ref.map["b".to_key()] == 2.to_value()

# Gene expression tests
test_vm """
  (var a 1)
  (var b 2)
  (:test ^a a b)
""", proc(r: Value) =
  check r.gene.props["a".to_key()] == 1.to_value()
  check r.gene.children[0] == 2.to_value()

# Test simple spread operator first
test_vm """
  (... [2 3])
""", proc(r: Value) =
  check r.kind == VkExplode

# Gene spread test
test_vm """
  (_ (... [2 3]) 4)
""", proc(r: Value) =
  check r.gene.children.len == 3
  check r.gene.children[0] == 2.to_value()
  check r.gene.children[1] == 3.to_value()
  check r.gene.children[2] == 4.to_value()

# test_vm "(if true 1)", 1
# test_vm "(if true then 1)", 1
# test_vm "(if not false 1)", 1
# test_vm "(if false 1 else 2)", 2
# Advanced conditional tests
test_vm "(if true then 1)", 1
# TODO: Fix if statement with not condition - currently returns true instead of 1
# test_vm "(if not false 1)", 1
test_vm """
  (if false
    1
  elif true
    2
  else
    3
  )
""", 2

test_vm """
  (if false
    1
  elif false
    2
  else
    3
  )
""", 3

# void operation test
test_vm """
  (void 1 2)
""", NIL

# $with context test
test_vm """
  ($with 1
    self
  )
""", 1

# $tap operations
test_vm """
  ($tap 1
    (assert (self == 1))
    2
  )
""", 1

# test_vm """
#   ($tap 1 :i
#     (assert (i == 1))
#     2
#   )
# """, 1

# test_vm """
#   (var a 1)
#   ($tap a :i
#     (assert (i == 1))
#     2
#   )
# """, 1

# Advanced loop control
echo "Running advanced loop control test..."
test_vm """
  (var i 0)
  (loop
    (i += 1)
    (if (i < 5)
      (continue)
    else
      (break)
    )
    (i = 10000)  # should not reach here
  )
  i
""", 5

# while loop tests
test_vm """
  (var i 0)
  (while (i < 3)
    (i += 1)
  )
  i
""", 3

test_vm """
  (var i 0)
  (while true
    (i += 1)
    (if (i < 3)
      (continue)
    else
      (break)
    )
    (i = 10000)  # should not reach here
  )
  i
""", 3

# eval operations
test_vm """
  (var a 1)
  (eval :a)
""", 1

test_vm """
  (var a 1)
  (var b 2)
  (eval :a :b)
""", 2

# spread operator tests
test_vm """
  (var a [2 3])
  [1 a... 4]
""", new_array_value(1, 2, 3, 4)

test_vm """
  [1 (... [2 3]) 4]
""", new_array_value(1, 2, 3, 4)

# $parse operation
test_vm """
  ($parse "true")
""", true

test_vm """
  (eval ($parse "(1 + 2)"))
""", 3