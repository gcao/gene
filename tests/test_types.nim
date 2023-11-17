import unicode
import unittest

import gene/types

test "Value kind":
  check NIL.kind == VkNil
  check VOID.kind == VkVoid
  check PLACEHOLDER.kind == VkPlaceholder

  check TRUE.kind == VkBool
  check FALSE.kind == VkBool

  check 0.Value.kind == VkInt

  var a = 1
  check a.addr.to_value().kind == VkPointer

  check 'a'.to_value().kind == VkChar
  check  "你".rune_at(0).to_value().kind == VkChar

  check "".to_value().kind == VkString
  check "a".to_value().kind == VkString
  check "ab".to_value().kind == VkString
  check "abc".to_value().kind == VkString
  check "abcd".to_value().kind == VkString
  check "abcde".to_value().kind == VkString
  check "abcdef".to_value().kind == VkString
  check "abcdefghij".to_value().kind == VkString
  check "你".to_value().kind == VkString
  check "你从哪里来？".to_value().kind == VkString

  check new_array().kind == VkArray
  check new_map().kind == VkMap
  check new_gene().kind == VkGene

  check "".to_symbol().kind == VkSymbol
  check "a".to_symbol().kind == VkSymbol
  check "abcdefghij".to_symbol().kind == VkSymbol
  check "你".to_symbol().kind == VkSymbol
  check "你从哪里来？".to_symbol().kind == VkSymbol

test "Value conversion":
  check nil.to_value().is_nil() == true
  check nil.to_value() == NIL

  check true.to_value().to_bool() == true
  check false.to_value().to_bool() == false
  check NIL.to_bool() == false
  check 0.Value.to_bool() == true

  check 1.Value.to_int() == 1
  check 0x20.shl(56).Value.to_float() == 0.0
  check 1.1.to_value().to_float() == 1.1
  var a = 1
  check cast[ptr int64](a.addr.to_value().to_pointer())[] == 1

  check "".to_value().str() == ""
  check "a".to_value().str() == "a"
  check "ab".to_value().str() == "ab"
  check "abc".to_value().str() == "abc"
  check "abcd".to_value().str() == "abcd"
  check "abcde".to_value().str() == "abcde"
  check "abcdef".to_value().str() == "abcdef"
  check "abcdefghij".to_value().str() == "abcdefghij"
  check "你".to_value().str() == "你"
  check "你从哪里来？".to_value().str() == "你从哪里来？"

  check "".to_symbol().str() == ""
  check "abc".to_symbol().str() == "abc"
  check "abcdefghij".to_symbol().str() == "abcdefghij"
  check "你".to_symbol().str() == "你"
  check "你从哪里来？".to_symbol().str() == "你从哪里来？"

test "String / char":
  check "abc".to_value()[0] == 'a'.to_value()
  check "你".to_value()[0] == "你".rune_at(0)
  check "你从哪里来？".to_value()[0] == "你".rune_at(0)
  check "你从哪里来？".to_value()[1] == "从".rune_at(0)
  check "你".to_value().size == 1

test "Array":
  check new_array().size == 0
  check new_array(1).size == 1

  let a = new_array(1)
  check a[0] == 1
  check a[1] == NIL
