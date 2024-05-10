import tables, strutils

import ./types
import "./compiler/if"

#################### Definitions #################
proc compile*(self: Compiler, input: Value)

proc compile(self: Compiler, input: seq[Value]) =
  for i, v in input:
    self.compile(v)
    if i < input.len - 1:
      self.output.instructions.add(Instruction(kind: IkPop))

proc compile_literal(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))

# Translate $x to gene/x and $x/y to gene/x/y
proc translate_symbol(input: Value): Value =
  case input.kind:
    of VkSymbol:
      let s = input.str
      if s.starts_with("$"):
        result = @["gene", s[1..^1]].to_complex_symbol()
      else:
        result = input
    of VkComplexSymbol:
      result = input
      let r = input.ref
      if r.csymbol[0] == "":
        r.csymbol[0] = "self"
      elif r.csymbol[0].starts_with("$"):
        r.csymbol.insert("gene", 0)
        r.csymbol[1] = r.csymbol[1][1..^1]
    else:
      not_allowed($input)

proc compile_complex_symbol(self: Compiler, input: Value) =
  if self.quote_level > 0:
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))
  else:
    let r = translate_symbol(input).ref
    let key = r.csymbol[0].to_key()
    if self.scope_tracker.mappings.has_key(key):
      self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: self.scope_tracker.mappings[key].Value))
    else:
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: r.csymbol[0].to_symbol_value()))
    for s in r.csymbol[1..^1]:
      let (is_int, i) = to_int(s)
      if is_int:
        self.output.instructions.add(Instruction(kind: IkGetChild, arg0: i))
      elif s.starts_with("."):
        self.output.instructions.add(Instruction(kind: IkCallMethodNoArgs, arg0: s[1..^1]))
      else:
        self.output.instructions.add(Instruction(kind: IkGetMember, arg0: s.to_key()))

proc compile_symbol(self: Compiler, input: Value) =
  if self.quote_level > 0:
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))
  else:
    let input = translate_symbol(input)
    if input.kind == VkSymbol:
      let key = cast[Key](input)
      let found = self.scope_tracker.locate(key)
      if found.local_index >= 0:
        if found.parent_index == 0:
          self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: found.local_index.Value))
        else:
          self.output.instructions.add(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.Value, arg1: found.parent_index))
      else:
        self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: input))
    elif input.kind == VkComplexSymbol:
      self.compile_complex_symbol(input)

proc compile_array(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkArrayStart))
  for child in input.ref.arr:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkArrayAddChild))
  self.output.instructions.add(Instruction(kind: IkArrayEnd))

proc compile_map(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkMapStart))
  for k, v in input.ref.map:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkMapSetProp, arg0: k))
  self.output.instructions.add(Instruction(kind: IkMapEnd))

proc compile_do(self: Compiler, gene: ptr Gene) =
  self.compile(gene.children)

proc start_scope(self: Compiler) =
  let scope_tracker = new_scope_tracker(self.scope_tracker)
  self.scope_trackers.add(scope_tracker)
  # ScopeStart is added when the first variable is declared
  # self.output.instructions.add(Instruction(kind: IkScopeStart, arg0: st.to_value()))

proc start_scope(self: Compiler, parent: ScopeTracker, parent_index_max: int) =
  var scope_tracker = new_scope_tracker(parent)
  scope_tracker.parent_index_max = parent_index_max.int16
  self.scope_trackers.add(scope_tracker)

proc add_scope_start(self: Compiler) =
  if self.scope_tracker.next_index == 0:
    self.output.instructions.add(Instruction(kind: IkScopeStart, arg0: self.scope_tracker.to_value()))

proc end_scope(self: Compiler) =
  if self.scope_tracker.next_index > 0:
    self.output.instructions.add(Instruction(kind: IkScopeEnd))
  discard self.scope_trackers.pop()

proc compile_if(self: Compiler, gene: ptr Gene) =
  normalize_if(gene)

  self.start_scope()

  self.compile(gene.props[COND_KEY.to_key()])
  let else_label = new_label()
  let end_label = new_label()
  self.output.instructions.add(Instruction(kind: IkJumpIfFalse, arg0: else_label.Value))

  self.start_scope()
  self.compile(gene.props[THEN_KEY.to_key()])
  self.end_scope()

  self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.Value))

  self.output.instructions.add(Instruction(kind: IkNoop, label: else_label))
  self.start_scope()
  self.compile(gene.props[ELSE_KEY.to_key()])
  self.end_scope()

  self.output.instructions.add(Instruction(kind: IkNoop, label: end_label))

  self.end_scope()

