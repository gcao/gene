import unittest, tables

import gene/types

import ./helpers

test_vm "nil", NIL
test_vm "1", 1
test_vm "true", true
test_vm "false", false
test_vm "_", PLACEHOLDER
test_vm "\"string\"", "string"

# test_vm ":a", new_gene_symbol("a")

# test_vm "[]", new_gene_vec()
# test_vm "[1 2]", new_gene_vec(1, 2)

# test_vm "{}", Table[string, Value]()
# test_vm "{^a 1}", {"a": new_gene_int(1)}.toTable

# test_vm "1 2 3", 3

# test_vm "(1 + 2)", 3
# test_vm "(3 - 2)", 1
# test_vm "(2 * 3)", 6
# test_vm "(6 / 2)", 3.0

# test_vm "(2 < 3)", true
# test_vm "(2 < 2)", false
# test_vm "(2 <= 2)", true
# test_vm "(2 <= 1)", false
# test_vm "(2 > 1)", true
# test_vm "(2 > 2)", false
# test_vm "(2 >= 2)", true
# test_vm "(2 >= 3)", false
# test_vm "(2 == 2)", true
# test_vm "(2 == 3)", false
# test_vm "(2 != 3)", true
# test_vm "(2 != 2)", false

# test_vm "(true  && true)",  true
# test_vm "(true  && false)", false
# test_vm "(false && false)", false
# test_vm "(true  || true)",  true
# test_vm "(true  || false)", true
# test_vm "(false || false)", false

# # && and || are short-circuiting
# # test_vm "(false && error)", false
# # test_vm "(true  || error)", true

# # test_vm "(1 || 2)", 1
# # test_vm "(false || 1)", 1

# # (do ...) will create a scope if needed, execute all statements and return the result of the last statement.
# # `catch` and `ensure` can be used inside `do`.
# # `ensure` will run after `catch` if both are present? but the exception thrown in `ensure` will be ignored?

# test_vm """
#   (do 1 2 3)
# """, 3

# test_vm """
#   (if false
#     1
#   )
# """, Value(kind: VkNil)

# test_vm """
#   (if true
#     # do nothing
#   else
#     1
#   )
# """, Value(kind: VkNil)

# test_vm """
#   (if true
#     1
#   else
#     2
#   )
# """, 1

# test_vm """
#   (if false
#     1
#   else
#     2
#   )
# """, 2

# test_vm """
#   (var i 1)
# """, 1

# test_vm """
#   (var i 1)
#   i
# """, 1

# test_vm """
#   (var a 1)
#   (var b 2)
#   [a b]
# """, new_gene_vec(1, 2)

# test_vm """
#   (var a 1)
#   (var b 2)
#   {^a a ^b b}
# """, {"a": new_gene_int(1), "b": new_gene_int(2)}.toTable

# test_vm """
#   (var i 1)
#   (i = 2)
#   i
# """, 2

# test_vm """
#   (var i 1)
#   (i + 2)
# """, 3

# test_vm """
#   (var a (if false 1))
#   a
# """, Value(kind: VkNil)

# test_vm """
#   (do
#     (var i 1)
#     i
#   )
# """, 1

# test_vm """
#   # ($_print_instructions)
#   (loop
#     1
#     (break)
#   )
#   # ($_print_registers)
#   2
# """, 2

# test_vm """
#   (loop
#     (break 1)
#   )
# """, 1

# test_vm ":(1 + 2)", proc(r: Value) =
#   check r.gene_type == 1
#   check r.gene_children[0] == new_gene_symbol("+")
#   check r.gene_children[1] == 2

# test_vm "(_ 1 2)", proc(r: Value) =
#   check r.gene_children[0] == 1
#   check r.gene_children[1] == 2

# test_vm "(:a 1 2)", proc(r: Value) =
#   check r.gene_type == new_gene_symbol("a")
#   check r.gene_children[0] == 1
#   check r.gene_children[1] == 2

# test_vm """
#   (var x {^a 1})
#   x/a
# """, 1

# test_vm """
#   (var x (_ ^a 1))
#   x/a
# """, 1

# test_vm """
#   (var x [1 2])
#   x/0
# """, 1

# test_vm """
#   (var x (_ 1 2))
#   x/0
# """, 1

# test_vm """
#   (var x {^a [1 2]})
#   x/a/1
# """, 2
