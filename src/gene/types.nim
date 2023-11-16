import tables, re, bitops, unicode, strformat

type
  ValueKind* = enum
    # void vs nil vs placeholder:
    #   void has special meaning in some places (e.g. templates)
    #   nil is the default/uninitialized value.
    #   placeholder can be interpreted any way we want
    VkNil = 0
    VkVoid
    VkPlaceholder
    VkPointer
    VkBool
    VkInt
    VkFloat
    VkChar    # Support ascii and unicode characters
    VkString
    VkSymbol

    VkArray
    VkMap
    VkGene

  Value* = distinct int64

  Reference* = ref object
    case kind*: ValueKind
      of VkString, VkSymbol:
        str*: string
      of VkArray:
        arr*: seq[Value]
      of VkMap:
        map*: Table[string, Value]
      else:
        discard

  Gene* = ref object
    `type`*: Value
    props*: Table[string, Value]
    children*: seq[Value]

  # No symbols should be removed.
  ManagedSymbols = object
    store: seq[string]
    map:  Table[string, int64]

  ManagedReferences = object
    data: seq[Reference]
    free: seq[int64]

  ManagedGenes = object
    data: seq[Gene]
    free: seq[int64]

const I64_MASK = 0xC000_0000_0000_0000u64
const F64_ZERO = 0x2000_0000_0000_0000u64

const AND_MASK = 0x0000_FFFF_FFFF_FFFFu64

const NIL_PREFIX = 0x7FFA
const NIL* = cast[Value](0x7FFA_A000_0000_0000u64)

const BOOL_PREFIX = 0x7FFC
const TRUE*  = cast[Value](0x7FFC_A000_0000_0000u64)
const FALSE* = cast[Value](0x7FFC_0000_0000_0000u64)

const POINTER_PREFIX = 0x7FFB

const REF_PREFIX = 0x7FFD
const REF_MASK = 0x7FFD_0000_0000_0000u64

const GENE_PREFIX = 0x7FF8
const GENE_MASK = 0x7FF8_0000_0000_0000u64

const OTHER_PREFIX = 0x7FFE
const OTHER_MASK = 0x7FFE_FF00_0000_0000u64

const VOID* = cast[Value](0x7FFE_0000_0000_0000u64)
const PLACEHOLDER* = cast[Value](0x7FFE_0100_0000_0000u64)

const CHAR_PREFIX = 0xFFFE
const CHAR_MASK = 0xFFFE_0000_0000_0000u64

const SHORT_STR_PREFIX  = 0xFFF8
const LONG_STR_PREFIX = 0xFFF9
const SHORT_STR_MASK = 0xFFF8_0000_0000_0000u64
const LONG_STR_MASK = 0xFFF9_0000_0000_0000u64

const EMPTY_STRING = 0xFFF8_0000_0000_0000u64

const SYMBOL_PREFIX  = 0xFFFA
const EMPTY_SYMBOL = 0xFFFA_0000_0000_0000u64

#################### Definitions #################

proc `$`*(self: Value): string
proc `$`*(self: Reference): string

proc to_ref*(v: Value): Reference

proc str*(v: Value): string {.inline.}
proc to_value*(v: char): Value {.inline.}

proc get_symbol*(i: int64): string {.inline.}

#################### Common ######################

proc todo*() =
  raise new_exception(Exception, "TODO")

proc todo*(message: string) =
  raise new_exception(Exception, "TODO: " & message)

proc not_allowed*(message: string) =
  raise new_exception(Exception, message)

proc not_allowed*() =
  not_allowed("Error: should not arrive here.")

proc to_binstr*(v: int64): string =
  re.replacef(fmt"{v: 065b}", re.re"([01]{8})", "$1 ")

#################### Reference ###################

var REFS*: ManagedReferences

proc `$`*(self: Reference): string =
  $self.kind

proc add_ref*(v: Reference): int64 =
  if REFS.free.len == 0:
    result = REFS.data.len
    REFS.data.add(v)
  else:
    result = REFS.free.pop()
    REFS.data[result] = v
  # echo REFS.data, " ", result

proc get_ref*(i: int64): Reference =
  REFS.data[i]

proc free_ref*(i: int64) =
  REFS.data[i] = nil
  REFS.free.add(i)

proc to_ref*(v: Value): Reference =
  get_ref(cast[int64](bitand(AND_MASK, v.uint64)))

#################### Value ######################

proc `==`*(a, b: Value): bool {.inline.} =
  cast[int64](a) == cast[int64](b)