proc compile_var(self: Compiler, gene: ptr Gene) =
  let name = gene.children[0]
  let index = self.scope_tracker.next_index
  self.scope_tracker.mappings[name.str.to_key()] = index
  if gene.children.len > 1:
    self.compile(gene.children[1])
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    self.output.instructions.add(Instruction(kind: IkVar, arg0: index.Value))
  else:
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    self.output.instructions.add(Instruction(kind: IkVarValue, arg0: NIL, arg1: index))

proc compile_assignment(self: Compiler, gene: ptr Gene) =
  let `type` = gene.type
  if `type`.kind == VkSymbol:
    self.compile(gene.children[1])
    let key = `type`.str.to_key()
    let found = self.scope_tracker.locate(key)
    if found.local_index >= 0:
      if found.parent_index == 0:
        self.output.instructions.add(Instruction(kind: IkVarAssign, arg0: found.local_index.Value))
      else:
        self.output.instructions.add(Instruction(kind: IkVarAssignInherited, arg0: found.local_index.Value, arg1: found.parent_index))
    else:
      self.output.instructions.add(Instruction(kind: IkAssign, arg0: `type`))
  elif `type`.kind == VkComplexSymbol:
    let r = translate_symbol(`type`).ref
    let key = r.csymbol[0].to_key()
    if self.scope_tracker.mappings.has_key(key):
      self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: self.scope_tracker.mappings[key].Value))
    else:
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: r.csymbol[0].to_symbol_value()))
    if r.csymbol.len > 2:
      for s in r.csymbol[1..^2]:
        let (is_int, i) = to_int(s)
        if is_int:
          self.output.instructions.add(Instruction(kind: IkGetChild, arg0: i))
        elif s.starts_with("."):
          self.output.instructions.add(Instruction(kind: IkCallMethodNoArgs, arg0: s[1..^1]))
        else:
          self.output.instructions.add(Instruction(kind: IkGetMember, arg0: s.to_key()))
    self.compile(gene.children[1])
    self.output.instructions.add(Instruction(kind: IkSetMember, arg0: r.csymbol[^1].to_key()))
  else:
    not_allowed($`type`)

proc compile_loop(self: Compiler, gene: ptr Gene) =
  let label = new_label()
  self.output.instructions.add(Instruction(kind: IkLoopStart, label: label))
  self.compile(gene.children)
  self.output.instructions.add(Instruction(kind: IkContinue, arg0: label.Value))
  self.output.instructions.add(Instruction(kind: IkLoopEnd, label: label))

proc compile_break(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  self.output.instructions.add(Instruction(kind: IkBreak))

proc compile_fn(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkFunction, arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(Instruction(kind: IkNoop, arg0: r.to_ref_value()))

proc compile_return(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  self.output.instructions.add(Instruction(kind: IkReturn))

proc compile_macro(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkMacro, arg0: input))

proc compile_compile(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkCompileFn, arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(Instruction(kind: IkNoop, arg0: r.to_ref_value()))

proc compile_ns(self: Compiler, gene: ptr Gene) =
  self.output.instructions.add(Instruction(kind: IkNamespace, arg0: gene.children[0]))
  if gene.children.len > 1:
    let body = new_stream_value(gene.children[1..^1])
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: body))
    self.output.instructions.add(Instruction(kind: IkCompileInit))
    self.output.instructions.add(Instruction(kind: IkCallInit))

proc compile_class(self: Compiler, gene: ptr Gene) =
  var body_start = 1
  if gene.children.len >= 3 and gene.children[1] == "<".to_symbol_value():
    body_start = 3
    self.compile(gene.children[2])
    self.output.instructions.add(Instruction(kind: IkSubClass, arg0: gene.children[0]))
  else:
    self.output.instructions.add(Instruction(kind: IkClass, arg0: gene.children[0]))

  if gene.children.len > body_start:
    let body = new_stream_value(gene.children[body_start..^1])
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: body))
    self.output.instructions.add(Instruction(kind: IkCompileInit))
    self.output.instructions.add(Instruction(kind: IkCallInit))

# Construct a Gene object whose type is the class
# The Gene object will be used as the arguments to the constructor
proc compile_new(self: Compiler, gene: ptr Gene) =
  self.output.instructions.add(Instruction(kind: IkGeneStart))
  self.compile(gene.children[0])
  self.output.instructions.add(Instruction(kind: IkGeneSetType))
  # TODO: compile the arguments
  # IKGeneEnd is replaced by IkNew here
  # self.output.instructions.add(Instruction(kind: IkGeneEnd))
  self.output.instructions.add(Instruction(kind: IkNew))

