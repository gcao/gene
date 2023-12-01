import tables, strutils, strformat

import ./types
import ./parser
import ./compiler

const REG_DEFAULT = 6

proc init_app_and_vm*() =
  VM = VirtualMachine(
    state: VmWaiting,
  )
  let r = new_ref(VkApplication)
  r.app = new_app()
  r.app.global_ns = new_namespace("global").to_value()
  r.app.gene_ns   = new_namespace("gene"  ).to_value()
  r.app.genex_ns  = new_namespace("gene"  ).to_value()
  App = r.to_ref_value()

  for callback in VmCreatedCallbacks:
    callback()

proc new_frame(): Frame =
  Frame(
    stack_index: REG_DEFAULT,
  )

proc new_frame(ns: Namespace): Frame =
  result = new_frame()
  result.ns = ns
  result.scope = new_scope()

proc new_frame(caller: Caller): Frame =
  result = new_frame()
  result.caller = caller
  result.scope = new_scope()

proc current(self: var Frame): Value =
  self.stack[self.stack_index - 1]

proc push(self: var Frame, value: Value) =
  self.stack[self.stack_index] = value
  self.stack_index.inc()

proc pop(self: var Frame): Value =
  self.stack_index.dec()
  result = self.stack[self.stack_index]
  self.stack[self.stack_index] = nil

proc default(self: Frame): Value =
  self.stack[REG_DEFAULT]

proc new_vm_data*(ns: Namespace): VirtualMachineData =
  result = VirtualMachineData(
    frame: new_frame(ns),
    code_mgr: CodeManager(),
  )

proc parse*(self: var RootMatcher, v: Value)

