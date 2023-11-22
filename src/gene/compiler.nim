import tables, strutils, strformat

import ./types
# import ./utils
# import "./compiler/if"

proc `$`*(self: Instruction): string =
  case self.kind
    of IkPushValue,
      IkVar,
      IkJump, IkJumpIfFalse,
      IkAddValue, IkLtValue,
      IkMapSetProp, IkMapSetPropValue,
      IkArrayAddChildValue,
      IkResolveSymbol,
      IkSetMember, IkGetMember,
      IkSetChild, IkGetChild,
      IkInternal:
      ($self.kind)[2..^1] & " " & $self.arg0
    of IkJumpIfMatchSuccess:
      ($self.kind)[2..^1] & " " & $self.arg0 & " " & $self.arg1
    else:
      ($self.kind)[2..^1]

proc `$`*(self: seq[Instruction]): string =
  for i, instr in self:
    result &= fmt"{i:03} {instr}" & "\n"

proc `$`*(self: CompilationUnit): string =
  "CompilationUnit " & $self.id & "\n" & $self.instructions

proc `len`*(self: CompilationUnit): int =
  self.instructions.len

proc `[]`*(self: CompilationUnit, i: int): Instruction =
  self.instructions[i]

proc find_label*(self: CompilationUnit, label: Label): int =
  for i, inst in self.instructions:
    if inst.label == label:
      return i

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

proc compile(self: var Compiler, input: Value)

proc compile(self: var Compiler, input: seq[Value]) =
  for i, v in input:
    self.compile(v)
    if i < input.len - 1:
      self.output.instructions.add(Instruction(kind: IkPop))

proc compile_literal(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))

proc compile_symbol(self: var Compiler, input: Value) =
  if self.quote_level > 0:
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))
  else:
    self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: input))

proc compile_complex_symbol(self: var Compiler, input: Value) =
  todo()
  # if self.quote_level > 0:
  #   self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))
  # else:
  #   var first = input.csymbol[0]
  #   if first == "":
  #     self.output.instructions.add(Instruction(kind: IkSelf))
  #   else:
  #     self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: first))
  #   for s in input.csymbol[1..^1]:
  #     let (is_int, i) = to_int(s)
  #     if is_int:
  #       self.output.instructions.add(Instruction(kind: IkGetChild, arg0: i))
  #     elif s.starts_with("."):
  #       self.output.instructions.add(Instruction(kind: IkCallMethodNoArgs, arg0: s[1..^1]))
  #     else:
  #       self.output.instructions.add(Instruction(kind: IkGetMember, arg0: s))

proc compile_array(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkArrayStart))
  for child in input.to_ref().arr:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkArrayAddChild))
  self.output.instructions.add(Instruction(kind: IkArrayEnd))

proc compile_map(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkMapStart))
  for k, v in input.to_ref().map:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkMapSetProp, arg0: k))
  self.output.instructions.add(Instruction(kind: IkMapEnd))

proc compile_do(self: var Compiler, input: Value) =
  self.compile(input.gene.children)

proc compile_if(self: var Compiler, input: Value) =
  todo()
  # normalize_if(input)
  # self.compile(input.gene_props[COND_KEY])
  # var elseLabel = new_id()
  # var endLabel = new_id()
  # self.output.instructions.add(Instruction(kind: IkJumpIfFalse, arg0: elseLabel))
  # self.compile(input.gene_props[THEN_KEY])
  # self.output.instructions.add(Instruction(kind: IkJump, arg0: endLabel))
  # self.output.instructions.add(Instruction(kind: IkNoop, label: elseLabel))
  # self.compile(input.gene_props[ELSE_KEY])
  # self.output.instructions.add(Instruction(kind: IkNoop, label: endLabel))

proc compile_var(self: var Compiler, input: Value) =
  todo()
  # let name = input.gene_children[0]
  # if input.gene_children.len > 1:
  #   self.compile(input.gene_children[1])
  #   self.output.instructions.add(Instruction(kind: IkVar, arg0: name))
  # else:
  #   self.output.instructions.add(Instruction(kind: IkVarValue, arg0: name, arg1: Value(kind: VkNil)))

