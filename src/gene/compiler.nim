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
  self.output.instructions.add(Instruction(kind: IkPushValue, push_value: input))

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
    self.output.instructions.add(Instruction(kind: IkPushValue, push_value: input))
  else:
    let r = translate_symbol(input).ref
    let key = r.csymbol[0].to_key()
    if self.scope_tracker.mappings.has_key(key):
      self.output.instructions.add(Instruction(kind: IkVarResolve, var_arg0: self.scope_tracker.mappings[key].Value))
    else:
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, var_arg0: r.csymbol[0].to_symbol_value()))
    for s in r.csymbol[1..^1]:
      let (is_int, i) = to_int(s)
      if is_int:
        self.output.instructions.add(Instruction(kind: IkGetChild, var_arg0: i))
      elif s.starts_with("."):
        self.output.instructions.add(Instruction(kind: IkCallMethodNoArgs, var_arg0: s[1..^1]))
      else:
        self.output.instructions.add(Instruction(kind: IkGetMember, var_arg0: s.to_key()))

proc compile_symbol(self: Compiler, input: Value) =
  if self.quote_level > 0:
    self.output.instructions.add(Instruction(kind: IkPushValue, push_value: input))
  else:
    let input = translate_symbol(input)
    if input.kind == VkSymbol:
      let key = cast[Key](input)
      let found = self.scope_tracker.locate(key)
      if found.local_index >= 0:
        if found.parent_index == 0:
          self.output.instructions.add(Instruction(kind: IkVarResolve, var_arg0: found.local_index.Value))
        else:
          self.output.instructions.add(Instruction(kind: IkVarResolveInherited, effect_arg0: found.local_index.Value, effect_arg1: found.parent_index.Value))
      else:
        self.output.instructions.add(Instruction(kind: IkResolveSymbol, var_arg0: input))
    elif input.kind == VkComplexSymbol:
      self.compile_complex_symbol(input)

proc compile_array(self: Compiler, input: Value) =
  # Create new array and store in register 0
  self.output.instructions.add(Instruction(kind: IkArrayStart))
  for child in input.ref.arr:
    # Move array to register 1 temporarily
    self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
    # Compile child value to register 0
    if child.kind == VkSymbol:
      let key = child.str.to_key()
      let found = self.scope_tracker.locate(key)
      if found.local_index >= 0:
        if found.parent_index == 0:
          self.output.instructions.add(Instruction(kind: IkVarResolve, var_arg0: found.local_index.Value))
        else:
          self.output.instructions.add(Instruction(kind: IkVarResolveInherited, effect_arg0: found.local_index.Value, effect_arg1: found.parent_index.Value))
      else:
        self.output.instructions.add(Instruction(kind: IkResolveSymbol, var_arg0: child))
    else:
      self.output.instructions.add(Instruction(kind: IkPushValue, push_value: child))
    # Add child to array (array is in register 1, child in register 0)
    self.output.instructions.add(Instruction(kind: IkMove, move_dest: 2.Value, move_src: 0.Value))  # Save child in register 2
    self.output.instructions.add(Instruction(kind: IkMove, move_dest: 0.Value, move_src: 1.Value))  # Move array back to register 0
    self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 2.Value))  # Move child to register 1
    self.output.instructions.add(Instruction(kind: IkArrayAddChild))
  self.output.instructions.add(Instruction(kind: IkArrayEnd))

proc compile_map(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkMapStart))
  for k, v in input.ref.map:
    # Move map to register 1 temporarily
    self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
    # Compile and push value to register 0
    self.compile(v)
    # Move value to register 2
    self.output.instructions.add(Instruction(kind: IkMove, move_dest: 2.Value, move_src: 0.Value))
    # Move map back to register 0
    self.output.instructions.add(Instruction(kind: IkMove, move_dest: 0.Value, move_src: 1.Value))
    # Move value to register 1
    self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 2.Value))
    # Set property
    self.output.instructions.add(Instruction(kind: IkMapSetProp, prop_arg0: k))
  self.output.instructions.add(Instruction(kind: IkMapEnd))

proc compile_do(self: Compiler, gene: ptr Gene) =
  self.compile(gene.children)

proc start_scope(self: Compiler) =
  let scope_tracker = new_scope_tracker(self.scope_tracker)
  self.scope_trackers.add(scope_tracker)
  # ScopeStart is added when the first variable is declared
  # self.output.instructions.add(Instruction(kind: IkScopeStart, arg0: st.to_value()))