proc calc_next*(self: var Matcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_next*(self: var RootMatcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_min_left*(self: var Matcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1

proc calc_min_left*(self: var RootMatcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1

proc parse(self: var RootMatcher, group: var seq[Matcher], v: Value) =
  case v.kind:
    of VkSymbol:
      if v.str[0] == '^':
        var m = new_matcher(self, MatchProp)
        if v.str.ends_with("..."):
          m.is_splat = true
          if v.str[1] == '^':
            m.name = v.str[2..^4]
            m.is_prop = true
          else:
            m.name = v.str[1..^4]
        else:
          if v.str[1] == '^':
            m.name = v.str[2..^1]
            m.is_prop = true
          else:
            m.name = v.str[1..^1]
        group.add(m)
      else:
        var m = new_matcher(self, MatchData)
        group.add(m)
        if v.str != "_":
          if v.str.ends_with("..."):
            m.is_splat = true
            if v.str[0] == '^':
              m.name = v.str[1..^4]
              m.is_prop = true
            else:
              m.name = v.str[0..^4]
          else:
            if v.str[0] == '^':
              m.name = v.str[1..^1]
              m.is_prop = true
            else:
              m.name = v.str
    of VkComplexSymbol:
      todo($VkComplexSymbol)
      # if v.csymbol[0] == '^':
      #   todo("parse " & $v)
      # else:
      #   var m = new_matcher(self, MatchData)
      #   group.add(m)
      #   m.is_prop = true
      #   var name = v.csymbol[1]
      #   if name.ends_with("..."):
      #     m.is_splat = true
      #     m.name = name[0..^4]
      #   else:
      #     m.name = name
    of VkArray:
      var i = 0
      while i < v.ref.arr.len:
        var item = v.ref.arr[i]
        i += 1
        if item.kind == VkArray:
          var m = new_matcher(self, MatchData)
          group.add(m)
          self.parse(m.children, item)
        else:
          self.parse(group, item)
          if i < v.ref.arr.len and v.ref.arr[i] == "=".to_symbol_value():
            i += 1
            var last_matcher = group[^1]
            var value = v.ref.arr[i]
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

proc parse*(self: var RootMatcher, v: Value) =
  if v == nil or v == to_symbol_value("_"):
    return
  self.parse(self.children, v)
  self.calc_min_left()
  self.calc_next()

proc new_arg_matcher*(value: Value): RootMatcher =
  result = new_arg_matcher()
  result.parse(value)

proc to_function*(node: Value): Function {.gcsafe.} =
  var name: string
  var matcher = new_arg_matcher()
  var body_start: int
  if node.gene.type == "fnx".to_symbol_value():
    matcher.parse(node.gene.children[0])
    name = "<unnamed>"
    body_start = 1
  elif node.gene.type == "fnxx".to_symbol_value():
    name = "<unnamed>"
    body_start = 0
  else:
    var first = node.gene.children[0]
    case first.kind:
      of VkSymbol, VkString:
        name = first.str
      of VkComplexSymbol:
        name = first.ref.csymbol[^1]
      else:
        todo($first.kind)

    matcher.parse(node.gene.children[1])
    body_start = 2

  var body: seq[Value] = @[]
  for i in body_start..<node.gene.children.len:
    body.add node.gene.children[i]

  # body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  result.async = node.gene.props.get_or_default("async", false)

proc to_macro(node: Value): Macro =
  var first = node.gene.children[0]
  var name: string
  if first.kind == VkSymbol:
    name = first.str
  elif first.kind == VkComplexSymbol:
    name = first.ref.csymbol[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene.children[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene.children.len:
    body.add node.gene.children[i]

  # body = wrap_with_try(body)
  result = new_macro(name, matcher, body)

proc handle_args*(self: VirtualMachine, matcher: RootMatcher, args: Value) {.inline.} =
  case matcher.hint.mode:
    of MhNone:
      discard
    of MhSimpleData:
      var match_result = MatchResult()
      for i, value in args.gene.children:
        let field = matcher.children[i]
        match_result.fields[field.name] = MatchedField(
          kind: MfSuccess,
          matcher: field,
          value: value,
        )
        self.data.frame.scope.def_member(field.name, value)
      for m in matcher.children:
        if not match_result.fields.has_key(m.name):
          match_result.fields[m.name] = MatchedField(
            kind: MfMissing,
            matcher: m,
          )
      self.data.frame.match_result = match_result
    else:
      todo($matcher.hint.mode)

proc print_frame(self: VirtualMachine) =
  var s = "Frame "
  for i, reg in self.data.frame.stack:
    if i > 0:
      s &= ", "
    if i == self.data.frame.stack_index.int:
      s &= "=> "
    s &= $self.data.frame.stack[i]
  echo s

proc exec*(self: VirtualMachine): Value =
  var indent = ""

  App.app.gene_ns.ns["_trace_start"] = proc(vm_data: VirtualMachineData, args: Value): Value =
    self.trace = true
    self.data.frame.push(NIL)

  while true:
    let inst = self.data.cur_block[self.data.pc]
    if inst.kind == IkStart:
      indent &= "  "
    if self.trace:
      # self.print_frame()
      echo fmt"{indent}{self.data.pc:03} {inst}"
    case inst.kind:
      of IkNoop:
        discard

      of IkStart:
        let matcher = self.data.cur_block.matcher
        if matcher != nil:
          self.handle_args(matcher, self.data.frame.args)

      of IkEnd:
        indent.delete(indent.len-2..indent.len-1)
        let v = self.data.frame.default
        let caller = self.data.frame.caller
        if caller == nil:
          return v
        else:
          self.data.frame = caller.frame
          if not self.data.cur_block.skip_return:
            self.data.frame.push(v)
          self.data.cur_block = self.data.code_mgr.data[caller.address.id]
          self.data.pc = caller.address.pc
          continue

      of IkVar:
        let value = self.data.frame.pop()
        self.data.frame.scope.def_member(inst.arg0.str, value)
        self.data.frame.push(value)

      of IkAssign:
        let value = self.data.frame.current()
        self.data.frame.scope[inst.arg0.str] = value

      of IkResolveSymbol:
        case inst.arg0.str:
          of "_":
            self.data.frame.push(PLACEHOLDER)
          of "self":
            self.data.frame.push(self.data.frame.self)
          of "gene":
            self.data.frame.push(App.app.gene_ns)
          else:
            let scope = self.data.frame.scope
            let name = inst.arg0.str
            if scope.has_key(name):
              self.data.frame.push(scope[name])
            elif self.data.frame.ns.has_key(name):
              self.data.frame.push(self.data.frame.ns[name])
            else:
              not_allowed("Unknown symbol " & name)

      of IkSelf:
        self.data.frame.push(self.data.frame.self)

      of IkSetMember:
        let name = inst.arg0.str
        let value = self.data.frame.pop()
        var target = self.data.frame.pop()
        case target.kind:
          of VkMap:
            target.ref.map[name] = value
          of VkGene:
            target.gene.props[name] = value
          of VkNamespace:
            target.ref.ns[name] = value
          of VkClass:
            target.ref.class.ns[name] = value
          of VkInstance:
            target.ref.instance_props[name] = value
          else:
            todo($target.kind)
        self.data.frame.push(value)

      of IkGetMember:
        let name = inst.arg0.str
        let value = self.data.frame.pop()
        case value.kind:
          of VkMap:
            self.data.frame.push(value.ref.map[name])
          of VkGene:
            self.data.frame.push(value.gene.props[name])
          of VkNamespace:
            self.data.frame.push(value.ref.ns[name])
          of VkClass:
            self.data.frame.push(value.ref.class.ns[name])
          of VkInstance:
            self.data.frame.push(value.ref.instance_props[name])
          else:
            todo($value.kind)

      of IkGetChild:
        let i = inst.arg0.int
        let value = self.data.frame.pop()
        case value.kind:
          of VkArray:
            self.data.frame.push(value.ref.arr[i])
          of VkGene:
            self.data.frame.push(value.gene.children[i])
          else:
            todo($value.kind)

      of IkJump:
        self.data.pc = self.data.cur_block.find_label(inst.arg0.Label)
        continue
      of IkJumpIfFalse:
        if not self.data.frame.pop().to_bool():
          self.data.pc = self.data.cur_block.find_label(inst.arg0.Label)
          continue

      of IkJumpIfMatchSuccess:
        let mr = self.data.frame.match_result
        if mr.fields[inst.arg0.str].kind == MfSuccess:
          self.data.pc = self.data.cur_block.find_label(inst.arg1.Label)
          continue

      of IkLoopStart, IkLoopEnd:
        discard

      of IkContinue:
        self.data.pc = self.data.cur_block.find_loop_start(self.data.pc)
        continue

      of IkBreak:
        self.data.pc = self.data.cur_block.find_loop_end(self.data.pc)
        continue

      of IkPushValue:
        self.data.frame.push(inst.arg0)
      of IkPushNil:
        self.data.frame.push(NIL)
      of IkPop:
        discard self.data.frame.pop()

      of IkArrayStart:
        self.data.frame.push(new_array_value())
      of IkArrayAddChild:
        let child = self.data.frame.pop()
        self.data.frame.current().ref.arr.add(child)
      of IkArrayEnd:
        discard

      of IkMapStart:
        self.data.frame.push(new_map_value())
      of IkMapSetProp:
        let key = inst.arg0.str
        let val = self.data.frame.pop()
        self.data.frame.current().ref.map[key] = val
      of IkMapEnd:
        discard

      of IkGeneStart:
        self.data.frame.push(new_gene_value())
      of IkGeneStartDefault:
        let v = self.data.frame.pop()
        if v.kind == VkMacro:
          not_allowed("Macro not allowed here")
        self.data.frame.push(new_gene_value(v))
      of IkGeneStartMacro:
        let v = self.data.frame.pop()
        if v.kind != VkMacro:
          not_allowed("Macro expected")
        self.data.frame.push(new_gene_value(v))
      of IkGeneStartMethod:
        let v = self.data.frame.pop()
        # if v.kind != VkBoundMethod or v.bound_method.method.is_macro:
        #   not_allowed("Macro method not allowed here")
        self.data.frame.push(new_gene_value(v))
      of IkGeneStartMacroMethod:
        let v = self.data.frame.pop()
        # if v.kind != VkBoundMethod or not v.bound_method.method.is_macro:
        #   not_allowed("Macro method expected")
        self.data.frame.push(new_gene_value(v))
      of IkGeneCheckType:
        let v = self.data.frame.current()
        case v.kind:
          of VkFunction:
            self.data.pc = self.data.cur_block.find_label(inst.arg0.Label)
            # TODO: delete macro-related instructions
            continue
          of VkMacro:
            # TODO: delete non-macro-related instructions
            discard
          of VkBoundMethod:
            if not v.ref.bound_method.method.is_macro:
              self.data.pc = self.data.cur_block.find_label(inst.arg0.Label)
              # TODO: delete non-macro-related instructions
              continue
          of VkNativeFn, VkNativeFn2:
            self.data.pc = self.data.cur_block.find_label(inst.arg0.Label)
            continue
          else:
            todo($v.kind)

      of IkGeneSetType:
        let val = self.data.frame.pop()
        self.data.frame.current().gene.type = val
      of IkGeneSetProp:
        let key = inst.arg0.str
        let val = self.data.frame.pop()
        self.data.frame.current().gene.props[key] = val
      of IkGeneAddChild:
        let child = self.data.frame.pop()
        self.data.frame.current().gene.children.add(child)

      of IkGeneEnd:
        let v = self.data.frame.current()
        let gene_type = v.gene.type
        if gene_type != nil:
          case gene_type.kind:
            of VkFunction:
              self.data.pc.inc()
              discard self.data.frame.pop()

              gene_type.ref.fn.compile()
              self.data.code_mgr.data[gene_type.ref.fn.body_compiled.id] = gene_type.ref.fn.body_compiled

              var caller = Caller(
                address: Address(id: self.data.cur_block.id, pc: self.data.pc),
                frame: self.data.frame,
              )
              self.data.frame = new_frame(caller)
              self.data.frame.scope.set_parent(gene_type.ref.fn.parent_scope, gene_type.ref.fn.parent_scope_max)
              self.data.frame.ns = gene_type.ref.fn.ns
              self.data.frame.args = v
              self.data.cur_block = gene_type.ref.fn.body_compiled
              self.data.pc = 0
              continue

            of VkMacro:
              self.data.pc.inc()
              discard self.data.frame.pop()

              gene_type.ref.macro.compile()
              self.data.code_mgr.data[gene_type.ref.macro.body_compiled.id] = gene_type.ref.macro.body_compiled

              var caller = Caller(
                address: Address(id: self.data.cur_block.id, pc: self.data.pc),
                frame: self.data.frame,
              )
              self.data.frame = new_frame(caller)
              self.data.frame.scope.set_parent(gene_type.ref.macro.parent_scope, gene_type.ref.macro.parent_scope_max)
              self.data.frame.ns = gene_type.ref.macro.ns
              self.data.frame.args = v
              self.data.cur_block = gene_type.ref.macro.body_compiled
              self.data.pc = 0
              continue

            of VkClass:
              todo($v)

            of VkBoundMethod:
              discard self.data.frame.pop()

              let meth = gene_type.ref.bound_method.method
              case meth.callable.kind:
                of VkNativeFn:
                  self.data.frame.push(meth.callable.ref.native_fn(self.data, v))
                of VkFunction:
                  self.data.pc.inc()

                  var fn = meth.callable.ref.fn
                  fn.compile()
                  self.data.code_mgr.data[fn.body_compiled.id] = fn.body_compiled

                  var caller = Caller(
                    address: Address(id: self.data.cur_block.id, pc: self.data.pc),
                    frame: self.data.frame,
                  )
                  self.data.frame = new_frame(caller)
                  self.data.frame.scope.set_parent(fn.parent_scope, fn.parent_scope_max)
                  self.data.frame.ns = fn.ns
                  self.data.frame.self = gene_type.ref.bound_method.self
                  self.data.frame.args = v
                  self.data.cur_block = fn.body_compiled
                  self.data.pc = 0
                  continue
                else:
                  todo("Bound method: " & $meth.callable.kind)

            else:
              discard

      of IkAdd:
        self.data.frame.push(self.data.frame.pop().int + self.data.frame.pop().int)

      of IkSub:
        self.data.frame.push(-self.data.frame.pop().int + self.data.frame.pop().int)

      of IkMul:
        self.data.frame.push(self.data.frame.pop().int * self.data.frame.pop().int)

      of IkDiv:
        let second = self.data.frame.pop().int
        let first = self.data.frame.pop().int
        self.data.frame.push(first / second)

      of IkLt:
        let second = self.data.frame.pop().int
        let first = self.data.frame.pop().int
        self.data.frame.push(first < second)

      of IkLe:
        let second = self.data.frame.pop().int
        let first = self.data.frame.pop().int
        self.data.frame.push(first <= second)

      of IkGt:
        let second = self.data.frame.pop().int
        let first = self.data.frame.pop().int
        self.data.frame.push(first > second)

      of IkGe:
        let second = self.data.frame.pop().int
        let first = self.data.frame.pop().int
        self.data.frame.push(first >= second)

      of IkEq:
        let second = self.data.frame.pop().int
        let first = self.data.frame.pop().int
        self.data.frame.push(first == second)

      of IkNe:
        let second = self.data.frame.pop().int
        let first = self.data.frame.pop().int
        self.data.frame.push(first != second)

      of IkAnd:
        let second = self.data.frame.pop()
        let first = self.data.frame.pop()
        self.data.frame.push(first.to_bool and second.to_bool)

      of IkOr:
        let second = self.data.frame.pop()
        let first = self.data.frame.pop()
        self.data.frame.push(first.to_bool or second.to_bool)

      of IkCompileInit:
        let input = self.data.frame.pop()
        let compiled = compile_init(input)
        self.data.code_mgr.data[compiled.id] = compiled
        self.data.frame.push(compiled.id.Value)

      of IkCallInit:
        let id = self.data.frame.pop().Id
        let compiled = self.data.code_mgr.data[id]
        let obj = self.data.frame.current()
        var ns: Namespace
        case obj.kind:
          of VkNamespace:
            ns = obj.ref.ns
          of VkClass:
            ns = obj.ref.class.ns
          else:
            todo($obj.kind)

        self.data.pc.inc()
        var caller = Caller(
          address: Address(id: self.data.cur_block.id, pc: self.data.pc),
          frame: self.data.frame,
        )
        self.data.frame = new_frame(caller)
        self.data.frame.self = obj
        self.data.frame.ns = ns
        self.data.cur_block = compiled
        self.data.pc = 0
        continue

      of IkFunction:
        var f = to_function(inst.arg0)
        f.ns = self.data.frame.ns
        let r = new_ref(VkFunction)
        r.fn = f
        let v = r.to_ref_value()
        f.ns[f.name] = v
        f.parent_scope = self.data.frame.scope
        f.parent_scope_max = self.data.frame.scope.max
        self.data.frame.push(v)

      of IkMacro:
        var m = to_macro(inst.arg0)
        m.ns = self.data.frame.ns
        let r = new_ref(VkMacro)
        r.macro = m
        var v = r.to_ref_value()
        m.ns[m.name] = v
        self.data.frame.push(v)

      of IkReturn:
        let caller = self.data.frame.caller
        if caller == nil:
          not_allowed("Return from top level")
        else:
          let v = self.data.frame.pop()
          self.data.frame = caller.frame
          self.data.cur_block = self.data.code_mgr.data[caller.address.id]
          self.data.pc = caller.address.pc
          self.data.frame.push(v)
          continue

      of IkNamespace:
        var name = inst.arg0.str
        var ns = new_namespace(name)
        let r = new_ref(VkNamespace)
        r.ns = ns
        var v = r.to_ref_value()
        self.data.frame.ns[name] = v
        self.data.frame.push(v)

      of IkClass:
        var name = inst.arg0.str
        var class = new_class(name)
        let r = new_ref(VkClass)
        r.class = class
        var v = r.to_ref_value()
        self.data.frame.ns[name] = v
        self.data.frame.push(v)

      of IkNew:
        var v = self.data.frame.pop()
        var instance = new_ref(VkInstance)
        instance.instance_class = v.gene.type.ref.class
        self.data.frame.push(instance.to_ref_value())

        let class = instance.instance_class
        case class.constructor.kind:
          of VkFunction:
            class.constructor.ref.fn.compile()
            let compiled = class.constructor.ref.fn.body_compiled
            compiled.skip_return = true

            self.data.pc.inc()
            var caller = Caller(
              address: Address(id: self.data.cur_block.id, pc: self.data.pc),
              frame: self.data.frame,
            )
            self.data.frame = new_frame(caller)
            self.data.frame.self = instance.to_ref_value()
            self.data.frame.ns = class.constructor.ref.fn.ns
            self.data.cur_block = compiled
            self.data.pc = 0
            continue
          of VkNil:
            discard
          else:
            todo($class.constructor.kind)

      of IkSubClass:
        var name = inst.arg0.str
        var class = new_class(name)
        class.parent = self.data.frame.pop().ref.class
        let r = new_ref(VkClass)
        r.class = class
        self.data.frame.ns[name] = r.to_ref_value()
        self.data.frame.push(r.to_ref_value())

      of IkResolveMethod:
        var v = self.data.frame.pop()
        let class = v.get_class()
        let meth = class.get_method(inst.arg0.str)
        let r = new_ref(VkBoundMethod)
        r.bound_method = BoundMethod(
          self: v,
          # class: class,
          `method`: meth,
        )
        self.data.frame.push(r.to_ref_value())

      of IkCallMethodNoArgs:
        let v = self.data.frame.pop()

        let class = v.get_class()
        let meth = class.get_method(inst.arg0.str)
        case meth.callable.kind:
          of VkNativeFn:
            self.data.frame.push(meth.callable.ref.native_fn(self.data, v))
          of VkFunction:
            self.data.pc.inc()

            var fn = meth.callable.ref.fn
            fn.compile()
            self.data.code_mgr.data[fn.body_compiled.id] = fn.body_compiled

            var caller = Caller(
              address: Address(id: self.data.cur_block.id, pc: self.data.pc),
              frame: self.data.frame,
            )
            self.data.frame = new_frame(caller)
            self.data.frame.scope.set_parent(fn.parent_scope, fn.parent_scope_max)
            self.data.frame.ns = fn.ns
            self.data.frame.self = v
            self.data.cur_block = fn.body_compiled
            self.data.pc = 0
            continue
          else:
            todo("CallMethodNoArgs: " & $meth.callable.kind)

      # of IkInternal:
      #   case inst.arg0.str:
      #     of "$_trace_start":
      #       self.trace = true
      #       self.data.frame.push(NIL)
      #     of "$_trace_end":
      #       self.trace = false
      #       self.data.frame.push(NIL)
      #     of "$_debug":
      #       if inst.arg1:
      #         echo "$_debug ", self.data.frame.current()
      #       else:
      #         self.data.frame.push(NIL)
      #     of "$_print_instructions":
      #       echo self.data.cur_block
      #       if inst.arg1:
      #         discard self.data.frame.pop()
      #       self.data.frame.push(NIL)
      #     of "$_print_frame":
      #       self.print_frame()
      #       self.data.frame.push(NIL)
      #     else:
      #       todo(inst.arg0.str)

      else:
        todo($inst.kind)

    self.data.pc.inc
    if self.data.pc >= self.data.cur_block.len:
      break

proc exec*(self: VirtualMachine, code: string, module_name: string): Value =
  let compiled = compile(read_all(code))

  var ns = new_namespace(module_name)
  var vm_data = new_vm_data(ns)
  vm_data.code_mgr.data[compiled.id] = compiled
  vm_data.cur_block = compiled

  self.data = vm_data
  self.exec()

include "./vm/core"