proc compile_assignment(self: var Compiler, input: Value) =
  todo()
  # let `type` = input.gene_type
  # if `type`.kind == VkSymbol:
  #   self.compile(input.gene_children[1])
  #   self.output.instructions.add(Instruction(kind: IkAssign, arg0: `type`))
  # elif `type`.kind == VkComplexSymbol:
  #   if `type`.csymbol[0] == "":
  #     `type`.csymbol[0] = "self"
  #   if `type`.csymbol.len == 2:
  #     self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: `type`.csymbol[0]))
  #     self.compile(input.gene_children[1])
  #     self.output.instructions.add(Instruction(kind: IkSetMember, arg0: `type`.csymbol[1]))
  #   else:
  #     let arg0 = Value(kind: VkComplexSymbol, csymbol: `type`.csymbol[0..^2])
  #     self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: arg0))
  #     self.compile(input.gene_children[1])
  #     self.output.instructions.add(Instruction(kind: IkSetMember, arg0: `type`.csymbol[^1]))
  # else:
  #   not_allowed($`type`)

proc compile_loop(self: var Compiler, input: Value) =
  todo()
  # var label = new_id()
  # self.output.instructions.add(Instruction(kind: IkLoopStart, label: label))
  # self.compile(input.gene_children)
  # self.output.instructions.add(Instruction(kind: IkContinue, arg0: label))
  # self.output.instructions.add(Instruction(kind: IkLoopEnd, label: label))

proc compile_break(self: var Compiler, input: Value) =
  todo()
  # if input.gene_children.len > 0:
  #   self.compile(input.gene_children[0])
  # else:
  #   self.output.instructions.add(Instruction(kind: IkPushNil))
  # self.output.instructions.add(Instruction(kind: IkBreak))

proc compile_fn(self: var Compiler, input: Value) =
  todo()
  # self.output.instructions.add(Instruction(kind: IkFunction, arg0: input))

proc compile_return(self: var Compiler, input: Value) =
  todo()
  # if input.gene_children.len > 0:
  #   self.compile(input.gene_children[0])
  # else:
  #   self.output.instructions.add(Instruction(kind: IkPushNil))
  # self.output.instructions.add(Instruction(kind: IkReturn))

proc compile_macro(self: var Compiler, input: Value) =
  todo()
  # self.output.instructions.add(Instruction(kind: IkMacro, arg0: input))

proc compile_ns(self: var Compiler, input: Value) =
  todo()
  # self.output.instructions.add(Instruction(kind: IkNamespace, arg0: input.gene_children[0]))
  # if input.gene_children.len > 1:
  #   let body = new_gene_stream(input.gene_children[1..^1])
  #   self.output.instructions.add(Instruction(kind: IkPushValue, arg0: body))
  #   self.output.instructions.add(Instruction(kind: IkCompileInit))
  #   self.output.instructions.add(Instruction(kind: IkCallInit))

proc compile_class(self: var Compiler, input: Value) =
  todo()
  # var body_start = 1
  # if input.gene_children.len >= 3 and input.gene_children[1].is_symbol("<"):
  #   body_start = 3
  #   self.compile(input.gene_children[2])
  #   self.output.instructions.add(Instruction(kind: IkSubClass, arg0: input.gene_children[0]))
  # else:
  #   self.output.instructions.add(Instruction(kind: IkClass, arg0: input.gene_children[0]))

  # if input.gene_children.len > body_start:
  #   let body = new_gene_stream(input.gene_children[body_start..^1])
  #   self.output.instructions.add(Instruction(kind: IkPushValue, arg0: body))
  #   self.output.instructions.add(Instruction(kind: IkCompileInit))
  #   self.output.instructions.add(Instruction(kind: IkCallInit))

# Construct a Gene object whose type is the class
# The Gene object will be used as the arguments to the constructor
proc compile_new(self: var Compiler, input: Value) =
  todo()
  # self.output.instructions.add(Instruction(kind: IkGeneStart))
  # self.compile(input.gene_children[0])
  # self.output.instructions.add(Instruction(kind: IkGeneSetType))
  # # TODO: compile the arguments
  # self.output.instructions.add(Instruction(kind: IkGeneEnd))
  # self.output.instructions.add(Instruction(kind: IkNew))

