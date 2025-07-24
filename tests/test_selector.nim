import unittest, tables

import gene/types

import ./helpers

# Selector
# * Borrow ideas from XPath/XSLT/CSS
#   * XPath: locate any node or group of nodes in a xml document
#   * XSLT: transform a xml document to another
#   * CSS: apply styles on any element or group of elements in a html document
#   * CSS Selectors: similar to XPath
# * Mode:
#   * Match first
#   * Match all
# * Flags:
#   * error_on_no_match: Throw error if none is matched
# * Types
#   * Index: 0,1,..-2,-1
#   * Index list
#   * Index range: 0..2
#   * Property name
#   * Property name list
#   * Property name pattern: /^test/
#   * Gene type: :$type
#   * Gene properties: :$props
#   * Gene property names: :$keys
#   * Gene property values: :$values
#   * Gene children: :$children
#   * Descendants: :$descendants - how does match work for this? self.gene.children and their descendants?
#   * Self and descendants: _
#   * Predicate (fnx it ...)
#   * Composite: [0 1 (range 3 5)]
#
# SelectorResult
# * Single value
# * Array or map or gene
#
# Define styles for gene value matched by a selector (like CSS).
# This should live outside the gene value.
# Inline styles can be defined for a gene. However it is not related to selectors.
# Shortcuts like those in css selectors
#   * id: &x matches (_ ^id "x")
#   * type: :y matches (y)
#   * tag (like css classes): ?t1?t2 matches (_ ^tags ["t1" "t2"])
#
# Transform a gene value based on selectors and actions (like XSLT)
# Should support non-gene output, e.g. raw strings.
# Actions:
#   * Copy value matched by selector to output
#   * Call callback with value, add result to output
#
# Distinguish predicates, transformers and callbacks etc:
# * Predicates return special list of path=value or value
# * Callbacks' does not return special list, thus discarded

# @p        <=> (@ "p")
# (@p)      <=> ((@ "p"))       <=> /p        <=> (self ./p)
# (@p)      <=> ((@ "p") self)
# (/p = 1)  <=> ((@ "p") = 1)   <=> (self ./p = 1)
# (/p += 1) <=> (/p = (/p + 1)) <=> ((@ "p") = ((@ "p") + 1))

# (./p)     <=> (self ./p)      <=> (self ./ "p")
# (/p = 1)  <=> ($set self @p 1)

# (@ "test")             # target["test"]
# @test                  # target["test"]
# (@ 0 "test")           # target[0]["test"]
# @0/test                # target[0]["test"]
# (@ (@ 0) "test")       # target[0]["test"]
# (@ [0 1] "test")       # target[0, 1]["test"]
# (@ (range 0 3) :type)  # target[0..3].type
# (@* [0 "test"] [1 "another"])  # target[0]["test"] + target[1]["another"]
#
# /0/test                   # ((@ 0 "test") self)
# (./ 0 "test")             # ((@ 0 "test") self)
# (./0/test)                # ((@ 0 "test") self)
# (./ :type)                # ((@ :type) self)
# (obj ./ 0 "test")         # ((@ 0 "test") obj)
# ((@* 0 1) self)
# (./ 0 "test" = "value")   # (assign self (@ 0 "test") "value")
# (./test)                  # ((@ "test") self)
# (./first/second)          # ((@ "first" "second") self)
#
# * Search
# * Update
# * Remove

test_interpreter """
  ({^a "A"} ./ "a")
""", "A"

test_interpreter """
  ({} ./ "a")
""", Value(kind: VkNil)

test_interpreter """
  ({} ./ "a" 1)
""", Value(kind: VkNil)

test_interpreter """
  ({^a "A"} ./a)
""", "A"

test_interpreter """
  ((_ ^a "A") ./ "a")
""", "A"

test_interpreter """
  ([1 2] ./ 0)
""", 1

test_interpreter """
  ([1 2] ./0)
""", 1

test_interpreter """
  ([0 1 2 -2 -1] ./ (0 .. 1))
""", @[0, 1]

test_interpreter """
  ([0 1 2 -2 -1] ./ (0 .. -2))
""", @[0, 1, 2, -2]