# proc start_scope(self: Compiler, parent: ScopeTracker, parent_index_max: int) =
#   var scope_tracker = new_scope_tracker(parent)
#   scope_tracker.parent_index_max = parent_index_max.int16
#   self.scope_trackers.add(scope_tracker)

proc add_scope_start(self: Compiler) =
  if self.scope_tracker.next_index == 0:
    self.output.instructions.add(Instruction(kind: IkScopeStart, scope_arg0: self.scope_tracker.to_value()))

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
  self.output.instructions.add(Instruction(kind: IkJumpIfFalse, jump_arg0: else_label.Value))

  self.start_scope()
  self.compile(gene.props[THEN_KEY.to_key()])
  self.end_scope()

  self.output.instructions.add(Instruction(kind: IkJump, jump_arg0: end_label.Value))

  self.output.instructions.add(Instruction(kind: IkNoop, label: else_label))
  self.start_scope()
  self.compile(gene.props[ELSE_KEY.to_key()])
  self.end_scope()

  self.output.instructions.add(Instruction(kind: IkNoop, label: end_label))

  self.end_scope()

proc compile_if_not(self: Compiler, gene: ptr Gene) =
  self.start_scope()

  self.compile(gene.children[0])
  let else_label = new_label()
  let end_label = new_label()
  self.output.instructions.add(Instruction(kind: IkJumpIfTrue, jump_arg0: else_label.Value))

  self.start_scope()
  self.compile(gene.children[1..^1])
  self.end_scope()

  self.output.instructions.add(Instruction(kind: IkJump, jump_arg0: end_label.Value))

  self.output.instructions.add(Instruction(kind: IkNoop, label: else_label))
  self.output.instructions.add(Instruction(kind: IkPushNil))

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
    self.output.instructions.add(Instruction(kind: IkVar, var_arg0: index.Value))
  else:
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    self.output.instructions.add(Instruction(kind: IkVarValue, prop_arg0: NIL, prop_arg1: index.Value))

proc compile_assignment(self: Compiler, gene: ptr Gene) =
  let `type` = gene.type
  if `type`.kind == VkSymbol:
    self.compile(gene.children[1])
    let key = `type`.str.to_key()
    let found = self.scope_tracker.locate(key)
    if found.local_index >= 0:
      if found.parent_index == 0:
        self.output.instructions.add(Instruction(kind: IkVarAssign, var_arg0: found.local_index.Value))
      else:
        self.output.instructions.add(Instruction(kind: IkVarAssignInherited, effect_arg0: found.local_index.Value, effect_arg1: found.parent_index.Value))
    else:
      self.output.instructions.add(Instruction(kind: IkAssign, var_arg0: `type`))
  elif `type`.kind == VkComplexSymbol:
    let r = translate_symbol(`type`).ref
    let key = r.csymbol[0].to_key()
    if self.scope_tracker.mappings.has_key(key):
      self.output.instructions.add(Instruction(kind: IkVarResolve, var_arg0: self.scope_tracker.mappings[key].Value))
    else:
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, var_arg0: r.csymbol[0].to_symbol_value()))
    if r.csymbol.len > 2:
      for s in r.csymbol[1..^2]:
        let (is_int, i) = to_int(s)
        if is_int:
          self.output.instructions.add(Instruction(kind: IkGetChild, var_arg0: i))
        elif s.starts_with("."):
          self.output.instructions.add(Instruction(kind: IkCallMethodNoArgs, var_arg0: s[1..^1]))
        else:
          self.output.instructions.add(Instruction(kind: IkGetMember, var_arg0: s.to_key()))
    self.compile(gene.children[1])
    self.output.instructions.add(Instruction(kind: IkSetMember, var_arg0: r.csymbol[^1].to_key()))
  else:
    not_allowed($`type`)

proc compile_loop(self: Compiler, gene: ptr Gene) =
  let label = new_label()
  self.output.instructions.add(Instruction(kind: IkLoopStart, label: label))
  self.compile(gene.children)
  self.output.instructions.add(Instruction(kind: IkContinue, jump_arg0: label.Value))
  self.output.instructions.add(Instruction(kind: IkLoopEnd, label: label))