proc kind*(v: Value): ValueKind {.inline.} =
  let v1 = cast[uint64](v)
  case cast[int64](v1.shr(48)):
    of NIL_PREFIX:
      return VkNil
    of BOOL_PREFIX:
      return VkBool
    of POINTER_PREFIX:
      return VkPointer
    of REF_PREFIX:
      # It may not be a bad idea to store the reference kind in the value itself.
      # However we may later support changing reference in place, so it may not be a good idea.
      let r = get_ref(cast[int64](bitand(v1, AND_MASK)))
      return r.kind
    of GENE_PREFIX:
      return VkGene
    of CHAR_PREFIX:
      return VkChar
    of SHORT_STR_PREFIX, LONG_STR_PREFIX:
      return VkString
    of SYMBOL_PREFIX:
      return VkSymbol
    of OTHER_PREFIX:
      let other_info = cast[Value](bitand(v1, OTHER_MASK))
      case other_info:
        of VOID:
          return VkVoid
        of PLACEHOLDER:
          return VkPlaceholder
        else:
          todo()
    else:
      if bitand(v1, I64_MASK) == 0:
        return VkInt
      else:
        return VkFloat

proc `$`*(self: Value): string =
  case self.kind:
    of VkString:
      result = $self.to_ref.str
    of VkSymbol:
      todo()
    else:
      result = $self.kind

proc is_nil*(v: Value): bool {.inline.} =
  v == NIL

proc to_float*(v: Value): float64 {.inline.} =
  if cast[uint64](v) == F64_ZERO:
    return 0.0
  else:
    return cast[float64](v)

proc to_value*(v: float64): Value {.inline.} =
  if v == 0.0:
    return cast[Value](F64_ZERO)
  else:
    return cast[Value](v)

converter to_bool*(v: Value): bool {.inline.} =
  not (v == FALSE or v == NIL)

proc to_value*(v: bool): Value {.inline.} =
  if v:
    return TRUE
  else:
    return FALSE

proc to_pointer*(v: Value): pointer {.inline.} =
  cast[pointer](bitand(cast[int64](v), 0x0000FFFFFFFFFFFF))

proc to_value*(v: pointer): Value {.inline.} =
  if v.is_nil:
    return NIL
  else:
    cast[Value](bitor(cast[int64](v), 0x7FFB000000000000))

# Applicable to array, string, symbol, gene etc
proc `[]`*(self: Value, i: int): Value {.inline.} =
  let v = cast[uint64](self)
  case cast[int64](v.shr(48)):
    of NIL_PREFIX:
      return NIL
    of REF_PREFIX:
      # It may not be a bad idea to store the reference kind in the value itself.
      # However we may later support changing reference in place, so it may not be a good idea.
      let r = get_ref(cast[int64](bitand(v, AND_MASK)))
      if r.kind == VkArray:
        if i >= r.arr.len:
          return NIL
        else:
          return r.arr[i]
      else:
        todo($r.kind)
    of GENE_PREFIX:
      todo("VkGene")
    of SHORT_STR_PREFIX, LONG_STR_PREFIX:
      if i >= self.str().len:
        return NIL
      else:
        return self.str()[i].to_value()
    of SYMBOL_PREFIX:
      todo("VkSymbol")
    else:
      todo()

# Applicable to array, string, symbol, gene etc
proc size*(self: Value): int {.inline.} =
  let v = cast[uint64](self)
  case cast[int64](v.shr(48)):
    of NIL_PREFIX:
      return 0
    of REF_PREFIX:
      # It may not be a bad idea to store the reference kind in the value itself.
      # However we may later support changing reference in place, so it may not be a good idea.
      let r = get_ref(cast[int64](bitand(v, AND_MASK)))
      if r.kind == VkArray:
        return r.arr.len
      else:
        todo($r.kind)
    of GENE_PREFIX:
      todo("VkGene")
    of SHORT_STR_PREFIX, LONG_STR_PREFIX:
      todo("VkString")
    of SYMBOL_PREFIX:
      todo("VkSymbol")
    else:
      todo()

#################### Int ########################

# TODO: check range of value is within int61

converter to_value*(v: int): Value {.inline.} =
  result = cast[Value](v.int64)

converter to_value*(v: int64): Value {.inline.} =
  result = cast[Value](v)

converter to_int*(v: Value): int64 {.inline.} =
  result = cast[int64](v)

#################### String #####################

proc get_str*(i: int64): string =
  get_ref(i).str

