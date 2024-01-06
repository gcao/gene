import math, hashes, tables, sets, re, bitops, unicode, strutils, strformat
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

    # VkInstruction
    VkScopeTracker
    VkScope

  Key* = distinct int64
  Value* = distinct int64

  # Keep the size of Value to 4*8 = 32 bytes
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
        map*: Table[Key, Value]
      of VkStream:
        stream*: seq[Value]
        stream_index*: int64
        # stream_ended*: bool
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
        # instance_props*: Table[Key, Value]
      of VkNativeFn:
        native_fn*: NativeFn
      of VkNativeFn2:
        native_fn2*: NativeFn2
      # of VkInstruction:
      #   instruction*: Instruction
      of VkScopeTracker:
        scope_tracker*: ScopeTracker
      of VkScope:
        scope*: Scope
      else:
        discard

  Gene* = object
    ref_count*: int32
    `type`*: Value
    props*: Table[Key, Value]
    children*: seq[Value]

  String* = object
    ref_count*: int32
    str*: string

  Document* = ref object
    `type`: Value
    props*: Table[Key, Value]
    children*: seq[Value]
    # references*: References # Uncomment this when it's needed.

  ScopeObj* = object
    ref_count*: int32
    # tracker*: ScopeTracker
    parent*: Scope
    parent_index_max*: int16   # To remove
    members*:  seq[Value]
    # Below fields are replacement of seq[Value] to achieve better performance
    #   Have to benchmark to see if it's worth it.
    # vars*: ptr UncheckedArray[Value]
    # vars_in_use*: int16
    # vars_max*: int16

  Scope* = ptr ScopeObj

  ## This is the root of a running application
  Application* = ref object
    name*: string         # Default to base name of command, can be changed, e.g. ($set_app_name "...")
    pkg*: Package         # Entry package for the application
    ns*: Namespace
    cmd*: string
    args*: seq[string]
    main_module*: Module
    # dep_root*: DependencyRoot
    props*: Table[Key, Value]  # Additional properties

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
    # dependencies*: Table[Key, Dependency]
    homepage*: string
    src_path*: string     # Default to "src"
    test_path*: string    # Default to "tests"
    asset_path*: string   # Default to "assets"
    build_path*: string   # Default to "build"
    load_paths*: seq[string]
    init_modules*: seq[string]    # Modules that should be loaded when the package is used the first time
    props*: Table[Key, Value]  # Additional properties
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
    props*: Table[Key, Value]  # Additional properties

  Namespace* = ref object
    module*: Module
    parent*: Namespace
    stop_inheritance*: bool  # When set to true, stop looking up for members from parent namespaces
    name*: string
    members*: Table[Key, Value]
    on_member_missing*: seq[Value]

  Class* = ref object
    parent*: Class
    name*: string
    constructor*: Value
    methods*: Table[Key, Method]
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
    # class*: Class       # Note that class may be different from method.class
    `method`*: Method

  Function* = ref object
    async*: bool
    name*: string
    ns*: Namespace
    parent_scope_tracker*: ScopeTracker
    parent_scope*: Scope
    parent_scope_max*: int16
    matcher*: RootMatcher
    # matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: CompilationUnit
    # ret*: Expr

  Macro* = ref object
    ns*: Namespace
    name*: string
    parent_scope*: Scope
    parent_scope_max*: int16
    matcher*: RootMatcher
    # matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: CompilationUnit

  Block* = ref object
    # frame*: Frame
    ns*: Namespace
    parent_scope*: Scope
    parent_scope_max*: int16
    matcher*: RootMatcher
    # matching_hint*: MatchingHint
    body*: seq[Value]
    # body_compiled*: Expr
    body_compiled*: CompilationUnit

  MatchingMode* {.size: sizeof(int16) .} = enum
    MatchArguments # (fn f [a b] ...)
    MatchExpression # (match [a b] input): a and b will be defined
    MatchAssignment # ([a b] = input): a and b must be defined first

  # Match the whole input or the first child (if running in ArgumentMode)
  # Can have name, match nothing, or have group of children
  RootMatcher* = ref object
    mode*: MatchingMode
    hint_mode*: MatchingHintMode
    children*: seq[Matcher]

  MatchingHintMode* {.size: sizeof(int16) .} = enum
    MhDefault
    MhNone
    MhSimpleData  # E.g. [a b]

  # MatchingHint* = object
  #   mode*: MatchingHintMode

  MatcherKind* = enum
    MatchType
    MatchProp
    MatchData
    MatchLiteral

  Matcher* = ref object
    root*: RootMatcher
    kind*: MatcherKind
    next*: Matcher  # if kind is MatchData and is_splat is true, we may need to check next matcher
    name_key*: Key
    is_prop*: bool
    literal*: Value # if kind is MatchLiteral, this is required
    # match_name*: bool # Match symbol to name - useful for (myif true then ... else ...)
    default_value*: Value
    # default_value_expr*: Expr
    is_splat*: bool
    min_left*: int # Minimum number of args following this
    children*: seq[Matcher]
    # required*: bool # computed property: true if splat is false and default value is not given

  # MatchedFieldKind* = enum
  #   MfMissing
  #   MfSuccess
  #   MfTypeMismatch # E.g. map is passed but array or gene is expected

  # MatchResult* = object
  #   fields*: seq[MatchedFieldKind]

  Id* = distinct int64
  Label* = int16

  Compiler* = ref object
    output*: CompilationUnit
    quote_level*: int
    scope_trackers*: seq[ScopeTracker]

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
    IkVarResolve
    IkVarResolveInherited
    IkVarAssign
    IkVarAssignInherited

    IkAssign      # TODO: rename to IkSetMemberOnCurrentNS

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
    IkSubValue
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

  Instruction* = object
    kind*: InstructionKind
    label*: Label
    arg1*: int32
    arg0*: Value

  VarIndex* = object
    local_index*: int32
    parent_index*: int32

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
    scope_tracker*: ScopeTracker

  # Used by the compiler to keep track of scopes and variables
  #
  # Scopes should be created on demand (when the first variable is defined)
  # Scopes should be destroyed when they are no longer needed
  # Scopes should stay alive when they are referenced by child scopes
  # Function/macro/block/if/loop/switch/do/eval inherit parent scope
  # Class/namespace do not inherit parent scope
  ScopeTracker* = ref object
    parent*: ScopeTracker   # If parent is nil, the scope is the top level scope.
    parent_index_max*: int16
    next_index*: int16      # If next_index is 0, the scope is empty
    mappings*: Table[Key, int16]

  Address* = object
    id*: Id
    pc*: int

  VirtualMachineState* = enum
    VmWaiting   # waiting for task
    VmRunning
    VmPaused

  # Virtual machine and its data can be separated however it doesn't
  # bring much benefit. So we keep them together.
  VirtualMachine* = ref object
    state*: VirtualMachineState
    is_main*: bool
    cur_block*: CompilationUnit
    pc*: int
    frame*: Frame
    code_mgr*: CodeManager
    trace*: bool

  VmCallback* = proc() {.gcsafe.}

  FrameObj = object
    ref_count*: int32
    caller_frame*: Frame
    caller_address*: Address
    ns*: Namespace
    scope*: Scope
    self*: Value
    args*: Value
    # match_result*: MatchResult
    stack*: array[24, Value]
    stack_index*: uint8

  Frame* = ptr FrameObj

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

  NativeFn* = proc(vm_data: VirtualMachine, args: Value): Value {.gcsafe, nimcall.}
  NativeFn2* = proc(vm_data: VirtualMachine, args: Value): Value {.gcsafe.}

