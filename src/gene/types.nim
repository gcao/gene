import math, tables, sets, re, bitops, unicode, strformat
import random
import dynlib

type
  ValueKind* {.size: sizeof(int16) .} = enum
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
    VkComplexSymbol

    VkArray
    VkSet
    VkMap
    VkGene
    VkStream
    VkDocument

    VkQuote
    VkUnquote

    VkApplication
    VkPackage
    VkModule
    VkNamespace
    VkFunction
    VkMacro
    VkBlock
    VkClass
    VkMethod
    VkBoundMethod
    VkInstance
    VkNativeFn
    VkNativeFn2

  Value* = distinct int64

  Reference* = object
    ref_count*: int32
    case kind*: ValueKind
      of VkDocument:
        doc*: Document
      of VkString, VkSymbol:
        str*: string
      of VkArray:
        arr*: seq[Value]
      of VkSet:
        set*: HashSet[Value]
      of VkMap:
        map*: Table[string, Value]
      of VkStream:
        stream*: seq[Value]
        stream_index*: int64
        stream_ended*: bool
      of VkComplexSymbol:
        csymbol*: seq[string]
      of VkQuote:
        quote*: Value
      of VkUnquote:
        unquote*: Value
        unquote_discard*: bool
      of VkApplication:
        app*: Application
      of VkPackage:
        pkg*: Package
      of VkModule:
        module*: Module
      of VkNamespace:
        ns*: Namespace
      of VkFunction:
        fn*: Function
      of VkMacro:
        `macro`*: Macro
      of VkBlock:
        `block`*: Block
      of VkClass:
        class*: Class
      of VkMethod:
        `method`*: Method
      of VkBoundMethod:
        bound_method*: BoundMethod
      of VkInstance:
        instance_class*: Class
        instance_props*: Table[string, Value]
      of VkNativeFn:
        native_fn*: NativeFn
      of VkNativeFn2:
        native_fn2*: NativeFn2
      else:
        discard

  Gene* = object
    ref_count*: int32
    `type`*: Value
    props*: Table[string, Value]
    children*: seq[Value]

  String* = object
    ref_count*: int32
    str*: string

  Document* = ref object
    `type`: Value
    props*: Table[string, Value]
    children*: seq[Value]
    # references*: References # Uncomment this when it's needed.

  # index of a name in a scope
  NameIndexScope* = distinct int

  Scope* = ref object
    parent*: Scope
    parent_index_max*: NameIndexScope
    members*:  seq[Value]
    # Value of mappings is composed of two bytes:
    #   first is the optional index in self.mapping_history + 1
    #   second is the index in self.members
    mappings*: Table[string, int]
    mapping_history*: seq[seq[NameIndexScope]]

  ## This is the root of a running application
  Application* = ref object
    name*: string         # Default to base name of command, can be changed, e.g. ($set_app_name "...")
    pkg*: Package         # Entry package for the application
    ns*: Namespace
    cmd*: string
    args*: seq[string]
    main_module*: Module
    # dep_root*: DependencyRoot
    props*: Table[string, Value]  # Additional properties

    global_ns*     : Value
    gene_ns*       : Value
    genex_ns*      : Value

    object_class*   : Value
    nil_class*      : Value
    bool_class*     : Value
    int_class*      : Value
    float_class*    : Value
    char_class*     : Value
    string_class*   : Value
    symbol_class*   : Value
    complex_symbol_class*: Value
    array_class*    : Value
    map_class*      : Value
    set_class*      : Value
    gene_class*     : Value
    stream_class*   : Value
    document_class* : Value
    regex_class*    : Value
    range_class*    : Value
    date_class*     : Value
    datetime_class* : Value
    time_class*     : Value
    timezone_class* : Value
    selector_class* : Value
    exception_class*: Value
    class_class*    : Value
    mixin_class*    : Value
    application_class*: Value
    package_class*  : Value
    module_class*   : Value
    namespace_class*: Value
    function_class* : Value
    macro_class*    : Value
    block_class*    : Value
    future_class*   : Value
    thread_class*   : Value
    thread_message_class* : Value
    thread_message_type_class* : Value
    file_class*     : Value

  Package* = ref object
    dir*: string          # Where the package assets are installed
    adhoc*: bool          # Adhoc package is created when package.gene is not found
    ns*: Namespace
    name*: string
    version*: Value
    license*: Value
    globals*: seq[string] # Global variables defined by this package
    # dependencies*: Table[string, Dependency]
    homepage*: string
    src_path*: string     # Default to "src"
    test_path*: string    # Default to "tests"
    asset_path*: string   # Default to "assets"
    build_path*: string   # Default to "build"
    load_paths*: seq[string]
    init_modules*: seq[string]    # Modules that should be loaded when the package is used the first time
    props*: Table[string, Value]  # Additional properties
    # doc*: Document        # content of package.gene

  SourceType* = enum
    StFile
    StVirtualFile # e.g. a file embeded in the source code or an archive file.
    StInline
    StRepl
    StEval

  Module* = ref object
    source_type*: SourceType
    source*: Value
    pkg*: Package         # Package in which the module is defined
    name*: string
    ns*: Namespace
    handle*: LibHandle    # Optional handle for dynamic lib
    props*: Table[string, Value]  # Additional properties

  Namespace* = ref object
    module*: Module
    parent*: Namespace
    stop_inheritance*: bool  # When set to true, stop looking up for members from parent namespaces
    name*: string
    members*: Table[string, Value]
    proxies*: Table[string, Value] # Ask the proxy to look it up instead of checking members and parent
    on_member_missing*: seq[Value]

  Class* = ref object
    parent*: Class
    name*: string
    constructor*: Value
    methods*: Table[string, Method]
    on_extended*: Value
    # method_missing*: Value
    ns*: Namespace # Class can act like a namespace
    for_singleton*: bool # if it's the class associated with a single object, can not be extended

  Method* = ref object
    class*: Class
    name*: string
    callable*: Value
    # public*: bool
    is_macro*: bool

  BoundMethod* = object
    self*: Value
    class*: Class       # Note that class may be different from method.class
    `method`*: Method

  Function* = ref object
    async*: bool
    name*: string
    ns*: Namespace
    parent_scope*: Scope
    parent_scope_max*: NameIndexScope
    matcher*: RootMatcher
    matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: CompilationUnit
    # ret*: Expr

  Macro* = ref object
    ns*: Namespace
    name*: string
    parent_scope*: Scope
    parent_scope_max*: NameIndexScope
    matcher*: RootMatcher
    matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: CompilationUnit

  Block* = ref object
    # frame*: Frame
    ns*: Namespace
    parent_scope*: Scope
    parent_scope_max*: NameIndexScope
    matcher*: RootMatcher
    matching_hint*: MatchingHint
    body*: seq[Value]
    # body_compiled*: Expr
    body_compiled*: CompilationUnit

  MatchingMode* = enum
    MatchArguments # (fn f [a b] ...)
    MatchExpression # (match [a b] input): a and b will be defined
    MatchAssignment # ([a b] = input): a and b must be defined first

  # Match the whole input or the first child (if running in ArgumentMode)
  # Can have name, match nothing, or have group of children
  RootMatcher* = ref object
    mode*: MatchingMode
    children*: seq[Matcher]

  MatchingHintMode* = enum
    MhDefault
    MhNone
    MhSimpleData  # E.g. [a b]

  MatchingHint* = object
    mode*: MatchingHintMode

  MatcherKind* = enum
    MatchType
    MatchProp
    MatchData
    MatchLiteral

  Matcher* = ref object
    root*: RootMatcher
    kind*: MatcherKind
    next*: Matcher  # if kind is MatchData and is_splat is true, we may need to check next matcher
    name*: string
    is_prop*: bool
    literal*: Value # if kind is MatchLiteral, this is required
    # match_name*: bool # Match symbol to name - useful for (myif true then ... else ...)
    default_value*: Value
    # default_value_expr*: Expr
    is_splat*: bool
    min_left*: int # Minimum number of args following this
    children*: seq[Matcher]
    # required*: bool # computed property: true if splat is false and default value is not given

  MatchedFieldKind* = enum
    MfMissing
    MfSuccess
    MfTypeMismatch # E.g. map is passed but array or gene is expected

  MatchedField* = ref object
    kind*: MatchedFieldKind
    matcher*: Matcher
    value*: Value

  MatchResult* = ref object
    fields*: Table[string, MatchedField]

  Id* = uint64
  Label* = int32

  Compiler* = ref object
    output*: CompilationUnit
    quote_level*: int

  InstructionKind* {.size: sizeof(int16).} = enum
    IkNoop

    IkStart   # start a compilation unit
    IkEnd     # end a compilation unit

    IkScopeStart
    IkScopeEnd

    IkPushValue   # push value to the next slot
    IkPushNil
    IkPop

    IkVar
    IkVarValue
    IkAssign

    IkJump        # unconditional jump
    IkJumpIfFalse

    IkJumpIfMatchSuccess  # Special instruction for argument matching

    IkLoopStart
    IkLoopEnd
    IkContinue    # is added automatically before the loop end
    IkBreak

    IkAdd
    IkAddValue    # args: literal value
    IkSub
    IkMul
    IkDiv
    IkPow

    IkLt
    IkLtValue
    IkLe
    IkGt
    IkGe
    IkEq
    IkNe

    IkAnd
    IkOr

    IkCompileInit

    IkThrow

    # IkApplication
    # IkPackage
    # IkModule

    IkNamespace

    IkFunction
    IkReturn
    IkCallFunction
    IkCallFunctionNoArgs
    IkCallSimple  # call class or namespace body

    IkMacro
    IkCallMacro

    IkClass
    IkSubClass
    IkNew
    IkResolveMethod
    IkCallMethod
    IkCallMethodNoArgs
    IkCallInit

    IkMapStart
    IkMapSetProp        # args: key
    IkMapSetPropValue   # args: key, literal value
    IkMapEnd

    IkArrayStart
    IkArrayAddChild
    IkArrayAddChildValue # args: literal value
    IkArrayEnd

    IkGeneStart
    IkGeneStartDefault
    IkGeneStartMacro
    IkGeneStartMethod
    IkGeneStartMacroMethod
    IkGeneCheckType
    IkGeneSetType
    IkGeneSetProp
    IkGeneSetPropValue        # args: key, literal value
    IkGeneAddChild
    IkGeneAddChildValue       # args: literal value
    IkGeneEnd

    IkResolveSymbol
    IkSetMember
    IkGetMember
    IkSetChild
    IkGetChild

    IkSelf

    IkYield
    IkResume

    IkInternal

  Instruction* = object
    kind*: InstructionKind
    label*: Label
    arg0*: Value
    arg1*: Value

  CompilationUnitKind* = enum
    CkDefault
    CkFunction
    CkMacro
    CkBlock
    CkModule
    CkInit      # namespace / class / object initialization
    CkInline    # evaluation during execution

  CompilationUnit* = ref object
    id*: Id
    kind*: CompilationUnitKind
    matcher*: RootMatcher
    instructions*: seq[Instruction]
    labels*: Table[Label, int]
    skip_return*: bool

  Address* = object
    id*: Id
    pc*: int

  VirtualMachineState* = enum
    VmWaiting   # waiting for task
    VmRunning
    VmPaused

  VirtualMachine* = ref object
    state*: VirtualMachineState
    data*: VirtualMachineData
    trace*: bool

  VmCallback* = proc() {.gcsafe.}

  VirtualMachineData* = ref object
    is_main*: bool
    cur_block*: CompilationUnit
    pc*: int
    registers*: Registers
    code_mgr*: CodeManager

  Registers* = ref object
    caller*: Caller
    ns*: Namespace
    scope*: Scope
    self*: Value
    args*: Value
    match_result*: MatchResult
    data*: array[32, Value]
    next_slot*: int

  Caller* = ref object
    address*: Address
    registers*: Registers

  CodeManager* = ref object
    data*: Table[Id, CompilationUnit]

  # No symbols should be removed.
  ManagedSymbols = object
    store: seq[string]
    map:  Table[string, int64]

  Exception* = object of CatchableError
    instance*: Value  # instance of Gene exception class

  NotDefinedException* = object of Exception

  # Types related to command line argument parsing
  ArgumentError* = object of Exception

  NativeFn* = proc(vm_data: VirtualMachineData, args: Value): Value {.gcsafe, nimcall.}
  NativeFn2* = proc(vm_data: VirtualMachineData, args: Value): Value {.gcsafe.}

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