proc compile_gene_default(self: var Compiler, input: Value) {.inline.} =
  todo()
  # self.output.instructions.add(Instruction(kind: IkGeneStart))
  # self.compile(input.gene_type)
  # self.output.instructions.add(Instruction(kind: IkGeneSetType))
  # for k, v in input.gene_props:
  #   self.compile(v)
  #   self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  # for child in input.gene_children:
  #   self.compile(child)
  #   self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  # self.output.instructions.add(Instruction(kind: IkGeneEnd))

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
proc compile_gene_unknown(self: var Compiler, input: Value) {.inline.} =
  todo()
  # self.compile(input.gene_type)
  # let fn_label = new_id()
  # let end_label = new_id()
  # self.output.instructions.add(
  #   Instruction(
  #     kind: IkGeneCheckType,
  #     arg0: Value(kind: VkCuId, cu_id: fn_label),
  #     arg1: Value(kind: VkCuId, cu_id: end_label),
  #   )
  # )

  # self.output.instructions.add(Instruction(kind: IkGeneStartMacro))
  # self.quote_level.inc()
  # for k, v in input.gene_props:
  #   self.compile(v)
  #   self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  # for child in input.gene_children:
  #   self.compile(child)
  #   self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  # self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label))
  # self.quote_level.dec()

  # self.output.instructions.add(Instruction(kind: IkGeneStartDefault, label: fn_label))
  # for k, v in input.gene_props:
  #   self.compile(v)
  #   self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  # for child in input.gene_children:
  #   self.compile(child)
  #   self.output.instructions.add(Instruction(kind: IkGeneAddChild))

  # self.output.instructions.add(Instruction(kind: IkGeneEnd, label: end_label))

# TODO: handle special cases:
# 1. No arguments
# 2. All arguments are primitives or array/map of primitives
#
# self, method_name, arguments
# self + method_name => bounded_method_object (is composed of self, class, method_object(is composed of name, logic))
# (bounded_method_object ...arguments)
proc compile_method_call(self: var Compiler, input: Value) {.inline.} =
  todo()
  # if input.gene_type.kind == VkSymbol and input.gene_type.str.starts_with("."):
  #   self.output.instructions.add(Instruction(kind: IkSelf))
  #   self.output.instructions.add(Instruction(kind: IkResolveMethod, arg0: input.gene_type.str[1..^1]))
  # else:
  #   self.compile(input.gene_type)
  #   let first = input.gene_children[0]
  #   input.gene_children.delete(0)
  #   self.output.instructions.add(Instruction(kind: IkResolveMethod, arg0: first.str[1..^1]))

  # let fn_label = new_id()
  # let end_label = new_id()
  # self.output.instructions.add(
  #   Instruction(
  #     kind: IkGeneCheckType,
  #     arg0: Value(kind: VkCuId, cu_id: fn_label),
  #     arg1: Value(kind: VkCuId, cu_id: end_label),
  #   )
  # )

  # self.output.instructions.add(Instruction(kind: IkGeneStartMacroMethod))
  # self.quote_level.inc()
  # for k, v in input.gene_props:
  #   self.compile(v)
  #   self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  # for child in input.gene_children:
  #   self.compile(child)
  #   self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  # self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label))
  # self.quote_level.dec()

  # self.output.instructions.add(Instruction(kind: IkGeneStartMethod, label: fn_label))
  # for k, v in input.gene_props:
  #   self.compile(v)
  #   self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  # for child in input.gene_children:
  #   self.compile(child)
  #   self.output.instructions.add(Instruction(kind: IkGeneAddChild))

  # self.output.instructions.add(Instruction(kind: IkGeneEnd, label: end_label))