proc new_str*(s: string): int64 =
  add_ref(Reference(kind: VkString, str: s))

proc free_str*(i: int64) =
  free_ref(i)

proc to_value*(v: char): Value {.inline.} =
  cast[Value](bitor(CHAR_MASK, v.ord.uint64))

proc str*(v: Value): string {.inline.} =
  let v1 = cast[uint64](v)
  # echo v1.shr(48).int64.to_binstr
  case cast[int64](v1.shr(48)):
    of SHORT_STR_PREFIX:
      var x = cast[int64](bitand(cast[uint64](v1), AND_MASK))
      # echo x.to_binstr
      if x > 0xFF_FFFF:
        if x > 0xFFFF_FFFF:
          if x > 0xFF_FFFF_FFFF: # 6 chars
            result = new_string(6)
            copy_mem(result[0].addr, x.addr, 6)
          else: # 5 chars
            result = new_string(5)
            copy_mem(result[0].addr, x.addr, 5)
        else: # 4 chars
          result = new_string(4)
          copy_mem(result[0].addr, x.addr, 4)
      else:
        if x > 0xFF:
          if x > 0xFFFF: # 3 chars
            result = new_string(3)
            copy_mem(result[0].addr, x.addr, 3)
          else: # 2 chars
            result = new_string(2)
            copy_mem(result[0].addr, x.addr, 2)
        else:
          if x > 0: # 1 chars
            result = new_string(1)
            copy_mem(result[0].addr, x.addr, 1)
          else: # 0 char
            result = ""

    of LONG_STR_PREFIX:
      var x = cast[int64](bitand(cast[uint64](v1), AND_MASK))
      result = get_str(x)

    of SYMBOL_PREFIX:
      var x = cast[int64](bitand(cast[uint64](v1), AND_MASK))
      result = get_symbol(x)

    else:
      not_allowed(fmt"${v} is not a string.")

proc to_value*(v: string): Value {.inline.} =
  case v.len:
    of 0:
      return cast[Value](EMPTY_STRING)
    of 1:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64))
    of 2:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64))
    of 3:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64, v[2].ord.shl(16).uint64))
    of 4:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64, v[2].ord.shl(16).uint64, v[3].ord.shl(24).uint64))
    of 5:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64, v[2].ord.shl(16).uint64, v[3].ord.shl(24).uint64, v[4].ord.shl(32).uint64))
    of 6:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64, v[2].ord.shl(16).uint64, v[3].ord.shl(24).uint64, v[4].ord.shl(32).uint64, v[5].ord.shl(40).uint64))
    else:
      let i = new_str(v).uint64
      return cast[Value](bitor(LONG_STR_MASK, i))

converter to_value*(v: Rune): Value {.inline.} =
  todo()

#################### Symbol #####################

var SYMBOLS*: ManagedSymbols

proc get_symbol*(i: int64): string {.inline.} =
  SYMBOLS.store[i]

proc to_symbol*(s: string): Value {.inline.} =
  if SYMBOLS.map.has_key(s):
    let i = SYMBOLS.map[s].uint64
    result = cast[Value](bitor(EMPTY_SYMBOL, i))
  else:
    result = cast[Value](bitor(EMPTY_SYMBOL, SYMBOLS.store.len.uint64))
    SYMBOLS.map[s] = SYMBOLS.store.len
    SYMBOLS.store.add(s)

#################### Array ######################

proc new_array*(v: varargs[Value]): Value =
  let i = add_ref(Reference(kind: VkArray, arr: @v)).uint64
  cast[Value](bitor(REF_MASK, i))

#################### Map #########################

proc new_map*(): Value =
  let i = add_ref(Reference(kind: VkMap)).uint64
  cast[Value](bitor(REF_MASK, i))

#################### Gene ########################

var GENES*: ManagedGenes

proc add_gene*(v: Gene): int64 =
  if GENES.free.len == 0:
    result = GENES.data.len
    GENES.data.add(v)
  else:
    result = GENES.free.pop()
    GENES.data[result] = v
  # echo GENES.data, " ", result

proc get_gene*(i: int64): Gene =
  GENES.data[i]

proc free_gene*(i: int64) =
  GENES.data[i] = nil
  GENES.free.add(i)

proc new_gene*(): Value =
  let i = add_gene(Gene()).uint64
  cast[Value](bitor(GENE_MASK, i))

#################### Helpers #####################

proc init_values*() =
  REFS = ManagedReferences()
  GENES = ManagedGenes()
  SYMBOLS = ManagedSymbols()

init_values()