proc compile_break(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  self.output.instructions.add(Instruction(kind: IkBreak))

proc compile_xloop(self: Compiler, gene: ptr Gene) =
  let label = new_label()
  let config = EffectConfig(
    scope: EffectScope(kind: EScopeBounded, start_pos: self.output.instructions.len.int32),
    handlers: initTable[EffectKind, EffectHandler]()
  )
  let v = config.to_value()
  self.output.instructions.add(Instruction(kind: IkEffectEnter, effect_arg0: v))

  self.output.instructions.add(Instruction(kind: IkNoop, label: label))
  self.compile(gene.children)
  self.output.instructions.add(Instruction(kind: IkJump, jump_arg0: label.Value)) # jump back to the beginning of the loop

  # Break effect handler
  let break_handler_pos = self.output.instructions.len
  config.handlers[EfBreak] = EffectHandler(kind: EhSimple, simple_pos: break_handler_pos)
  self.output.instructions.add(Instruction(kind: IkEffectConsume, effect_arg0: EfBreak.int32.Value))

  let end_label = new_label()
  self.output.instructions.add(Instruction(kind: IkJump, jump_arg0: end_label.Value)) # Jump past the loop

  config.scope.end_pos = self.output.instructions.len.int32
  self.output.instructions.add(Instruction(kind: IkEffectExit, effect_arg0: v))

proc compile_xbreak(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  self.output.instructions.add(Instruction(kind: IkEffectTrigger, effect_arg0: EfBreak.int32.Value))

# proc compile_xloop(self: Compiler, gene: ptr Gene) =
#   let label = new_label()
#   let config = EffectConfig()
#   let v = config.to_value()
#   self.output.instructions.add(Instruction(kind: IkEffectEnter, arg0: v))

#   self.output.instructions.add(Instruction(kind: IkNoop, label: label))
#   self.compile(gene.children)
#   self.output.instructions.add(Instruction(kind: IkJump, arg0: label.Value)) # jump back to the beginning of the loop

#   # Break effect handler
#   config.handlers[EfBreak] = EffectHandler(kind: EhSimple, simple_pos: self.output.instructions.len)
#   self.output.instructions.add(Instruction(kind: IkEffectConsume, arg1: EfBreak.int32))

#   # Use boundary check instead of IkEffectExit?
#   # Clean up the effect handlers
#   # self.output.instructions.add(Instruction(kind: IkEffectExit, arg0: v))

# proc compile_xbreak(self: Compiler, gene: ptr Gene) =
#   if gene.children.len > 0:
#     self.compile(gene.children[0])
#   else:
#     self.output.instructions.add(Instruction(kind: IkPushNil))
#   self.output.instructions.add(Instruction(kind: IkEffectTrigger, arg1: EfBreak.int32))

proc compile_fn(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkFunction, var_arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(Instruction(kind: IkPushValue, push_value: r.to_ref_value()))

proc compile_return(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  self.output.instructions.add(Instruction(kind: IkReturn))

proc compile_macro(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkMacro, var_arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(Instruction(kind: IkPushValue, push_value: r.to_ref_value()))

proc compile_block(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkBlock, var_arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(Instruction(kind: IkPushValue, push_value: r.to_ref_value()))

proc compile_compile(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkCompileFn, var_arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(Instruction(kind: IkPushValue, push_value: r.to_ref_value()))

proc compile_ns(self: Compiler, gene: ptr Gene) =
  self.output.instructions.add(Instruction(kind: IkNamespace, var_arg0: gene.children[0]))
  if gene.children.len > 1:
    let body = new_stream_value(gene.children[1..^1])
    self.output.instructions.add(Instruction(kind: IkPushValue, push_value: body))
    self.output.instructions.add(Instruction(kind: IkCompileInit))
    self.output.instructions.add(Instruction(kind: IkCallInit))

proc compile_class(self: Compiler, gene: ptr Gene) =
  var body_start = 1
  if gene.children.len >= 3 and gene.children[1] == "<".to_symbol_value():
    body_start = 3
    self.compile(gene.children[2])
    self.output.instructions.add(Instruction(kind: IkSubClass, var_arg0: gene.children[0]))
  else:
    self.output.instructions.add(Instruction(kind: IkClass, var_arg0: gene.children[0]))

  if gene.children.len > body_start:
    let body = new_stream_value(gene.children[body_start..^1])
    self.output.instructions.add(Instruction(kind: IkPushValue, push_value: body))
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
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, prop_arg0: k))
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
  self.output.instructions.add(Instruction(kind: IkGeneStartDefault, prop_arg0: fn_label.Value))

  # self.output.instructions.add(Instruction(kind: IkGeneStartMacro))
  self.quote_level.inc()
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, prop_arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkJump, jump_arg0: end_label.Value))
  self.quote_level.dec()

  # self.output.instructions.add(Instruction(kind: IkGeneStartFn, label: fn_label))
  self.output.instructions.add(Instruction(kind: IkNoop, label: fn_label))
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, prop_arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkGeneEnd, jump_arg0: start_pos, label: end_label))

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
    self.output.instructions.add(Instruction(kind: IkResolveMethod, var_arg0: gene.type.str[1..^1]))
  else:
    self.compile(gene.type)
    let first = gene.children[0]
    gene.children.delete(0)
    self.output.instructions.add(Instruction(kind: IkResolveMethod, var_arg0: first.str[1..^1]))

  let fn_label = new_label()
  let end_label = new_label()
  self.output.instructions.add(Instruction(kind: IkGeneStartDefault, prop_arg0: fn_label.Value))

  self.quote_level.inc()
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, prop_arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkJump, jump_arg0: end_label.Value))
  self.quote_level.dec()

  self.output.instructions.add(Instruction(kind: IkNoop, label: fn_label))
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, prop_arg0: k))
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
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkAdd))
          return
        of "-":
          self.compile(`type`)
          if gene.children[1].is_literal():
            self.output.instructions.add(Instruction(kind: IkSubValue, value_arg0: gene.children[1]))
          else:
            self.compile(gene.children[1])
            self.output.instructions.add(Instruction(kind: IkSub))
          return
        of "*":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkMul))
          return
        of "/":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkDiv))
          return
        of "<":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          if gene.children[1].is_literal():
            self.output.instructions.add(Instruction(kind: IkLtValue, value_arg0: gene.children[1]))
          else:
            self.compile(gene.children[1])
            self.output.instructions.add(Instruction(kind: IkLt))
          return
        of "<=":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          if gene.children[1].is_literal():
            self.output.instructions.add(Instruction(kind: IkLeValue, value_arg0: gene.children[1]))
          else:
            self.compile(gene.children[1])
            self.output.instructions.add(Instruction(kind: IkLe))
          return
        of ">":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkGt))
          return
        of ">=":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkGe))
          return
        of "==":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkEq))
          return
        of "!=":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkNe))
          return
        of "&&":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkAnd))
          return
        of "||":
          self.compile(`type`)
          self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkOr))
          return
        of "->":
          self.compile_block(input)
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
      of "if_not":
        self.compile_if_not(gene)
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
      of "xloop":
        self.compile_xloop(gene)
        return
      of "xbreak":
        self.compile_xbreak(gene)
        return
      of "fn", "fnx":
        self.compile_fn(input)
        return
      of "macro":
        self.compile_macro(input)
        return
      of "->":
        self.compile_block(input)
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
      of IkJump, IkJumpIfFalse, IkJumpIfTrue, IkContinue:
        self.instructions[i].jump_arg0 = self.find_label(inst.jump_arg0.Label).Value
      of IkGeneStartDefault:
        self.instructions[i].prop_arg0 = self.find_label(inst.prop_arg0.Label).Value
      of IkJumpIfMatchSuccess:
        self.instructions[i].jump_arg1 = self.find_label(inst.jump_arg1.Label).Value
      else:
        discard