proc compile_gene_default(self: Compiler, gene: ptr Gene) {.inline.} =
  self.output.instructions.add(Instruction(kind: IkGeneStart))
  self.compile(gene.type)
  self.output.instructions.add(Instruction(kind: IkGeneSetType))
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkGeneEnd))

# For a call that is unsure whether it is a function call or a macro call,
# we need to handle both cases and decide at runtime:
# * Compile type (use two labels to mark boundaries of two branches)
# * GeneCheckType Update code in place, remove incompatible branch
# * GeneStartMacro(fail if the type is not a macro)
# * Compile arguments assuming it is a macro call
# * FnLabel: GeneStart(fail if the type is not a function)
# * Compile arguments assuming it is a function call
# * GeneLabel: GeneEnd
# Similar logic is used for regular method calls and macro-method calls
proc compile_gene_unknown(self: Compiler, gene: ptr Gene) {.inline.} =
  let start_pos = self.output.instructions.len
  self.compile(gene.type)

  # if gene.args_are_literal():
  #   self.output.instructions.add(Instruction(kind: IkGeneStartDefault))
  #   for k, v in gene.props:
  #     self.compile(v)
  #     self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  #   for child in gene.children:
  #     self.compile(child)
  #     self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  #   self.output.instructions.add(Instruction(kind: IkGeneEnd))
  #   return

  let fn_label = new_label()
  let end_label = new_label()
  self.output.instructions.add(Instruction(kind: IkGeneStartDefault, arg0: fn_label.Value))

  # self.output.instructions.add(Instruction(kind: IkGeneStartMacro))
  self.quote_level.inc()
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.Value))
  self.quote_level.dec()

  # self.output.instructions.add(Instruction(kind: IkGeneStartFn, label: fn_label))
  self.output.instructions.add(Instruction(kind: IkNoop, label: fn_label))
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkGeneEnd, arg0: start_pos, label: end_label))

# TODO: handle special cases:
# 1. No arguments
# 2. All arguments are primitives or array/map of primitives
#
# self, method_name, arguments
# self + method_name => bounded_method_object (is composed of self, class, method_object(is composed of name, logic))
# (bounded_method_object ...arguments)
proc compile_method_call(self: Compiler, gene: ptr Gene) {.inline.} =
  if gene.type.kind == VkSymbol and gene.type.str.starts_with("."):
    self.output.instructions.add(Instruction(kind: IkSelf))
    self.output.instructions.add(Instruction(kind: IkResolveMethod, arg0: gene.type.str[1..^1]))
  else:
    self.compile(gene.type)
    let first = gene.children[0]
    gene.children.delete(0)
    self.output.instructions.add(Instruction(kind: IkResolveMethod, arg0: first.str[1..^1]))

  let fn_label = new_label()
  let end_label = new_label()
  self.output.instructions.add(Instruction(kind: IkGeneStartDefault, arg0: fn_label.Value))

  self.quote_level.inc()
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.Value))
  self.quote_level.dec()

  self.output.instructions.add(Instruction(kind: IkNoop, label: fn_label))
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))

  self.output.instructions.add(Instruction(kind: IkGeneEnd, label: end_label))

proc compile_gene(self: Compiler, input: Value) =
  let gene = input.gene
  if self.quote_level > 0 or gene.type == "_".to_symbol_value() or gene.type.kind == VkQuote:
    self.compile_gene_default(gene)
    return

  let `type` = gene.type
  if gene.children.len > 0:
    let first = gene.children[0]
    if first.kind == VkSymbol:
      case first.str:
        of "=":
          self.compile_assignment(gene)
          return
        of "+":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkAdd))
          return
        of "-":
          self.compile(`type`)
          if gene.children[1].is_literal():
            self.output.instructions.add(Instruction(kind: IkSubValue, arg0: gene.children[1]))
          else:
            self.compile(gene.children[1])
            self.output.instructions.add(Instruction(kind: IkSub))
          return
        of "*":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkMul))
          return
        of "/":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkDiv))
          return
        of "<":
          self.compile(`type`)
          if gene.children[1].is_literal():
            self.output.instructions.add(Instruction(kind: IkLtValue, arg0: gene.children[1]))
          else:
            self.compile(gene.children[1])
            self.output.instructions.add(Instruction(kind: IkLt))
          return
        of "<=":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkLe))
          return
        of ">":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkGt))
          return
        of ">=":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkGe))
          return
        of "==":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkEq))
          return
        of "!=":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkNe))
          return
        of "&&":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkAnd))
          return
        of "||":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkOr))
          return
        else:
          if first.str.starts_with("."):
            self.compile_method_call(gene)
            return

  if `type`.kind == VkSymbol:
    case `type`.str:
      of "do":
        self.compile_do(gene)
        return
      of "if":
        self.compile_if(gene)
        return
      of "var":
        self.compile_var(gene)
        return
      of "loop":
        self.compile_loop(gene)
        return
      of "break":
        self.compile_break(gene)
        return
      of "fn", "fnx":
        self.compile_fn(input)
        return
      of "macro":
        self.compile_macro(input)
        return
      of "compile":
        self.compile_compile(input)
        return
      of "return":
        self.compile_return(gene)
        return
      of "ns":
        self.compile_ns(gene)
        return
      of "class":
        self.compile_class(gene)
        return
      of "new":
        self.compile_new(gene)
        return
      else:
        let s = `type`.str
        if s.starts_with("."):
          self.compile_method_call(gene)
          return

  self.compile_gene_unknown(gene)