test_interpreter """
  ([0 1 2 -2 -1] ./ (-2 .. -1))
""", @[-2, -1]

test_interpreter """
  ([0 1 2 -2 -1] ./ (-1 .. -1))
""", @[-1]

test_interpreter """
  ([0 1 2 -2 -1] ./ (6 .. -1))
""", @[]

test_interpreter """
  ([] ./ (0 .. 1))
""", @[]

test_interpreter """
  ([] ./ (-2 .. -1))
""", @[]

test_interpreter """
  ([1] ./ (-2 .. -1))
""", @[1]

test_interpreter """
  ((_ 0 1 2 -2 -1) ./ (0 .. -2))
""", @[0, 1, 2, -2]

test_interpreter """
  ((_) ./ (-2 .. -1))
""", @[]

test_interpreter """
  ((_) ./ (0 .. -2))
""", @[]

test_interpreter """
  ((_ 1) ./ (-2 .. -1))
""", @[1]

test_interpreter """
  ((@ "test") {^test 1})
""", 1

test_interpreter """
  (@test {^test 1})
""", 1

test_interpreter """
  ((@ "test" 0) {^test [1]})
""", 1

test_interpreter """
  (@test/0 {^test [1]})
""", 1

test_interpreter """
  (@0/test [{^test 1}])
""", 1

test_interpreter """
  ([{^test 1}] ./ 0 "test")
""", 1

test_interpreter """
  ([{^test 1}] ./0/test)
""", 1

test_interpreter """
  ($with [{^test 1}]
    (./ 0 "test")
  )
""", 1

test_interpreter """
  (var a [0])
  (a/0 = 1)
  a/0
""", 1

test_interpreter """
  (var a [0])
  a/-1
""", 0

test_interpreter """
  ($with [{^test 1}]
    (./0/test)
  )
""", 1

test_interpreter """
  (var a {})
  ($set a @test 1)
  (@test a)
""", 1

test_interpreter """
  (var a [0])
  ($set a @0 1)
  a
""", @[1]

test_interpreter """
  (class A)
  (var a (new A))
  ($set a @test 1)
  (@test a)
""", 1

test_interpreter """
  (class A
    (.fn test x
      ($set @x x)
    )
  )
  (var a (new A))
  (a .test 1)
  a/x
""", 1

test_interpreter """
  (class A
    (.ctor []
      (/description = "Class A")
    )
  )
  (new A)
""", proc(r: Value) =
  check r.instance_props["description"] == "Class A"

test_interpreter """
  ((@ 0) [1 2])
""", 1

test_interpreter """
  ((@ 0 "test") [{^test 1}])
""", 1

test_interpreter """
  ((@ (@ 0)) [1 2])
""", 1

test_interpreter """
  ((@ [0 1]) [1 2])
""", @[1, 2]

test_interpreter """
  ((@ ["a" "b"]) {^a 1 ^b 2 ^c 3})
""", @[1, 2]

test_interpreter """
  ((@* 0 1) [1 2])
""", @[1, 2]

test_interpreter """
  (class A
    (.fn test _
      1
    )
  )
  ((@. "test") (new A))
""", 1

test_interpreter """
  (class A
    (.fn test _
      1
    )
  )
  (@.test (new A))
""", 1

test_interpreter """
  (class A
    (.fn test _
      1
    )
  )
  (@0/.test [(new A)])
""", 1

test_interpreter """
  ((@ :TEST 0)
    (_ (:TEST 1))
  )
""", @[1]

# test_core """
#   (((@ _)
#     (_ (:TEST 1))
#     # Matches
#     # self: (_ (:TEST 1))
#     # descendants: (:TEST 1), 1
#   ).size)
# """, 3

# test_interpreter """
#   (var a)
#   (fn f v
#     (a = v)
#     (:void)
#   )
#   ((@ 0 f) [123])
#   a
# """, 123

# test_core """
#   ((@ 0 gene/inc) [1])
# """, @[2]

# test_interpreter """
#   ([] ./ 0 ^default 123)
# """, 123

# test_interpreter """
#   ([] ./0 ^default 123)
# """, 123

# test_interpreter """
#   (@0 [] ^default 123)
# """, 123
