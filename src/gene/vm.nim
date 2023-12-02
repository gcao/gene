import tables, strutils, strformat

import ./types
import ./parser
import ./compiler

proc handle_args*(self: VirtualMachine, matcher: RootMatcher, args: Value) {.inline.} =
  case matcher.hint.mode:
    of MhNone:
      discard
    of MhSimpleData:
      var match_result = MatchResult()
      for i, value in args.gene.children:
        let field = matcher.children[i]
        match_result.fields[field.name.to_key()] = MatchedField(
          kind: MfSuccess,
          matcher: field,
          value: value,
        )
        self.frame.scope.def_member(field.name.to_key(), value)
      for m in matcher.children:
        if not match_result.fields.has_key(m.name.to_key()):
          match_result.fields[m.name.to_key()] = MatchedField(
            kind: MfMissing,
            matcher: m,
          )
      self.frame.match_result = match_result
    else:
      todo($matcher.hint.mode)

# proc print_stack(self: VirtualMachine) =
#   var s = "Stack: "
#   for i, reg in self.frame.stack:
#     if i > 0:
#       s &= ", "
#     if i == self.frame.stack_index.int:
#       s &= "=> "
#     s &= $self.frame.stack[i]
#   echo s

proc exec*(self: VirtualMachine): Value =
  self.state = VmRunning
  var indent = ""

  App.app.gene_ns.ns["_trace_start".to_key()] = proc(vm_data: VirtualMachine, args: Value): Value =
    self.trace = true
    self.frame.push(NIL)

  while true:
    let inst = self.cur_block[self.pc]
    if inst.kind == IkStart:
      indent &= "  "
    if self.trace:
      # self.print_stack()
      echo fmt"{indent}{self.pc:03} {inst}"
    case inst.kind:
      of IkNoop:
        discard

      of IkStart:
        let matcher = self.cur_block.matcher
        if matcher != nil:
          self.handle_args(matcher, self.frame.args)

      of IkEnd:
        indent.delete(indent.len-2..indent.len-1)
        let v = self.frame.default
        let caller = self.frame.caller
        if caller == nil:
          return v
        else:
          self.frame = caller.frame
          if not self.cur_block.skip_return:
            self.frame.push(v)
          self.cur_block = self.code_mgr.data[caller.address.id]
          self.pc = caller.address.pc
          continue

      of IkVar:
        let value = self.frame.pop()
        self.frame.scope.def_member(inst.arg0.int64, value)
        self.frame.push(value)

      of IkAssign:
        let value = self.frame.current()
        self.frame.scope[inst.arg0.int64] = value

      of IkResolveSymbol:
        case inst.arg0.str:
          of "_":
            self.frame.push(PLACEHOLDER)
          of "self":
            self.frame.push(self.frame.self)
          of "gene":
            self.frame.push(App.app.gene_ns)
          else:
            let scope = self.frame.scope
            let name = inst.arg0.int64
            if scope.has_key(name):
              self.frame.push(scope[name])
            elif self.frame.ns.has_key(name):
              self.frame.push(self.frame.ns[name])
            else:
              not_allowed("Unknown symbol " & name.get_symbol())

      of IkSelf:
        self.frame.push(self.frame.self)

      of IkSetMember:
        let name = inst.arg0.int64
        let value = self.frame.pop()
        var target = self.frame.pop()
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
        self.frame.push(value)

      of IkGetMember:
        let name = inst.arg0.int64
        let value = self.frame.pop()
        case value.kind:
          of VkMap:
            self.frame.push(value.ref.map[name])
          of VkGene:
            self.frame.push(value.gene.props[name])
          of VkNamespace:
            self.frame.push(value.ref.ns[name])
          of VkClass:
            self.frame.push(value.ref.class.ns[name])
          of VkInstance:
            self.frame.push(value.ref.instance_props[name])
          else:
            todo($value.kind)

      of IkGetChild:
        let i = inst.arg0.int
        let value = self.frame.pop()
        case value.kind:
          of VkArray:
            self.frame.push(value.ref.arr[i])
          of VkGene:
            self.frame.push(value.gene.children[i])
          else:
            todo($value.kind)

      of IkJump:
        self.pc = self.cur_block.find_label(inst.arg0.Label)
        continue
      of IkJumpIfFalse:
        if not self.frame.pop().to_bool():
          self.pc = self.cur_block.find_label(inst.arg0.Label)
          continue

      of IkJumpIfMatchSuccess:
        let mr = self.frame.match_result
        if mr.fields[inst.arg0.int64].kind == MfSuccess:
          self.pc = self.cur_block.find_label(inst.arg1.Label)
          continue

      of IkLoopStart, IkLoopEnd:
        discard

      of IkContinue:
        self.pc = self.cur_block.find_loop_start(self.pc)
        continue

      of IkBreak:
        self.pc = self.cur_block.find_loop_end(self.pc)
        continue

      of IkPushValue:
        self.frame.push(inst.arg0)
      of IkPushNil:
        self.frame.push(NIL)
      of IkPop:
        discard self.frame.pop()

      of IkArrayStart:
        self.frame.push(new_array_value())
      of IkArrayAddChild:
        let child = self.frame.pop()
        self.frame.current().ref.arr.add(child)
      of IkArrayEnd:
        discard

      of IkMapStart:
        self.frame.push(new_map_value())
      of IkMapSetProp:
        let key = inst.arg0.int64
        let val = self.frame.pop()
        self.frame.current().ref.map[key] = val
      of IkMapEnd:
        discard

      of IkGeneStart:
        self.frame.push(new_gene_value())
      of IkGeneStartDefault:
        let v = self.frame.pop()
        if v.kind == VkMacro:
          not_allowed("Macro not allowed here")
        self.frame.push(new_gene_value(v))
      of IkGeneStartMacro:
        let v = self.frame.pop()
        if v.kind != VkMacro:
          not_allowed("Macro expected")
        self.frame.push(new_gene_value(v))
      of IkGeneStartMethod:
        let v = self.frame.pop()
        # if v.kind != VkBoundMethod or v.bound_method.method.is_macro:
        #   not_allowed("Macro method not allowed here")
        self.frame.push(new_gene_value(v))
      of IkGeneStartMacroMethod:
        let v = self.frame.pop()
        # if v.kind != VkBoundMethod or not v.bound_method.method.is_macro:
        #   not_allowed("Macro method expected")
        self.frame.push(new_gene_value(v))
      of IkGeneCheckType:
        let v = self.frame.current()
        case v.kind:
          of VkFunction:
            self.pc = self.cur_block.find_label(inst.arg0.Label)
            # TODO: delete macro-related instructions
            continue
          of VkMacro:
            # TODO: delete non-macro-related instructions
            discard
          of VkBoundMethod:
            if not v.ref.bound_method.method.is_macro:
              self.pc = self.cur_block.find_label(inst.arg0.Label)
              # TODO: delete non-macro-related instructions
              continue
          of VkNativeFn, VkNativeFn2:
            self.pc = self.cur_block.find_label(inst.arg0.Label)
            continue
          else:
            todo($v.kind)

      of IkGeneSetType:
        let val = self.frame.pop()
        self.frame.current().gene.type = val
      of IkGeneSetProp:
        let key = inst.arg0.int64
        let val = self.frame.pop()
        self.frame.current().gene.props[key] = val
      of IkGeneAddChild:
        let child = self.frame.pop()
        self.frame.current().gene.children.add(child)

      of IkGeneEnd:
        let v = self.frame.current()
        let gene_type = v.gene.type
        if gene_type != nil:
          case gene_type.kind:
            of VkFunction:
              self.pc.inc()
              discard self.frame.pop()

              gene_type.ref.fn.compile()
              self.code_mgr.data[gene_type.ref.fn.body_compiled.id] = gene_type.ref.fn.body_compiled

              var caller = Caller(
                address: Address(id: self.cur_block.id, pc: self.pc),
                frame: self.frame,
              )
              self.frame = new_frame(caller)
              self.frame.scope.set_parent(gene_type.ref.fn.parent_scope, gene_type.ref.fn.parent_scope_max)
              self.frame.ns = gene_type.ref.fn.ns
              self.frame.args = v
              self.cur_block = gene_type.ref.fn.body_compiled
              self.pc = 0
              continue

            of VkMacro:
              self.pc.inc()
              discard self.frame.pop()

              gene_type.ref.macro.compile()
              self.code_mgr.data[gene_type.ref.macro.body_compiled.id] = gene_type.ref.macro.body_compiled

              var caller = Caller(
                address: Address(id: self.cur_block.id, pc: self.pc),
                frame: self.frame,
              )
              self.frame = new_frame(caller)
              self.frame.scope.set_parent(gene_type.ref.macro.parent_scope, gene_type.ref.macro.parent_scope_max)
              self.frame.ns = gene_type.ref.macro.ns
              self.frame.args = v
              self.cur_block = gene_type.ref.macro.body_compiled
              self.pc = 0
              continue

            of VkClass:
              todo($v)

            of VkBoundMethod:
              discard self.frame.pop()

              let meth = gene_type.ref.bound_method.method
              case meth.callable.kind:
                of VkNativeFn:
                  self.frame.push(meth.callable.ref.native_fn(self, v))
                of VkFunction:
                  self.pc.inc()

                  var fn = meth.callable.ref.fn
                  fn.compile()
                  self.code_mgr.data[fn.body_compiled.id] = fn.body_compiled

                  var caller = Caller(
                    address: Address(id: self.cur_block.id, pc: self.pc),
                    frame: self.frame,
                  )
                  self.frame = new_frame(caller)
                  self.frame.scope.set_parent(fn.parent_scope, fn.parent_scope_max)
                  self.frame.ns = fn.ns
                  self.frame.self = gene_type.ref.bound_method.self
                  self.frame.args = v
                  self.cur_block = fn.body_compiled
                  self.pc = 0
                  continue
                else:
                  todo("Bound method: " & $meth.callable.kind)

            else:
              discard

      of IkAdd:
        self.frame.push(self.frame.pop().int + self.frame.pop().int)

      of IkSub:
        self.frame.push(-self.frame.pop().int + self.frame.pop().int)

      of IkMul:
        self.frame.push(self.frame.pop().int * self.frame.pop().int)

      of IkDiv:
        let second = self.frame.pop().int
        let first = self.frame.pop().int
        self.frame.push(first / second)

      of IkLt:
        let second = self.frame.pop().int
        let first = self.frame.pop().int
        self.frame.push(first < second)

      of IkLe:
        let second = self.frame.pop().int
        let first = self.frame.pop().int
        self.frame.push(first <= second)

      of IkGt:
        let second = self.frame.pop().int
        let first = self.frame.pop().int
        self.frame.push(first > second)

      of IkGe:
        let second = self.frame.pop().int
        let first = self.frame.pop().int
        self.frame.push(first >= second)

      of IkEq:
        let second = self.frame.pop().int
        let first = self.frame.pop().int
        self.frame.push(first == second)

      of IkNe:
        let second = self.frame.pop().int
        let first = self.frame.pop().int
        self.frame.push(first != second)

      of IkAnd:
        let second = self.frame.pop()
        let first = self.frame.pop()
        self.frame.push(first.to_bool and second.to_bool)

      of IkOr:
        let second = self.frame.pop()
        let first = self.frame.pop()
        self.frame.push(first.to_bool or second.to_bool)

      of IkCompileInit:
        let input = self.frame.pop()
        let compiled = compile_init(input)
        self.code_mgr.data[compiled.id] = compiled
        self.frame.push(compiled.id.Value)

      of IkCallInit:
        let id = self.frame.pop().Id
        let compiled = self.code_mgr.data[id]
        let obj = self.frame.current()
        var ns: Namespace
        case obj.kind:
          of VkNamespace:
            ns = obj.ref.ns
          of VkClass:
            ns = obj.ref.class.ns
          else:
            todo($obj.kind)

        self.pc.inc()
        var caller = Caller(
          address: Address(id: self.cur_block.id, pc: self.pc),
          frame: self.frame,
        )
        self.frame = new_frame(caller)
        self.frame.self = obj
        self.frame.ns = ns
        self.cur_block = compiled
        self.pc = 0
        continue

      of IkFunction:
        var f = to_function(inst.arg0)
        f.ns = self.frame.ns
        let r = new_ref(VkFunction)
        r.fn = f
        let v = r.to_ref_value()
        f.ns[f.name.to_key()] = v
        f.parent_scope = self.frame.scope
        f.parent_scope_max = self.frame.scope.max
        self.frame.push(v)

      of IkMacro:
        var m = to_macro(inst.arg0)
        m.ns = self.frame.ns
        let r = new_ref(VkMacro)
        r.macro = m
        var v = r.to_ref_value()
        m.ns[m.name.to_key()] = v
        self.frame.push(v)

      of IkReturn:
        let caller = self.frame.caller
        if caller == nil:
          not_allowed("Return from top level")
        else:
          let v = self.frame.pop()
          self.frame = caller.frame
          self.cur_block = self.code_mgr.data[caller.address.id]
          self.pc = caller.address.pc
          self.frame.push(v)
          continue

      of IkNamespace:
        var name = inst.arg0
        var ns = new_namespace(name.str)
        let r = new_ref(VkNamespace)
        r.ns = ns
        var v = r.to_ref_value()
        self.frame.ns[name.int64] = v
        self.frame.push(v)

      of IkClass:
        var name = inst.arg0
        var class = new_class(name.str)
        let r = new_ref(VkClass)
        r.class = class
        var v = r.to_ref_value()
        self.frame.ns[name.int64] = v
        self.frame.push(v)

      of IkNew:
        var v = self.frame.pop()
        var instance = new_ref(VkInstance)
        instance.instance_class = v.gene.type.ref.class
        self.frame.push(instance.to_ref_value())

        let class = instance.instance_class
        case class.constructor.kind:
          of VkFunction:
            class.constructor.ref.fn.compile()
            let compiled = class.constructor.ref.fn.body_compiled
            compiled.skip_return = true

            self.pc.inc()
            var caller = Caller(
              address: Address(id: self.cur_block.id, pc: self.pc),
              frame: self.frame,
            )
            self.frame = new_frame(caller)
            self.frame.self = instance.to_ref_value()
            self.frame.ns = class.constructor.ref.fn.ns
            self.cur_block = compiled
            self.pc = 0
            continue
          of VkNil:
            discard
          else:
            todo($class.constructor.kind)

      of IkSubClass:
        var name = inst.arg0
        var class = new_class(name.str)
        class.parent = self.frame.pop().ref.class
        let r = new_ref(VkClass)
        r.class = class
        self.frame.ns[name.int64] = r.to_ref_value()
        self.frame.push(r.to_ref_value())

      of IkResolveMethod:
        var v = self.frame.pop()
        let class = v.get_class()
        let meth = class.get_method(inst.arg0.str)
        let r = new_ref(VkBoundMethod)
        r.bound_method = BoundMethod(
          self: v,
          # class: class,
          `method`: meth,
        )
        self.frame.push(r.to_ref_value())

      of IkCallMethodNoArgs:
        let v = self.frame.pop()

        let class = v.get_class()
        let meth = class.get_method(inst.arg0.str)
        case meth.callable.kind:
          of VkNativeFn:
            self.frame.push(meth.callable.ref.native_fn(self, v))
          of VkFunction:
            self.pc.inc()

            var fn = meth.callable.ref.fn
            fn.compile()
            self.code_mgr.data[fn.body_compiled.id] = fn.body_compiled

            var caller = Caller(
              address: Address(id: self.cur_block.id, pc: self.pc),
              frame: self.frame,
            )
            self.frame = new_frame(caller)
            self.frame.scope.set_parent(fn.parent_scope, fn.parent_scope_max)
            self.frame.ns = fn.ns
            self.frame.self = v
            self.cur_block = fn.body_compiled
            self.pc = 0
            continue
          else:
            todo("CallMethodNoArgs: " & $meth.callable.kind)

      # of IkInternal:
      #   case inst.arg0.str:
      #     of "$_trace_start":
      #       self.trace = true
      #       self.frame.push(NIL)
      #     of "$_trace_end":
      #       self.trace = false
      #       self.frame.push(NIL)
      #     of "$_debug":
      #       if inst.arg1:
      #         echo "$_debug ", self.frame.current()
      #       else:
      #         self.frame.push(NIL)
      #     of "$_print_instructions":
      #       echo self.cur_block
      #       if inst.arg1:
      #         discard self.frame.pop()
      #       self.frame.push(NIL)
      #     of "$_print_stack":
      #       self.print_stack()
      #       self.frame.push(NIL)
      #     else:
      #       todo(inst.arg0.str)

      else:
        todo($inst.kind)

    self.pc.inc
    if self.pc >= self.cur_block.len:
      break

proc exec*(self: VirtualMachine, code: string, module_name: string): Value =
  let compiled = compile(read_all(code))

  var ns = new_namespace(module_name)
  self.frame = new_frame(ns)
  self.code_mgr.data[compiled.id] = compiled
  self.cur_block = compiled

  self.exec()

include "./vm/core"