const VOID* = cast[Value](0x7FFE_0000_0000_0000u64)
const PLACEHOLDER* = cast[Value](0x7FFE_0100_0000_0000u64)

# Special variable used by the parser
const PARSER_IGNORE* = cast[Value](0x7FFE_0200_0000_0000u64)

const CHAR_MASK = 0x7FFE_0200_0000_0000u64
const CHAR2_MASK = 0x7FFE_0300_0000_0000u64
const CHAR3_MASK = 0x7FFE_0400_0000_0000u64
const CHAR4_MASK = 0x7FFE_0500_0000_0000u64

const SHORT_STR_PREFIX  = 0xFFF8
const SHORT_STR_MASK = 0xFFF8_0000_0000_0000u64
const LONG_STR_PREFIX  = 0xFFF9
const LONG_STR_MASK = 0xFFF9_0000_0000_0000u64

const EMPTY_STRING = 0xFFF8_0000_0000_0000u64

const SYMBOL_PREFIX  = 0xFFFA
const EMPTY_SYMBOL = 0xFFFA_0000_0000_0000u64

const BIGGEST_INT = 2^61 - 1

var VM* {.threadvar.}: VirtualMachine   # The current virtual machine
var App* {.threadvar.}: Value

var VmCreatedCallbacks*: seq[VmCallback] = @[]