# # Clean up scopes by removing unnecessary ScopeStart and ScopeEnd instructions
# proc cleanup_scopes(self: CompilationUnit) =
#   todo("cleanup_scopes")

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

  # generate code for arguments
  for i, m in f.matcher.children:
    self.scope_tracker.mappings[m.name_key] = i.int16
    let label = new_label()
    self.output.instructions.add(Instruction(
      kind: IkJumpIfMatchSuccess,
      jump_arg0: i.Value,
      jump_arg1: label.Value,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, var_arg0: m.name_key.Value))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(f.body)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  f.body_compiled = self.output
  f.body_compiled.matcher = f.matcher

proc compile*(m: Macro) =
  if m.body_compiled != nil:
    return

  var self = Compiler(output: new_compilation_unit())
  self.output.instructions.add(Instruction(kind: IkStart))
  self.scope_trackers.add(m.scope_tracker)

  # generate code for arguments
  for i, m in m.matcher.children:
    self.scope_tracker.mappings[m.name_key] = i.int16
    let label = new_label()
    self.output.instructions.add(Instruction(
      kind: IkJumpIfMatchSuccess,
      jump_arg0: i.Value,
      jump_arg1: label.Value,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, var_arg0: m.name_key.Value))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(m.body)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  m.body_compiled = self.output
  m.body_compiled.matcher = m.matcher