proc compile_gene(self: var Compiler, input: Value) =
  todo()
  # if self.quote_level > 0 or input.gene_type.is_symbol("_") or input.gene_type.kind == VkQuote:
  #   self.compile_gene_default(input)
  #   return

  # let `type` = input.gene_type
  # if input.gene_children.len > 0:
  #   var first = input.gene_children[0]
  #   if first.kind == VkSymbol:
  #     case first.str:
  #       of "=":
  #         self.compile_assignment(input)
  #         return
  #       of "+":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkAdd))
  #         return
  #       of "-":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkSub))
  #         return
  #       of "*":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkMul))
  #         return
  #       of "/":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkDiv))
  #         return
  #       of "<":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkLt))
  #         return
  #       of "<=":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkLe))
  #         return
  #       of ">":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkGt))
  #         return
  #       of ">=":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkGe))
  #         return
  #       of "==":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkEq))
  #         return
  #       of "!=":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkNe))
  #         return
  #       of "&&":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkAnd))
  #         return
  #       of "||":
  #         self.compile(`type`)
  #         self.compile(input.gene_children[1])
  #         self.output.instructions.add(Instruction(kind: IkOr))
  #         return
  #       else:
  #         if first.str.starts_with("."):
  #           self.compile_method_call(input)
  #           return

  # if `type`.kind == VkSymbol:
  #   case `type`.str:
  #     of "do":
  #       self.compile_do(input)
  #       return
  #     of "if":
  #       self.compile_if(input)
  #       return
  #     of "var":
  #       self.compile_var(input)
  #       return
  #     of "loop":
  #       self.compile_loop(input)
  #       return
  #     of "break":
  #       self.compile_break(input)
  #       return
  #     of "fn", "fnx":
  #       self.compile_fn(input)
  #       return
  #     of "macro":
  #       self.compile_macro(input)
  #       return
  #     of "return":
  #       self.compile_return(input)
  #       return
  #     of "ns":
  #       self.compile_ns(input)
  #       return
  #     of "class":
  #       self.compile_class(input)
  #       return
  #     of "new":
  #       self.compile_new(input)
  #       return
  #     else:
  #       let s = `type`.str
  #       if s.starts_with("."):
  #         self.compile_method_call(input)
  #         return
  #       elif s.starts_with("$_"):
  #         if input.gene_children.len > 1:
  #           not_allowed($input)
  #         elif input.gene_children.len == 1:
  #           self.compile(input.gene_children[0])
  #           self.output.instructions.add(Instruction(kind: IkInternal, arg0: `type`, arg1: true))
  #         else:
  #           self.output.instructions.add(Instruction(kind: IkInternal, arg0: `type`))
  #         return

  # self.compile_gene_unknown(input)

proc compile(self: var Compiler, input: Value) =
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
      self.compile(input.to_ref.quote)
      self.quote_level.dec()
    of VkStream:
      self.compile(input.to_ref.stream)
    of VkArray:
      self.compile_array(input)
    of VkMap:
      self.compile_map(input)
    of VkGene:
      self.compile_gene(input)
    else:
      todo($input.kind)

proc compile*(input: seq[Value]): CompilationUnit =
  var self = Compiler(output: CompilationUnit(id: new_id()))
  self.output.instructions.add(Instruction(kind: IkStart))

  for i, v in input:
    self.compile(v)
    if i < input.len - 1:
      self.output.instructions.add(Instruction(kind: IkPop))

  self.output.instructions.add(Instruction(kind: IkEnd))
  result = self.output

proc compile*(f: var Function) =
  if f.body_compiled != nil:
    return

  var self = Compiler(output: CompilationUnit(id: new_id()))
  self.output.instructions.add(Instruction(kind: IkStart))

  # generate code for arguments
  for m in f.matcher.children:
    let label = new_id()
    self.output.instructions.add(Instruction(
      kind: IkJumpIfMatchSuccess,
      arg0: m.name,
      arg1: label.Value,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.output.instructions.add(Instruction(kind: IkVar, arg0: m.name))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(f.body)
  self.output.instructions.add(Instruction(kind: IkEnd))
  f.body_compiled = self.output
  f.body_compiled.matcher = f.matcher

proc compile*(m: var Macro) =
  if m.body_compiled != nil:
    return

  m.body_compiled = compile(m.body)
  m.body_compiled.matcher = m.matcher

proc compile_init*(input: Value): CompilationUnit =
  var self = Compiler(output: CompilationUnit(id: new_id()))
  self.output.skip_return = true
  self.output.instructions.add(Instruction(kind: IkStart))

  self.compile(input)

  self.output.instructions.add(Instruction(kind: IkEnd))
  result = self.output