randomize()

#################### Definitions #################

proc kind*(v: Value): ValueKind {.inline.}
proc `==`*(a, b: Value): bool {.no_side_effect.}
converter to_bool*(v: Value): bool {.inline.}

proc `$`*(self: Value): string
proc `$`*(self: ptr Reference): string

proc to_ref*(v: Value): ptr Reference

proc new_str*(s: string): ptr String
proc new_str_value*(s: string): Value
proc str*(v: Value): string {.inline.}

converter to_value*(v: char): Value {.inline.}
converter to_value*(v: Rune): Value {.inline.}

proc get_symbol*(i: int64): string {.inline.}

proc new_namespace*(): Namespace {.gcsafe.}
proc new_namespace*(name: string): Namespace {.gcsafe.}
proc new_namespace*(parent: Namespace): Namespace {.gcsafe.}
proc `[]=`*(self: var Namespace, key: string, val: Value) {.inline.}

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

proc new_id*(): Id =
  cast[Id](rand(BIGGEST_INT))

proc `=destroy`*(self: Value) =
  let v1 = cast[uint64](self)
  case cast[int64](v1.shr(48)):
    of GENE_PREFIX:
      let x = cast[ptr Gene](bitand(v1, AND_MASK))
      if x.ref_count == 1:
        dealloc(x)
      else:
        x.ref_count.dec()
    of REF_PREFIX:
      let x = cast[ptr Reference](bitand(v1, AND_MASK))
      if x.ref_count == 1:
        dealloc(x)
      else:
        x.ref_count.dec()
    of LONG_STR_PREFIX:
      let x = cast[ptr String](bitand(v1, AND_MASK))
      if x.ref_count == 1:
        dealloc(x)
      else:
        x.ref_count.dec()
    else:
      discard