const INST_SIZE* = sizeof(Instruction)

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
# Used when a key does not exist in a map
const NOT_FOUND* = cast[Value](0x7FFE_0200_0000_0000u64)

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

const SYMBOL_PREFIX  = 0x7FF9
const EMPTY_SYMBOL = 0x7FF9_0000_0000_0000u64

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
proc `$`*(self: ptr Gene): string

proc `ref`*(v: Value): ptr Reference {.inline.}
proc gene*(v: Value): ptr Gene {.inline.}

proc new_str*(s: string): ptr String
proc new_str_value*(s: string): Value
proc str*(v: Value): string {.inline.}

converter to_value*(v: char): Value {.inline.}
converter to_value*(v: Rune): Value {.inline.}

proc get_symbol*(i: int): string {.inline.}
proc to_key*(s: string): Key {.inline.}

proc update*(self: var Scope, scope: Scope) {.inline.}

proc new_namespace*(): Namespace {.gcsafe.}
proc new_namespace*(name: string): Namespace {.gcsafe.}
proc new_namespace*(parent: Namespace): Namespace {.gcsafe.}
proc `[]=`*(self: Namespace, key: Key, val: Value) {.inline.}

#################### Common ######################

template `==`*(a, b: Key): bool =
  cast[int64](a) == cast[int64](b)