proc compile*(self: Compiler, input: Value) =
  case input.kind:
    of VkInt, VkBool, VkNil:
      self.compile_literal(input)
    of VkString:
      self.compile_literal(input) # TODO
    of VkSymbol:
      self.compile_symbol(input)
    of VkComplexSymbol:
      self.compile_complex_symbol(input)
    of VkQuote:
      self.quote_level.inc()
      self.compile(input.ref.quote)
      self.quote_level.dec()
    of VkStream:
      self.compile(input.ref.stream)
    of VkArray:
      self.compile_array(input)
    of VkMap:
      self.compile_map(input)
    of VkGene:
      self.compile_gene(input)
    else:
      todo($input.kind)

proc update_jumps(self: CompilationUnit) =
  for i, inst in self.instructions:
    case inst.kind
      of IkJump, IkJumpIfFalse, IkContinue, IkGeneStartDefault:
        self.instructions[i].arg0 = self.find_label(inst.arg0.Label).Value
      of IkJumpIfMatchSuccess:
        self.instructions[i].arg1 = self.find_label(inst.arg1.Label).int32
      else:
        discard

# Clean up scopes by removing unnecessary ScopeStart and ScopeEnd instructions
proc cleanup_scopes(self: CompilationUnit) =
  todo("cleanup_scopes")

proc compile*(input: seq[Value]): CompilationUnit =
  let self = Compiler(output: new_compilation_unit())
  self.output.instructions.add(Instruction(kind: IkStart))
  self.start_scope()

  for i, v in input:
    self.compile(v)
    if i < input.len - 1:
      self.output.instructions.add(Instruction(kind: IkPop))

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  result = self.output

proc compile*(f: Function) =
  if f.body_compiled != nil:
    return

  var self = Compiler(output: new_compilation_unit())
  self.output.instructions.add(Instruction(kind: IkStart))
  self.scope_trackers.add(f.scope_tracker)
  # self.start_scope(f.scope_tracker, f.parent_scope_max)
  # f.scope_tracker = self.scope_tracker

  # generate code for arguments
  for i, m in f.matcher.children:
    self.scope_tracker.mappings[m.name_key] = i.int16
    let label = new_label()
    self.output.instructions.add(Instruction(
      kind: IkJumpIfMatchSuccess,
      arg0: i.Value,
      arg1: label,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, arg0: m.name_key.Value))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(f.body)

  # self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  f.body_compiled = self.output
  f.body_compiled.matcher = f.matcher

proc compile*(m: Macro) =
  if m.body_compiled != nil:
    return

  m.body_compiled = compile(m.body)
  m.body_compiled.matcher = m.matcher

proc compile*(f: CompileFn) =
  if f.body_compiled != nil:
    return

  let self = Compiler(output: new_compilation_unit())
  self.output.instructions.add(Instruction(kind: IkStart))
  self.scope_trackers.add(f.scope_tracker)
  # self.start_scope(f.scope_tracker, f.parent_scope_max)
  # f.scope_tracker = self.scope_tracker

  # generate code for arguments
  for i, m in f.matcher.children:
    self.scope_tracker.mappings[m.name_key] = i.int16
    let label = new_label()
    self.output.instructions.add(Instruction(
      kind: IkJumpIfMatchSuccess,
      arg0: i.Value,
      arg1: label,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, arg0: m.name_key.Value))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(f.body)

  # self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  f.body_compiled = self.output
  f.body_compiled.kind = CkCompileFn
  f.body_compiled.matcher = f.matcher

proc compile_init*(input: Value): CompilationUnit =
  let self = Compiler(output: new_compilation_unit())
  self.output.skip_return = true
  self.output.instructions.add(Instruction(kind: IkStart))
  self.start_scope()

  self.compile(input)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  result = self.output

proc replace_chunk*(self: var CompilationUnit, start_pos: int, end_pos: int, replacement: sink seq[Instruction]) =
  self.instructions[start_pos..end_pos] = replacement