proc `=copy`*(a: var Value, b: Value) =
  `=destroy`(a)
  let v1 = cast[uint64](b)
  case cast[int64](v1.shr(48)):
    of GENE_PREFIX:
      let x = cast[ptr Gene](bitand(v1, AND_MASK))
      x.ref_count.inc()
      a = cast[Value](cast[uint64](b))
    of REF_PREFIX:
      let x = cast[ptr Reference](bitand(v1, AND_MASK))
      x.ref_count.inc()
      a = cast[Value](cast[uint64](b))
    of LONG_STR_PREFIX:
      let x = cast[ptr String](bitand(v1, AND_MASK))
      a = new_str_value(x.str)
    else:
      a = cast[Value](cast[uint64](b))

#################### Reference ###################

proc `==`*(a, b: ptr Reference): bool =
  if a.is_nil:
    return b.is_nil

  if b.is_nil:
    return false

  if a.kind != b.kind:
    return false

  case a.kind:
    of VkArray:
      return a.arr == b.arr
    of VkSet:
      return a.set == b.set
    of VkMap:
      return a.map == b.map
    of VkComplexSymbol:
      return a.csymbol == b.csymbol
    else:
      todo()

proc `$`*(self: ptr Reference): string =
  $self.kind

proc new_ref*(kind: ValueKind): ptr Reference =
  result = cast[ptr Reference](alloc0(sizeof(Reference)))
  {.cast(uncheckedAssign).}:
    result.kind = kind

proc to_ref*(v: Value): ptr Reference =
  cast[ptr Reference](bitand(AND_MASK, v.uint64))

proc to_ref_value*(v: ptr Reference): Value {.inline.} =
  v.ref_count.inc()
  cast[Value](bitor(REF_MASK, cast[uint64](v)))

#################### Value ######################

proc `==`*(a, b: Value): bool {.no_side_effect.} =
  if cast[uint64](a) == cast[uint64](b):
    return true

  let v1 = cast[uint64](a)
  let v2 = cast[uint64](b)
  case cast[int64](v1.shr(48)):
    of REF_PREFIX:
      if cast[int64](v2.shr(48)) == REF_PREFIX:
        return a.to_ref() == b.to_ref()
    else:
      discard

  # Default to false

proc kind*(v: Value): ValueKind {.inline.} =
  {.cast(gcsafe).}:
    let v1 = cast[uint64](v)
    case cast[int64](v1.shr(48)):
      of NIL_PREFIX:
        return VkNil
      of BOOL_PREFIX:
        return VkBool
      of POINTER_PREFIX:
        return VkPointer
      of REF_PREFIX:
        return v.to_ref().kind
      of GENE_PREFIX:
        return VkGene
      # of CHAR_PREFIX:
      #   return VkChar
      of SHORT_STR_PREFIX, LONG_STR_PREFIX:
        return VkString
      of SYMBOL_PREFIX:
        return VkSymbol
      of OTHER_PREFIX:
        case cast[int64](v1.shl(16).shr(56)):
          of 0x00:
            return VkVoid
          of 0x01:
            return VkPlaceholder
          of 0x02, 0x03, 0x04, 0x05:
            return VkChar
          else:
            todo()
        # let other_info = cast[Value](bitand(v1, OTHER_MASK))
        # case other_info:
        #   of VOID:
        #     return VkVoid
        #   of PLACEHOLDER:
        #     return VkPlaceholder
        #   else:
        #     todo()
      else:
        if bitand(v1, I64_MASK) == 0:
          return VkInt
        else:
          return VkFloat