template hash*(v: Key): Hash =
  cast[Hash](v)

template `==`*(a, b: Id): bool =
  cast[int64](a) == cast[int64](b)

template hash*(v: Id): Hash =
  cast[Hash](v)

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

converter to_value*(k: Key): Value {.inline.} =
  cast[Value](k)

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

proc `ref`*(v: Value): ptr Reference {.inline.} =
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
        return a.ref == b.ref
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
        return v.ref.kind
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

proc is_literal*(self: Value): bool =
  {.cast(gcsafe).}:
    let v1 = cast[uint64](self)
    case cast[int64](v1.shr(48)):
      of NIL_PREFIX, BOOL_PREFIX, SHORT_STR_PREFIX, LONG_STR_PREFIX:
        result = true
      of OTHER_PREFIX:
        result = true
      of SYMBOL_PREFIX:
        result = false
      of POINTER_PREFIX:
        result = false
      of REF_PREFIX:
        let r = self.ref
        case r.kind:
          of VkArray:
            for v in r.arr:
              if not is_literal(v):
                return false
            return true
          of VkMap:
            for v in r.map.values:
              if not is_literal(v):
                return false
            return true
          else:
            result = false
      of GENE_PREFIX:
        result = false
      else:
        result = true

proc `$`*(self: Value): string =
  {.cast(gcsafe).}:
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
        result = "\"" & $self.str & "\""
      of VkSymbol:
        result = $self.str
      of VkComplexSymbol:
        result = self.ref.csymbol.join("/")
      of VkGene:
        result = $self.gene
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
      let r = self.ref
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
      let r = self.ref
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
        let x = cast[int64](bitand(cast[uint64](v1), AND_MASK))
        # echo x.to_binstr
        {.push checks: off}
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
        {.pop.}

      of LONG_STR_PREFIX:
        let x = cast[ptr String](bitand(cast[uint64](v1), AND_MASK))
        result = x.str

      of SYMBOL_PREFIX:
        let x = cast[int64](bitand(cast[uint64](v1), AND_MASK))
        result = get_symbol(x)

      else:
        not_allowed(fmt"{v} is not a string.")

converter to_value*(v: string): Value {.inline.} =
  {.push checks: off}
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
  {.pop.}

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

proc get_symbol*(i: int): string {.inline.} =
  SYMBOLS.store[i]

proc to_symbol_value*(s: string): Value {.inline.} =
  {.cast(gcsafe).}:
    let found = SYMBOLS.map.get_or_default(s, -1)
    if found != -1:
      let i = found.uint64
      result = cast[Value](bitor(EMPTY_SYMBOL, i))
    else:
      result = cast[Value](bitor(EMPTY_SYMBOL, SYMBOLS.store.len.uint64))
      SYMBOLS.map[s] = SYMBOLS.store.len
      SYMBOLS.store.add(s)

proc to_key*(s: string): Key {.inline.} =
  cast[Key](to_symbol_value(s))

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

proc new_map_value*(map: Table[Key, Value]): Value =
  let r = new_ref(VkMap)
  r.map = map
  result = r.to_ref_value()

#################### Gene ########################

proc to_gene_value*(v: ptr Gene): Value {.inline.} =
  v.ref_count.inc()
  cast[Value](bitor(cast[uint64](v), GENE_MASK))

proc gene*(v: Value): ptr Gene {.inline.} =
  cast[ptr Gene](bitand(cast[int64](v), 0x0000FFFFFFFFFFFF))

proc `$`*(self: ptr Gene): string =
  result = "(" & $self.type
  for k, v in self.props:
    result &= " ^" & get_symbol(k.int64) & " " & $v
  for child in self.children:
    result &= " " & $child
  result &= ")"

proc new_gene*(): ptr Gene =
  result = cast[ptr Gene](alloc0(sizeof(Gene)))
  result.ref_count = 1
  result.type = NIL
  result.props = Table[Key, Value]()
  result.children = @[]