proc compile*(b: Block) =
  if b.body_compiled != nil:
    return

  var self = Compiler(output: new_compilation_unit())
  self.output.instructions.add(Instruction(kind: IkStart))
  self.scope_trackers.add(b.scope_tracker)

  # generate code for arguments
  for i, m in b.matcher.children:
    self.scope_tracker.mappings[m.name_key] = i.int16
    let label = new_label()
    self.output.instructions.add(Instruction(
      kind: IkJumpIfMatchSuccess,
      jump_arg0: i.Value,
      jump_arg1: label.Value,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, var_arg0: m.name_key.Value))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(b.body)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  b.body_compiled = self.output
  b.body_compiled.matcher = b.matcher

proc compile*(f: CompileFn) =
  if f.body_compiled != nil:
    return

  let self = Compiler(output: new_compilation_unit())
  self.output.instructions.add(Instruction(kind: IkStart))
  self.scope_trackers.add(f.scope_tracker)

  # generate code for arguments
  for i, m in f.matcher.children:
    self.scope_tracker.mappings[m.name_key] = i.int16
    let label = new_label()
    self.output.instructions.add(Instruction(
      kind: IkJumpIfMatchSuccess,
      jump_arg0: i.Value,
      jump_arg1: label.Value,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, var_arg0: m.name_key.Value))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(f.body)

  self.end_scope()
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

proc compile_add(self: Compiler, gene: ptr Gene) =
  # Compile first operand
  self.compile(gene.children[0])
  # Move first operand to register 1
  self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
  # Compile second operand to register 0
  self.compile(gene.children[1])
  # Add instruction (uses register 1 and 0)
  self.output.instructions.add(Instruction(kind: IkAdd))

proc compile_sub(self: Compiler, gene: ptr Gene) =
  # Compile first operand
  self.compile(gene.children[0])
  # Move first operand to register 1
  self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
  # Compile second operand to register 0
  self.compile(gene.children[1])
  # Subtract instruction (uses register 1 and 0)
  self.output.instructions.add(Instruction(kind: IkSub))

proc compile_mul(self: Compiler, gene: ptr Gene) =
  # Compile first operand
  self.compile(gene.children[0])
  # Move first operand to register 1
  self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
  # Compile second operand to register 0
  self.compile(gene.children[1])
  # Multiply instruction (uses register 1 and 0)
  self.output.instructions.add(Instruction(kind: IkMul))

proc compile_div(self: Compiler, gene: ptr Gene) =
  # Compile first operand
  self.compile(gene.children[0])
  # Move first operand to register 1
  self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
  # Compile second operand to register 0
  self.compile(gene.children[1])
  # Divide instruction (uses register 1 and 0)
  self.output.instructions.add(Instruction(kind: IkDiv))

proc compile_pow(self: Compiler, gene: ptr Gene) =
  # Compile first operand
  self.compile(gene.children[0])
  # Move first operand to register 1
  self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
  # Compile second operand to register 0
  self.compile(gene.children[1])
  # Power instruction (uses register 1 and 0)
  self.output.instructions.add(Instruction(kind: IkPow))

proc compile_lt(self: Compiler, gene: ptr Gene) =
  # Compile first operand
  self.compile(gene.children[0])
  # Move first operand to register 1
  self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
  # Compile second operand to register 0
  self.compile(gene.children[1])
  # Less than instruction (uses register 1 and 0)
  self.output.instructions.add(Instruction(kind: IkLt))

proc compile_le(self: Compiler, gene: ptr Gene) =
  # Compile first operand
  self.compile(gene.children[0])
  # Move first operand to register 1
  self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
  # Compile second operand to register 0
  self.compile(gene.children[1])
  # Less than or equal instruction (uses register 1 and 0)
  self.output.instructions.add(Instruction(kind: IkLe))

proc compile_gt(self: Compiler, gene: ptr Gene) =
  # Compile first operand
  self.compile(gene.children[0])
  # Move first operand to register 1
  self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
  # Compile second operand to register 0
  self.compile(gene.children[1])
  # Greater than instruction (uses register 1 and 0)
  self.output.instructions.add(Instruction(kind: IkGt))

proc compile_ge(self: Compiler, gene: ptr Gene) =
  # Compile first operand
  self.compile(gene.children[0])
  # Move first operand to register 1
  self.output.instructions.add(Instruction(kind: IkMove, move_dest: 1.Value, move_src: 0.Value))
  # Compile second operand to register 0
  self.compile(gene.children[1])
  # Greater than or equal instruction (uses register 1 and 0)
  self.output.instructions.add(Instruction(kind: IkGe))