proc `$`*(self: Value): string =
  case self.kind:
    of VkNil:
      result = "nil"
    of VkBool:
      result = $(self == TRUE)
    of VkInt:
      result = $(cast[int64](self))
    of VkFloat:
      result = $(cast[float64](self))
    of VkString:
      {.cast(gcsafe).}:
        result = "\"" & $self.str & "\""
    of VkSymbol:
      {.cast(gcsafe).}:
        result = $self.str
    else:
      result = $self.kind

proc is_nil*(v: Value): bool {.inline.} =
  v == NIL

proc to_float*(v: Value): float64 {.inline.} =
  if cast[uint64](v) == F64_ZERO:
    return 0.0
  else:
    return cast[float64](v)

converter to_value*(v: float64): Value {.inline.} =
  if v == 0.0:
    return cast[Value](F64_ZERO)
  else:
    return cast[Value](v)

converter to_bool*(v: Value): bool {.inline.} =
  not (v == FALSE or v == NIL)

converter to_value*(v: bool): Value {.inline.} =
  if v:
    return TRUE
  else:
    return FALSE

proc to_pointer*(v: Value): pointer {.inline.} =
  cast[pointer](bitand(cast[int64](v), 0x0000FFFFFFFFFFFF))

converter to_value*(v: pointer): Value {.inline.} =
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
      let r = self.to_ref()
      case r.kind:
        of VkArray:
          if i >= r.arr.len:
            return NIL
          else:
            return r.arr[i]
        of VkString:
          var j = 0
          for r in r.str.runes:
            if i == j:
              return r
            j.inc()
        else:
          todo($r.kind)
    of GENE_PREFIX:
      todo("VkGene")
    of SHORT_STR_PREFIX, LONG_STR_PREFIX:
      var j = 0
      # TODO: optimize
      for r in self.str().runes:
        if i == j:
          return r
        j.inc()
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
      let r = self.to_ref()
      case r.kind:
        of VkArray:
          return r.arr.len
        else:
          todo($r.kind)
    of GENE_PREFIX:
      todo("VkGene")
    of SHORT_STR_PREFIX:
      return self.str().to_runes().len
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

proc new_str*(s: string): ptr String =
  result = cast[ptr String](alloc0(sizeof(String)))
  result.ref_count = 1
  result.str = s

proc new_str_value*(s: string): Value =
  cast[Value](bitor(LONG_STR_MASK, cast[uint64](new_str(s))))

converter to_value*(v: char): Value {.inline.} =
  {.cast(gcsafe).}:
    cast[Value](bitor(CHAR_MASK, v.ord.uint64))

proc str*(v: Value): string {.inline.} =
  {.cast(gcsafe).}:
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
        var x = cast[ptr String](bitand(cast[uint64](v1), AND_MASK))
        result = x.str

      of SYMBOL_PREFIX:
        var x = cast[int64](bitand(cast[uint64](v1), AND_MASK))
        result = get_symbol(x)

      else:
        not_allowed(fmt"${v} is not a string.")

converter to_value*(v: string): Value {.inline.} =
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
      let s = cast[ptr String](alloc0(sizeof(String)))
      s.ref_count = 1
      s.str = v
      result = cast[Value](bitor(LONG_STR_MASK, cast[uint64](s)))

converter to_value*(v: Rune): Value {.inline.} =
  let rune_value = v.ord.uint64
  if rune_value > 0xFF_FFFF:
    return cast[Value](bitor(CHAR4_MASK, rune_value))
  elif rune_value > 0xFFFF:
    return cast[Value](bitor(CHAR3_MASK, rune_value))
  elif rune_value > 0xFF:
    return cast[Value](bitor(CHAR2_MASK, rune_value))
  else:
    return cast[Value](bitor(CHAR_MASK, rune_value))

#################### Symbol #####################

var SYMBOLS*: ManagedSymbols

proc get_symbol*(i: int64): string {.inline.} =
  SYMBOLS.store[i]

proc to_symbol_value*(s: string): Value {.inline.} =
  {.cast(gcsafe).}:
    if SYMBOLS.map.has_key(s):
      let i = SYMBOLS.map[s].uint64
      result = cast[Value](bitor(EMPTY_SYMBOL, i))
    else:
      result = cast[Value](bitor(EMPTY_SYMBOL, SYMBOLS.store.len.uint64))
      SYMBOLS.map[s] = SYMBOLS.store.len
      SYMBOLS.store.add(s)

#################### ComplexSymbol ###############

proc to_complex_symbol*(parts: seq[string]): Value {.inline.} =
  let r = new_ref(VkComplexSymbol)
  r.csymbol = parts
  result = r.to_ref_value()

#################### Array #######################

proc new_array_value*(v: varargs[Value]): Value =
  let r = new_ref(VkArray)
  r.arr = @v
  result = r.to_ref_value()