proc new_gene*(`type`: Value): ptr Gene =
  result = cast[ptr Gene](alloc0(sizeof(Gene)))
  result.ref_count = 1
  result.type = `type`
  result.props = Table[Key, Value]()
  result.children = @[]

proc new_gene_value*(): Value {.inline.} =
  new_gene().to_gene_value()

proc new_gene_value*(`type`: Value): Value {.inline.} =
  new_gene(`type`).to_gene_value()

# proc args_are_literal(self: ptr Gene): bool =
#   for k, v in self.props:
#     if not v.is_literal():
#       return false
#   for v in self.children:
#     if not v.is_literal():
#       return false
#   true

#################### Application #################

proc app*(self: Value): Application {.inline.} =
  self.ref.app

proc new_app*(): Application =
  result = Application()
  let global = new_namespace("global")
  result.ns = global

#################### Namespace ###################

proc ns*(self: Value): Namespace {.inline.} =
  self.ref.ns

proc to_value*(self: Namespace): Value {.inline.} =
  let r = new_ref(VkNamespace)
  r.ns = self
  result = r.to_ref_value()

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[Key, Value](),
  )

proc new_namespace*(parent: Namespace): Namespace =
  return Namespace(
    parent: parent,
    name: "<root>",
    members: Table[Key, Value](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[Key, Value](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[Key, Value](),
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

proc has_key*(self: Namespace, key: Key): bool {.inline.} =
  return self.members.has_key(key) or (self.parent != nil and self.parent.has_key(key))

proc `[]`*(self: Namespace, key: Key): Value {.inline.} =
  let found = self.members.get_or_default(key, NOT_FOUND)
  if found != NOT_FOUND:
    return found
  elif not self.stop_inheritance and self.parent != nil:
    return self.parent[key]
  else:
    return NOT_FOUND
    # raise new_exception(NotDefinedException, get_symbol(key.int64) & " is not defined")

proc locate*(self: Namespace, key: Key): (Value, Namespace) {.inline.} =
  let found = self.members.get_or_default(key, NOT_FOUND)
  if found != NOT_FOUND:
    result = (found, self)
  elif not self.stop_inheritance and self.parent != nil:
    result = self.parent.locate(key)
  else:
    not_allowed()

proc `[]=`*(self: Namespace, key: Key, val: Value) {.inline.} =
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
proc on_member_missing*(vm_data: VirtualMachine, args: Value): Value =
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

var SCOPES: seq[Scope] = @[]

proc free*(self: Scope) {.inline.} =
  self.ref_count.dec()
  if self.ref_count == 0:
    if self.parent != nil:
      self.parent.free()
    self.parent = nil
    self.parent_index_max = 0
    self.members.set_len(0)
    SCOPES.add(self)

proc update*(self: var Scope, scope: Scope) {.inline.} =
  if scope != nil:
    scope.ref_count.inc()
  if self != nil:
    self.free()
  self = scope

proc new_scope*(): Scope =
  if SCOPES.len > 0:
    result = SCOPES.pop()
  else:
    result = cast[Scope](alloc0(sizeof(ScopeObj)))
  result.ref_count = 1

proc max*(self: Scope): int16 {.inline.} =
  return self.members.len.int16

proc set_parent*(self: Scope, parent: Scope, max: int16) {.inline.} =
  parent.ref_count.inc()
  self.parent = parent
  self.parent_index_max = max

proc locate(self: ScopeTracker, key: Key, max: int): VarIndex {.inline.} =
  let found = self.mappings.get_or_default(key, -1)
  if found >= 0 and found < max:
    return VarIndex(parent_index: 0, local_index: found)
  elif self.parent != nil:
    result = self.parent.locate(key, self.parent_index_max.int)
    result.parent_index.inc()
  else:
    return VarIndex(parent_index: 0, local_index: -1)

proc locate*(self: ScopeTracker, key: Key): VarIndex =
  let found = self.mappings.get_or_default(key, -1)
  if found >= 0:
    return VarIndex(parent_index: 0, local_index: found)
  elif self.parent.is_nil():
    return VarIndex(parent_index: 0, local_index: -1)
  else:
    result = self.locate(key, self.parent_index_max.int)

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

proc check_hint*(self: RootMatcher) {.inline.} =
  if self.children.len == 0:
    self.hint_mode = MhNone
  else:
    self.hint_mode = MhSimpleData
    for item in self.children:
      if item.kind != MatchData or not item.required:
        self.hint_mode = MhDefault
        return

# proc hint*(self: RootMatcher): MatchingHint {.inline.} =
#   if self.children.len == 0:
#     result.mode = MhNone
#   else:
#     result.mode = MhSimpleData
#     for item in self.children:
#       if item.kind != MatchData or not item.required:
#         result.mode = MhDefault
#         return

# proc new_matched_field*(name: string, value: Value): MatchedField =
#   result = MatchedField(
#     name: name,
#     value: value,
#   )

proc props*(self: seq[Matcher]): HashSet[Key] =
  for m in self:
    if m.kind == MatchProp and not m.is_splat:
      result.incl(m.name_key)

proc prop_splat*(self: seq[Matcher]): Key =
  for m in self:
    if m.kind == MatchProp and m.is_splat:
      return m.name_key

proc parse*(self: RootMatcher, v: Value)

proc calc_next*(self: Matcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_next*(self: RootMatcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_min_left*(self: Matcher) =
  {.push checks: off}
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    let m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1
  {.pop.}

proc calc_min_left*(self: RootMatcher) =
  {.push checks: off}
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    let m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1
  {.pop.}

proc parse(self: RootMatcher, group: var seq[Matcher], v: Value) =
  {.push checks: off}
  case v.kind:
    of VkSymbol:
      if v.str[0] == '^':
        let m = new_matcher(self, MatchProp)
        if v.str.ends_with("..."):
          m.is_splat = true
          if v.str[1] == '^':
            m.name_key = v.str[2..^4].to_key()
            m.is_prop = true
          else:
            m.name_key = v.str[1..^4].to_key()
        else:
          if v.str[1] == '^':
            m.name_key = v.str[2..^1].to_key()
            m.is_prop = true
          else:
            m.name_key = v.str[1..^1].to_key()
        group.add(m)
      else:
        let m = new_matcher(self, MatchData)
        group.add(m)
        if v.str != "_":
          if v.str.ends_with("..."):
            m.is_splat = true
            if v.str[0] == '^':
              m.name_key = v.str[1..^4].to_key()
              m.is_prop = true
            else:
              m.name_key = v.str[0..^4].to_key()
          else:
            if v.str[0] == '^':
              m.name_key = v.str[1..^1].to_key()
              m.is_prop = true
            else:
              m.name_key = v.str.to_key()
    of VkComplexSymbol:
      todo($VkComplexSymbol)
      # if v.csymbol[0] == '^':
      #   todo("parse " & $v)
      # else:
      #   var m = new_matcher(self, MatchData)
      #   group.add(m)
      #   m.is_prop = true
      #   let name = v.csymbol[1]
      #   if name.ends_with("..."):
      #     m.is_splat = true
      #     m.name = name[0..^4]
      #   else:
      #     m.name = name
    of VkArray:
      var i = 0
      while i < v.ref.arr.len:
        let item = v.ref.arr[i]
        i += 1
        if item.kind == VkArray:
          let m = new_matcher(self, MatchData)
          group.add(m)
          self.parse(m.children, item)
        else:
          self.parse(group, item)
          if i < v.ref.arr.len and v.ref.arr[i] == "=".to_symbol_value():
            i += 1
            let last_matcher = group[^1]
            let value = v.ref.arr[i]
            i += 1
            last_matcher.default_value = value
    of VkQuote:
      todo($VkQuote)
      # var m = new_matcher(self, MatchLiteral)
      # m.literal = v.quote
      # m.name = "<literal>"
      # group.add(m)
    else:
      todo("parse " & $v.kind)
  {.pop.}

proc parse*(self: RootMatcher, v: Value) =
  if v == nil or v == to_symbol_value("_"):
    return
  self.parse(self.children, v)
  self.calc_min_left()
  self.calc_next()

proc new_arg_matcher*(value: Value): RootMatcher =
  result = new_arg_matcher()
  result.parse(value)
  result.check_hint()

#################### Function ####################

proc new_fn*(name: string, matcher: RootMatcher, body: seq[Value]): Function =
  return Function(
    name: name,
    matcher: matcher,
    # matching_hint: matcher.hint,
    body: body,
  )

proc to_function*(node: Value): Function {.gcsafe.} =
  var name: string
  let matcher = new_arg_matcher()
  var body_start: int
  if node.gene.type == "fnx".to_symbol_value():
    matcher.parse(node.gene.children[0])
    name = "<unnamed>"
    body_start = 1
  elif node.gene.type == "fnxx".to_symbol_value():
    name = "<unnamed>"
    body_start = 0
  else:
    let first = node.gene.children[0]
    case first.kind:
      of VkSymbol, VkString:
        name = first.str
      of VkComplexSymbol:
        name = first.ref.csymbol[^1]
      else:
        todo($first.kind)

    matcher.parse(node.gene.children[1])
    body_start = 2

  matcher.check_hint()
  var body: seq[Value] = @[]
  for i in body_start..<node.gene.children.len:
    body.add node.gene.children[i]

  # body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  result.async = node.gene.props.get_or_default("async".to_key(), false)

#################### Macro #######################

proc new_macro*(name: string, matcher: RootMatcher, body: seq[Value]): Macro =
  return Macro(
    name: name,
    matcher: matcher,
    # matching_hint: matcher.hint,
    body: body,
  )

proc to_macro*(node: Value): Macro =
  let first = node.gene.children[0]
  var name: string
  if first.kind == VkSymbol:
    name = first.str
  elif first.kind == VkComplexSymbol:
    name = first.ref.csymbol[^1]

  let matcher = new_arg_matcher()
  matcher.parse(node.gene.children[1])
  matcher.check_hint()

  var body: seq[Value] = @[]
  for i in 2..<node.gene.children.len:
    body.add node.gene.children[i]

  # body = wrap_with_try(body)
  result = new_macro(name, matcher, body)

#################### Block #######################

proc new_block*(matcher: RootMatcher,  body: seq[Value]): Block =
  return Block(
    matcher: matcher,
    # matching_hint: matcher.hint,
    body: body,
  )

#################### Class #######################

proc new_class*(name: string, parent: Class): Class =
  return Class(
    name: name,
    ns: new_namespace(nil, name),
    parent: parent,
    constructor: NIL,
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

proc has_method*(self: Class, name: Key): bool =
  if self.methods.has_key(name):
    return true
  elif self.parent != nil:
    return self.parent.has_method(name)

proc has_method*(self: Class, name: string): bool {.inline.} =
  self.has_method(name.to_key)

proc get_method*(self: Class, name: Key): Method =
  let found = self.methods.get_or_default(name, nil)
  if not found.is_nil:
    return found
  elif self.parent != nil:
    return self.parent.get_method(name)
  # else:
  #   not_allowed("No method available: " & name.to_s)

proc get_method*(self: Class, name: string): Method {.inline.} =
  self.get_method(name.to_key)

proc get_super_method*(self: Class, name: string): Method =
  if self.parent != nil:
    return self.parent.get_method(name)
  else:
    not_allowed("No super method available: " & name)

proc get_class*(val: Value): Class =
  case val.kind:
    of VkApplication:
      return App.ref.app.application_class.ref.class
    of VkPackage:
      return App.ref.app.package_class.ref.class
    of VkInstance:
      return val.ref.instance_class
    # of VkCast:
    #   return val.cast_class
    of VkClass:
      return App.ref.app.class_class.ref.class
    # of VkMixin:
    #   return App.ref.app.mixin_class.ref.class
    of VkNamespace:
      return App.ref.app.namespace_class.ref.class
    # of VkFuture:
    #   return App.ref.app.future_class.ref.class
    # of VkThread:
    #   return App.ref.app.thread_class.ref.class
    # of VkThreadMessage:
    #   return App.ref.app.thread_message_class.ref.class
    # of VkNativeFile:
    #   return App.ref.app.file_class.ref.class
    # of VkException:
    #   let ex = val.exception
    #   if ex is ref Exception:
    #     let ex = cast[ref Exception](ex)
    #     if ex.instance != nil:
    #       return ex.instance.instance_class
    #     else:
    #       return App.ref.app.exception_class.ref.class
    #   else:
    #     return App.ref.app.exception_class.ref.class
    of VkNil:
      return App.ref.app.nil_class.ref.class
    of VkBool:
      return App.ref.app.bool_class.ref.class
    of VkInt:
      return App.ref.app.int_class.ref.class
    of VkChar:
      return App.ref.app.char_class.ref.class
    of VkString:
      return App.ref.app.string_class.ref.class
    of VkSymbol:
      return App.ref.app.symbol_class.ref.class
    of VkComplexSymbol:
      return App.ref.app.complex_symbol_class.ref.class
    of VkArray:
      return App.ref.app.array_class.ref.class
    of VkMap:
      return App.ref.app.map_class.ref.class
    of VkSet:
      return App.ref.app.set_class.ref.class
    of VkGene:
      return App.ref.app.gene_class.ref.class
    # of VkRegex:
    #   return App.ref.app.regex_class.ref.class
    # of VkRange:
    #   return App.ref.app.range_class.ref.class
    # of VkDate:
    #   return App.ref.app.date_class.ref.class
    # of VkDateTime:
    #   return App.ref.app.datetime_class.ref.class
    # of VkTime:
    #   return App.ref.app.time_class.ref.class
    of VkFunction:
      return App.ref.app.function_class.ref.class
    # of VkTimezone:
    #   return App.ref.app.timezone_class.ref.class
    # of VkAny:
    #   if val.any_class == nil:
    #     return App.ref.app.object_class.ref.class
    #   else:
    #     return val.any_class
    # of VkCustom:
    #   if val.custom_class == nil:
    #     return App.ref.app.object_class.ref.class
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
  self.methods[name.to_key()] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
  )

proc def_native_method*(self: Class, name: string, f: NativeFn2) =
  let r = new_ref(VkNativeFn2)
  r.native_fn2 = f
  self.methods[name.to_key()] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
  )

proc def_native_macro_method*(self: Class, name: string, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.methods[name.to_key()] = Method(
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

#################### Native ######################

converter to_value*(f: NativeFn): Value {.inline.} =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  result = r.to_ref_value()

converter to_value*(f: NativeFn2): Value {.inline.} =
  let r = new_ref(VkNativeFn2)
  r.native_fn2 = f
  result = r.to_ref_value()

#################### Frame #######################

const REG_DEFAULT = 6
var FRAMES: seq[Frame] = @[]

proc free*(self: var Frame) {.inline.} =
  self.ref_count.dec()
  if self.ref_count <= 0:
    if self.caller_frame != nil:
      self.caller_frame.free()
    self.scope.free()
    self[].reset()
    FRAMES.add(self)

proc new_frame(): Frame {.inline.} =
  if FRAMES.len > 0:
    result = FRAMES.pop()
  else:
    result = cast[Frame](alloc0(sizeof(FrameObj)))
  result.ref_count = 1
  result.stack_index = REG_DEFAULT

proc new_frame*(ns: Namespace): Frame {.inline.} =
  result = new_frame()
  result.ns = ns
  result.scope = new_scope()

proc new_frame*(caller_frame: Frame, caller_address: Address, scope: Scope): Frame {.inline.} =
  result = new_frame()
  caller_frame.ref_count.inc()
  result.caller_frame = caller_frame
  result.caller_address = caller_address
  result.scope = scope

proc new_frame*(caller_frame: Frame, caller_address: Address): Frame {.inline.} =
  result = new_frame(caller_frame, caller_address, new_scope())

proc update*(self: var Frame, f: Frame) {.inline.} =
  f.ref_count.inc()
  if self != nil:
    self.free()
  self = f

template current*(self: Frame): Value =
  self.stack[self.stack_index - 1]

proc replace*(self: var Frame, v: Value) {.inline.} =
  self.stack[self.stack_index - 1] = v

template push*(self: var Frame, value: sink Value) =
  self.stack[self.stack_index] = value
  self.stack_index.inc()

proc pop*(self: var Frame): Value {.inline.} =
  self.stack_index.dec()
  result = self.stack[self.stack_index]
  self.stack[self.stack_index] = NIL

template pop2*(self: var Frame, to: var Value) =
  self.stack_index.dec()
  copy_mem(to.addr, self.stack[self.stack_index].addr, 8)
  self.stack[self.stack_index] = NIL

template default*(self: Frame): Value =
  self.stack[REG_DEFAULT]

#################### COMPILER ####################

proc new_compilation_unit*(): CompilationUnit =
  CompilationUnit(
    id: new_id(),
    scope_tracker: ScopeTracker(),
  )

proc `$`*(self: Instruction): string =
  case self.kind
    of IkPushValue,
      IkVar,
      IkAddValue, IkLtValue,
      IkMapSetProp, IkMapSetPropValue,
      IkArrayAddChildValue,
      IkResolveSymbol, IkResolveMethod,
      IkSetMember, IkGetMember,
      IkSetChild, IkGetChild:
      if self.label.int > 0:
        result = fmt"{self.label.int32.to_hex()} {($self.kind)[2..^1]} {$self.arg0}"
      else:
        result = fmt"         {($self.kind)[2..^1]} {$self.arg0}"
    of IkJump, IkJumpIfFalse:
      if self.label.int > 0:
        result = fmt"{self.label.int32.to_hex()} {($self.kind)[2..^1]} {self.arg0.int:03}"
      else:
        result = fmt"         {($self.kind)[2..^1]} {self.arg0.int:03}"
    of IkJumpIfMatchSuccess:
      if self.label.int > 0:
        result = fmt"{self.label.int32.to_hex()} {($self.kind)[2..^1]} {$self.arg0} {self.arg1.int:03}"
      else:
        result = fmt"         {($self.kind)[2..^1]} {$self.arg0} {self.arg1.int:03}"
    else:
      if self.label.int > 0:
        result = fmt"{self.label.int32.to_hex()} {($self.kind)[2..^1]}"
      else:
        result = fmt"         {($self.kind)[2..^1]}"

proc `$`*(self: seq[Instruction]): string =
  var i = 0
  while i < self.len:
    let instr = self[i]
    result &= fmt"{i:03} {instr}" & "\n"
    case instr.kind:
      of IkFunction:
        i.inc(2)
      else:
        i.inc()

proc `$`*(self: CompilationUnit): string =
  "CompilationUnit " & $(cast[uint64](self.id)) & "\n" & $self.instructions

proc new_label*(): Label =
  result = rand(int16.high).Label

proc find_label*(self: CompilationUnit, label: Label): int =
  var i = 0
  while i < self.instructions.len:
    let inst = self.instructions[i]
    if inst.label == label:
      while self.instructions[i].kind == IkNoop:
        i.inc()
      return i
    i.inc()

proc find_loop_start*(self: CompilationUnit, pos: int): int =
  var pos = pos
  while pos > 0:
    pos.dec()
    if self.instructions[pos].kind == IkLoopStart:
      return pos
  not_allowed("Loop start not found")

proc find_loop_end*(self: CompilationUnit, pos: int): int =
  var pos = pos
  while pos < self.instructions.len - 1:
    pos.inc()
    if self.instructions[pos].kind == IkLoopEnd:
      return pos
  not_allowed("Loop end not found")

template scope_tracker*(self: Compiler): ScopeTracker =
  self.scope_trackers[^1]

#################### VM ##########################

proc init_app_and_vm*() =
  VM = VirtualMachine(
    state: VmWaiting,
    code_mgr: CodeManager(),
  )
  let r = new_ref(VkApplication)
  r.app = new_app()
  r.app.global_ns = new_namespace("global").to_value()
  r.app.gene_ns   = new_namespace("gene"  ).to_value()
  r.app.genex_ns  = new_namespace("gene"  ).to_value()
  App = r.to_ref_value()

  for callback in VmCreatedCallbacks:
    callback()

# proc handle_args*(self: VirtualMachine, matcher: RootMatcher, args: Value) {.inline.} =
#   case matcher.hint_mode:
#     of MhNone:
#       discard
#     of MhSimpleData:
#       for i, value in args.gene.children:
#         self.frame.match_result.fields.add(MfSuccess)
#         self.frame.scope.members.add(value)
#       if args.gene.children.len < matcher.children.len:
#         for i in args.gene.children.len..matcher.children.len-1:
#           self.frame.match_result.fields.add(MfMissing)
#     else:
#       todo($matcher.hint_mode)

#################### Helpers #####################

const SYM_UNDERSCORE* = 0x7FF9_0000_0000_0000
const SYM_SELF* = 0x7FF9_0000_0000_0001
const SYM_GENE* = 0x7FF9_0000_0000_0002

proc init_values*() =
  SYMBOLS = ManagedSymbols()
  discard "_".to_symbol_value()
  discard "self".to_symbol_value()
  discard "gene".to_symbol_value()

init_values()

include ./utils