#################### Stream ######################

proc new_stream_value*(v: varargs[Value]): Value =
  let r = new_ref(VkStream)
  r.stream = @v
  result = r.to_ref_value()

#################### Set #########################

proc new_set_value*(): Value =
  let r = new_ref(VkSet)
  result = r.to_ref_value()

#################### Map #########################

proc new_map_value*(): Value =
  let r = new_ref(VkMap)
  result = r.to_ref_value()

proc new_map_value*(map: Table[string, Value]): Value =
  let r = new_ref(VkMap)
  r.map = map
  result = r.to_ref_value()

#################### Gene ########################

proc to_gene_value*(v: ptr Gene): Value {.inline.} =
  v.ref_count.inc()
  cast[Value](bitor(cast[uint64](v), GENE_MASK))

proc gene*(v: Value): ptr Gene {.inline.} =
  cast[ptr Gene](bitand(cast[int64](v), 0x0000FFFFFFFFFFFF))

proc new_gene*(): ptr Gene =
  result = cast[ptr Gene](alloc0(sizeof(Gene)))
  result.ref_count = 1
  result.type = NIL
  result.props = Table[string, Value]()
  result.children = @[]

proc new_gene*(`type`: Value): ptr Gene =
  result = cast[ptr Gene](alloc0(sizeof(Gene)))
  result.ref_count = 1
  result.type = `type`
  result.props = Table[string, Value]()
  result.children = @[]

proc new_gene_value*(): Value {.inline.} =
  new_gene().to_gene_value()

proc new_gene_value*(`type`: Value): Value {.inline.} =
  new_gene(`type`).to_gene_value()

#################### Application #################

proc new_app*(): Application =
  result = Application()
  var global = new_namespace("global")
  result.ns = global

#################### Namespace ###################

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[string, Value](),
  )

proc new_namespace*(parent: Namespace): Namespace =
  return Namespace(
    parent: parent,
    name: "<root>",
    members: Table[string, Value](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[string, Value](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[string, Value](),
  )

proc root*(self: Namespace): Namespace =
  if self.name == "<root>":
    return self
  else:
    return self.parent.root

proc get_module*(self: Namespace): Module =
  if self.module == nil:
    if self.parent != nil:
      return self.parent.get_module()
    else:
      return
  else:
    return self.module

proc package*(self: Namespace): Package =
  self.get_module().pkg

proc proxy*(self: Namespace, name: string, target: Value) =
  self.proxies[name] = target

proc has_key*(self: Namespace, key: string): bool {.inline.} =
  if self.proxies.has_key(key):
    return self.proxies[key].to_ref().ns.has_key(key)
  else:
    return self.members.has_key(key) or (self.parent != nil and self.parent.has_key(key))

proc `[]`*(self: Namespace, key: string): Value {.inline.} =
  if self.proxies.has_key(key):
    return self.proxies[key].to_ref().ns[key]
  elif self.members.has_key(key):
    return self.members[key]
  elif not self.stop_inheritance and self.parent != nil:
    return self.parent[key]
  else:
    raise new_exception(NotDefinedException, key & " is not defined")

proc locate*(self: Namespace, key: string): (Value, Namespace) {.inline.} =
  if self.members.has_key(key):
    result = (self.members[key], self)
  elif not self.stop_inheritance and self.parent != nil:
    result = self.parent.locate(key)
  else:
    not_allowed()

proc `[]=`*(self: var Namespace, key: string, val: Value) {.inline.} =
  self.members[key] = val

proc get_members*(self: Namespace): Value =
  todo()
  # result = new_gene_map()
  # for k, v in self.members:
  #   result.map[k] = v

proc member_names*(self: Namespace): Value =
  todo()
  # result = new_gene_vec()
  # for k, _ in self.members:
  #   result.vec.add(k)

# proc on_member_missing*(frame: Frame, self: Value, args: Value): Value =
proc on_member_missing*(vm_data: VirtualMachineData, args: Value): Value =
  todo()
  # let self = args.gene_type
  # case self.kind
  # of VkNamespace:
  #   self.ns.on_member_missing.add(args.gene_children[0])
  # of VkClass:
  #   self.class.ns.on_member_missing.add(args.gene_children[0])
  # of VkMixin:
  #   self.mixin.ns.on_member_missing.add(args.gene_children[0])
  # else:
  #   todo("member_missing " & $self.kind)

#################### Scope #######################

proc new_scope*(): Scope = Scope(
  members: @[],
  mappings: Table[string, int](),
  mapping_history: @[],
)

proc max*(self: Scope): NameIndexScope {.inline.} =
  return self.members.len.NameIndexScope

proc set_parent*(self: var Scope, parent: Scope, max: NameIndexScope) {.inline.} =
  self.parent = parent
  self.parent_index_max = max

proc reset*(self: var Scope) {.inline.} =
  self.parent = nil
  self.members.setLen(0)

proc has_key(self: Scope, key: string, max: int): bool {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    if found < max:
      return true
    if found > 255:
      var index = found and 0xFF
      if index < max:
        return true
      var history_index = found.shr(8) - 1
      var history = self.mapping_history[history_index]
      # If first >= max, all others will be >= max
      if history[0].int < max:
        return true

  if self.parent != nil:
    return self.parent.has_key(key, self.parent_index_max.int)

proc has_key*(self: Scope, key: string): bool {.inline.} =
  if self.mappings.has_key(key):
    return true
  elif self.parent != nil:
    return self.parent.has_key(key, self.parent_index_max.int)

proc def_member*(self: var Scope, key: string, val: Value) {.inline.} =
  var index = self.members.len
  self.members.add(val)
  if self.mappings.has_key_or_put(key, index):
    var cur = self.mappings[key]
    if cur > 255:
      todo()
      # var history_index = cur.shr(8) - 1
      # self.mapping_history[history_index].add(cur and 0xFF)
      # self.mappings[key] = (cur and 0b1111111100000000) + index
    else:
      var history_index = self.mapping_history.len
      self.mapping_history.add(@[NameIndexScope(cur)])
      self.mappings[key] = (history_index + 1).shl(8) + index

proc `[]`(self: Scope, key: string, max: int): Value {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    if found > 255:
      var cur = found and 0xFF
      if cur < max:
        return self.members[cur]
      else:
        var history_index = found.shr(8) - 1
        var history = self.mapping_history[history_index]
        var i = history.len - 1
        while i >= 0:
          var index: int = history[i].int
          if index < max:
            return self.members[index]
          i -= 1
    elif found < max:
      return self.members[found.int]

  if self.parent != nil:
    return self.parent[key, self.parent_index_max.int]

proc `[]`*(self: Scope, key: string): Value {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    if found > 255:
      found = found and 0xFF
    return self.members[found]
  elif self.parent != nil:
    return self.parent[key, self.parent_index_max.int]

proc `[]=`(self: var Scope, key: string, val: Value, max: int) {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    if found > 255:
      var index = found and 0xFF
      if index < max:
        self.members[index] = val
      else:
        var history_index = found.shr(8) - 1
        var history = self.mapping_history[history_index]
        var i = history.len - 1
        while i >= 0:
          var index: int = history[history_index].int
          if index < max:
            self.members[index] = val
          i -= 1
    elif found < max:
      self.members[found.int] = val

  elif self.parent != nil:
    self.parent.`[]=`(key, val, self.parent_index_max.int)
  else:
    not_allowed()

proc `[]=`*(self: var Scope, key: string, val: Value) {.inline.} =
  if self.mappings.has_key(key):
    self.members[self.mappings[key].int] = val
  elif self.parent != nil:
    self.parent.`[]=`(key, val, self.parent_index_max.int)
  else:
    not_allowed()

#################### Pattern Matching ############

proc new_match_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchExpression,
  )

proc new_arg_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchArguments,
  )

proc new_matcher*(root: RootMatcher, kind: MatcherKind): Matcher =
  result = Matcher(
    root: root,
    kind: kind,
  )

proc required*(self: Matcher): bool =
  # return self.default_value_expr == nil and not self.is_splat
  return not self.is_splat

proc hint*(self: RootMatcher): MatchingHint =
  if self.children.len == 0:
    result.mode = MhNone
  else:
    result.mode = MhSimpleData
    for item in self.children:
      if item.kind != MatchData or not item.required:
        result.mode = MhDefault
        return

# proc new_matched_field*(name: string, value: Value): MatchedField =
#   result = MatchedField(
#     name: name,
#     value: value,
#   )

proc props*(self: seq[Matcher]): HashSet[string] =
  for m in self:
    if m.kind == MatchProp and not m.is_splat:
      result.incl(m.name)

proc prop_splat*(self: seq[Matcher]): string =
  for m in self:
    if m.kind == MatchProp and m.is_splat:
      return m.name

#################### Function ####################

proc new_fn*(name: string, matcher: RootMatcher, body: seq[Value]): Function =
  return Function(
    name: name,
    matcher: matcher,
    matching_hint: matcher.hint,
    body: body,
  )

#################### Macro #######################

proc new_macro*(name: string, matcher: RootMatcher, body: seq[Value]): Macro =
  return Macro(
    name: name,
    matcher: matcher,
    matching_hint: matcher.hint,
    body: body,
  )

#################### Block #######################

proc new_block*(matcher: RootMatcher,  body: seq[Value]): Block =
  return Block(
    matcher: matcher,
    matching_hint: matcher.hint,
    body: body,
  )

#################### Class #######################

proc new_class*(name: string, parent: Class): Class =
  return Class(
    name: name,
    ns: new_namespace(nil, name),
    parent: parent,
  )

proc new_class*(name: string): Class =
  var parent: Class
  # if VM.object_class != nil:
  #   parent = VM.object_class.class
  new_class(name, parent)

proc get_constructor*(self: Class): Value =
  if self.constructor.is_nil:
    if not self.parent.is_nil:
      return self.parent.get_constructor()
  else:
    return self.constructor

proc has_method*(self: Class, name: string): bool =
  if self.methods.has_key(name):
    return true
  elif self.parent != nil:
    return self.parent.has_method(name)

proc get_method*(self: Class, name: string): Method =
  if self.methods.has_key(name):
    return self.methods[name]
  elif self.parent != nil:
    return self.parent.get_method(name)
  # else:
  #   not_allowed("No method available: " & name.to_s)

proc get_super_method*(self: Class, name: string): Method =
  if self.parent != nil:
    return self.parent.get_method(name)
  else:
    not_allowed("No super method available: " & name)

proc get_class*(val: Value): Class =
  case val.kind:
    # of VkApplication:
    #   return App.app.application_class.class
    # of VkPackage:
    #   return App.app.package_class.class
    # of VkInstance:
    #   return val.instance_class
    # of VkCast:
    #   return val.cast_class
    # of VkClass:
    #   return App.app.class_class.class
    # of VkMixin:
    #   return App.app.mixin_class.class
    # of VkNamespace:
    #   return App.app.namespace_class.class
    # of VkFuture:
    #   return App.app.future_class.class
    # of VkThread:
    #   return App.app.thread_class.class
    # of VkThreadMessage:
    #   return App.app.thread_message_class.class
    # of VkNativeFile:
    #   return App.app.file_class.class
    # of VkException:
    #   var ex = val.exception
    #   if ex is ref Exception:
    #     var ex = cast[ref Exception](ex)
    #     if ex.instance != nil:
    #       return ex.instance.instance_class
    #     else:
    #       return App.app.exception_class.class
    #   else:
    #     return App.app.exception_class.class
    # of VkNil:
    #   return App.app.nil_class.class
    # of VkBool:
    #   return App.app.bool_class.class
    # of VkInt:
    #   return App.app.int_class.class
    # of VkChar:
    #   return App.app.char_class.class
    # of VkString:
    #   return App.app.string_class.class
    # of VkSymbol:
    #   return App.app.symbol_class.class
    # of VkComplexSymbol:
    #   return App.app.complex_symbol_class.class
    # of VkVector:
    #   return App.app.array_class.class
    # of VkMap:
    #   return App.app.map_class.class
    # of VkSet:
    #   return App.app.set_class.class
    # of VkGene:
    #   return App.app.gene_class.class
    # of VkRegex:
    #   return App.app.regex_class.class
    # of VkRange:
    #   return App.app.range_class.class
    # of VkDate:
    #   return App.app.date_class.class
    # of VkDateTime:
    #   return App.app.datetime_class.class
    # of VkTime:
    #   return App.app.time_class.class
    # of VkFunction:
    #   return App.app.function_class.class
    # of VkTimezone:
    #   return App.app.timezone_class.class
    # of VkAny:
    #   if val.any_class == nil:
    #     return App.app.object_class.class
    #   else:
    #     return val.any_class
    # of VkCustom:
    #   if val.custom_class == nil:
    #     return App.app.object_class.class
    #   else:
    #     return val.custom_class
    else:
      todo("get_class " & $val.kind)

proc is_a*(self: Value, class: Class): bool =
  var my_class = self.get_class
  while true:
    if my_class == class:
      return true
    if my_class.parent == nil:
      return false
    else:
      my_class = my_class.parent

proc def_native_method*(self: Class, name: string, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.methods[name] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
  )

proc def_native_method*(self: Class, name: string, f: NativeFn2) =
  let r = new_ref(VkNativeFn2)
  r.native_fn2 = f
  self.methods[name] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
  )

proc def_native_macro_method*(self: Class, name: string, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.methods[name] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
    is_macro: true,
  )

proc def_native_constructor*(self: Class, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.constructor = r.to_ref_value()

proc def_native_constructor*(self: Class, f: NativeFn2) =
  let r = new_ref(VkNativeFn2)
  r.native_fn2 = f
  self.constructor = r.to_ref_value()

#################### Method ######################

proc new_method*(class: Class, name: string, fn: Function): Method =
  let r = new_ref(VkFunction)
  r.fn = fn
  return Method(
    class: class,
    name: name,
    callable: r.to_ref_value(),
  )

proc clone*(self: Method): Method =
  return Method(
    class: self.class,
    name: self.name,
    callable: self.callable,
  )

#################### Helpers #####################

proc init_values*() =
  SYMBOLS = ManagedSymbols()

init_values()

include ./utils
