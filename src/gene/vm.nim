import tables, strutils, strformat

import ./types
import ./parser
import ./compiler

# Important: not all push operation needs to be checked because many of
# them are often used in an expression. In those cases, add this check
# will only slow down the VM.
proc is_next_inst_pop(self: VirtualMachine): bool {.inline.} =
  {.push checks: off}
  result = self.cur_block.instructions[self.pc + 1].kind == IkPop
  {.pop.}

proc exec*(self: VirtualMachine): Value =
  self.state = VmRunning
  var indent = ""
  var inst: ptr Instruction

  while true:
    {.push checks: off}
    inst = self.cur_block.instructions[self.pc].addr
    {.pop.}
    if self.trace:
      if inst.kind == IkStart: # This is part of INDENT_LOGIC
        indent &= "  "
      # self.print_stack()
      echo fmt"{indent}{self.pc:03} {inst[]}"
    case inst.kind:
      of IkNoop:
        discard

      of IkStart:
        if not self.trace: # This is part of INDENT_LOGIC
          indent &= "  "
        if self.cur_block.matcher != nil:
          self.handle_args(self.cur_block.matcher, self.frame.args)

      of IkEnd:
        indent.delete(indent.len-2..indent.len-1)
        let v = self.frame.default
        let caller = self.frame.caller
        if caller == nil:
          return v
        else:
          self.frame.update(caller.frame)
          if not self.cur_block.skip_return:
            self.frame.push(v)
          self.cur_block = self.code_mgr.data[caller.address.id]
          self.pc = caller.address.pc
          continue

      of IkVar:
        self.frame.scope.members.add(self.frame.current())

      of IkVarResolve:
        {.push checks: off}
        self.frame.push(self.frame.scope.members[inst.arg0.int])
        {.pop.}

      of IkVarResolveInherited:
        var parent_index = inst.arg1.int32
        var scope = self.frame.scope
        while parent_index > 0:
          parent_index.dec()
          scope = scope.parent
        {.push checks: off}
        self.frame.push(scope.members[inst.arg0.int])
        {.pop.}

      of IkVarAssign:
        let value = self.frame.current()
        {.push checks: off}
        self.frame.scope.members[inst.arg0.int] = value
        {.pop.}

      of IkVarAssignInherited:
        let value = self.frame.current()
        var scope = self.frame.scope
        var parent_index = inst.arg1.int32
        while parent_index > 0:
          parent_index.dec()
          scope = scope.parent
        {.push checks: off}
        scope.members[inst.arg0.int] = value
        {.pop.}

      of IkAssign:
        todo($IkAssign)
        # let value = self.frame.current()
        # Find the namespace where the member is defined and assign it there

      of IkResolveSymbol:
        case inst.arg0.int64:
          of SYM_UNDERSCORE:
            self.frame.push(PLACEHOLDER)
          of SYM_SELF:
            self.frame.push(self.frame.self)
          of SYM_GENE:
            self.frame.push(App.app.gene_ns)
          else:
            let name = inst.arg0.Key
            let value = self.frame.ns[name]
            if value.int64 == NOT_FOUND.int64:
              not_allowed("Unknown symbol " & name.int.get_symbol())
            self.frame.push(value)

      of IkSelf:
        self.frame.push(self.frame.self)

      of IkSetMember:
        let name = inst.arg0.Key
        var value: Value
        self.frame.pop2(value)
        var target: Value
        self.frame.pop2(target)
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

        if self.is_next_inst_pop():
          self.pc.inc()
        else:
          self.frame.push(value)

      of IkGetMember:
        let name = inst.arg0.Key
        var value: Value
        self.frame.pop2(value)
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
        var value: Value
        self.frame.pop2(value)
        case value.kind:
          of VkArray:
            self.frame.push(value.ref.arr[i])
          of VkGene:
            self.frame.push(value.gene.children[i])
          else:
            todo($value.kind)

      of IkJump:
        self.pc = inst.arg0.int
        continue
      of IkJumpIfFalse:
        var value: Value
        self.frame.pop2(value)
        if not value.to_bool():
          self.pc = inst.arg0.int
          continue

      of IkJumpIfMatchSuccess:
        if self.frame.match_result.fields[inst.arg0.int64] == MfSuccess:
          self.pc = inst.arg1.int
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
        if self.is_next_inst_pop():
          self.pc.inc()
        else:
          self.frame.push(NIL)
      of IkPop:
        discard self.frame.pop()

      of IkArrayStart:
        self.frame.push(new_array_value())
      of IkArrayAddChild:
        var child: Value
        self.frame.pop2(child)
        self.frame.current().ref.arr.add(child)
      of IkArrayEnd:
        discard

      of IkMapStart:
        self.frame.push(new_map_value())
      of IkMapSetProp:
        let key = inst.arg0.Key
        var value: Value
        self.frame.pop2(value)
        self.frame.current().ref.map[key] = value
      of IkMapEnd:
        discard

      of IkGeneStart:
        self.frame.push(new_gene_value())

      of IkGeneStartDefault:
        var v: Value
        self.frame.pop2(v)
        self.frame.push(new_gene_value(v))
        case inst.arg1.int:
          of 1:   # Fn
            case v.kind:
              of VkFunction, VkNativeFn, VkNativeFn2:
                self.pc = inst.arg0.int
                continue
              of VkMacro:
                not_allowed("Macro not allowed here")
              of VkBoundMethod:
                if v.ref.bound_method.method.is_macro:
                  not_allowed("Macro not allowed here")
                else:
                  self.pc = inst.arg0.int
                  continue
              else:
                todo($v.kind)

          of 2:   # Macro
            case v.kind:
              of VkFunction, VkNativeFn, VkNativeFn2:
                not_allowed("Macro expected here")
              of VkMacro:
                discard
              of VkBoundMethod:
                if v.ref.bound_method.method.is_macro:
                  discard
                else:
                  not_allowed("Macro expected here")
              else:
                todo($v.kind)

          else:   # Not sure
            case v.kind:
              of VkFunction, VkNativeFn, VkNativeFn2:
                inst.arg1 = 1.Value
                self.pc = inst.arg0.int
                continue
              of VkMacro:
                inst.arg1 = 2.Value
              of VkBoundMethod:
                if v.ref.bound_method.method.is_macro:
                  inst.arg1 = 2.Value
                else:
                  inst.arg1 = 1.Value
                  self.pc = inst.arg0.int
                  continue
              else:
                todo($v.kind)

      of IkGeneSetType:
        var value: Value
        self.frame.pop2(value)
        self.frame.current().gene.type = value
      of IkGeneSetProp:
        let key = inst.arg0.Key
        var value: Value
        self.frame.pop2(value)
        self.frame.current().gene.props[key] = value
      of IkGeneAddChild:
        var child: Value
        self.frame.pop2(child)
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

              let caller = Caller(
                address: Address(id: self.cur_block.id, pc: self.pc),
              )
              caller.frame.update(self.frame)
              self.frame.update(new_frame(caller))
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

              let caller = Caller(
                address: Address(id: self.cur_block.id, pc: self.pc),
              )
              caller.frame.update(self.frame)
              self.frame.update(new_frame(caller))
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

                  let fn = meth.callable.ref.fn
                  fn.compile()
                  self.code_mgr.data[fn.body_compiled.id] = fn.body_compiled

                  let caller = Caller(
                    address: Address(id: self.cur_block.id, pc: self.pc),
                  )
                  caller.frame.update(self.frame)
                  self.frame.update(new_frame(caller))
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
        var second: Value
        self.frame.pop2(second)
        self.frame.replace(self.frame.current().int + second.int)

      of IkSub:
        var second: Value
        self.frame.pop2(second)
        self.frame.replace(self.frame.current().int - second.int)
      of IkSubValue:
        self.frame.replace(self.frame.current().int - inst.arg0.int)

      of IkMul:
        self.frame.push(self.frame.pop().int * self.frame.pop().int)

      of IkDiv:
        let second = self.frame.pop().int
        let first = self.frame.pop().int
        self.frame.push(first / second)

      of IkLt:
        var second: Value
        self.frame.pop2(second)
        self.frame.replace(self.frame.current().int < second.int)
      of IkLtValue:
        var first: Value
        self.frame.pop2(first)
        self.frame.push(first.int < inst.arg0.int)

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
        let caller = Caller(
          address: Address(id: self.cur_block.id, pc: self.pc),
        )
        caller.frame.update(self.frame)
        self.frame.update(new_frame(caller))
        self.frame.self = obj
        self.frame.ns = ns
        self.cur_block = compiled
        self.pc = 0
        continue

      of IkFunction:
        let f = to_function(inst.arg0)
        f.ns = self.frame.ns
        let r = new_ref(VkFunction)
        r.fn = f
        let v = r.to_ref_value()
        f.ns[f.name.to_key()] = v
        f.parent_scope_tracker = inst.arg1.ref.scope_tracker
        f.parent_scope.update(self.frame.scope)
        f.parent_scope_max = self.frame.scope.max
        if self.is_next_inst_pop():
          r.ref_count.inc() # Prevent GC
          self.pc.inc()
        else:
          self.frame.push(v)

      of IkMacro:
        let m = to_macro(inst.arg0)
        m.ns = self.frame.ns
        let r = new_ref(VkMacro)
        r.macro = m
        let v = r.to_ref_value()
        m.ns[m.name.to_key()] = v
        if self.is_next_inst_pop():
          r.ref_count.inc() # Prevent GC
          self.pc.inc()
        else:
          self.frame.push(v)

      of IkReturn:
        let caller = self.frame.caller
        if caller == nil:
          not_allowed("Return from top level")
        else:
          let v = self.frame.pop()
          self.frame.update(caller.frame)
          self.cur_block = self.code_mgr.data[caller.address.id]
          self.pc = caller.address.pc
          self.frame.push(v)
          continue

      of IkNamespace:
        let name = inst.arg0
        let ns = new_namespace(name.str)
        let r = new_ref(VkNamespace)
        r.ns = ns
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        if self.is_next_inst_pop():
          r.ref_count.inc() # Prevent GC
          self.pc.inc()
        else:
          self.frame.push(v)

      of IkClass:
        let name = inst.arg0
        let class = new_class(name.str)
        let r = new_ref(VkClass)
        r.class = class
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        if self.is_next_inst_pop():
          r.ref_count.inc() # Prevent GC
          self.pc.inc()
        else:
          self.frame.push(v)

      of IkNew:
        let v = self.frame.pop()
        let instance = new_ref(VkInstance)
        instance.instance_class = v.gene.type.ref.class
        self.frame.push(instance.to_ref_value())

        let class = instance.instance_class
        case class.constructor.kind:
          of VkFunction:
            class.constructor.ref.fn.compile()
            let compiled = class.constructor.ref.fn.body_compiled
            compiled.skip_return = true

            self.pc.inc()
            let caller = Caller(
              address: Address(id: self.cur_block.id, pc: self.pc),
            )
            caller.frame.update(self.frame)
            self.frame.update(new_frame(caller))
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
        let name = inst.arg0
        let class = new_class(name.str)
        class.parent = self.frame.pop().ref.class
        let r = new_ref(VkClass)
        r.class = class
        self.frame.ns[name.Key] = r.to_ref_value()
        self.frame.push(r.to_ref_value())

      of IkResolveMethod:
        let v = self.frame.pop()
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

            let fn = meth.callable.ref.fn
            fn.compile()
            self.code_mgr.data[fn.body_compiled.id] = fn.body_compiled

            let caller = Caller(
              address: Address(id: self.cur_block.id, pc: self.pc),
            )
            caller.frame.update(self.frame)
            self.frame.update(new_frame(caller))
            self.frame.scope.set_parent(fn.parent_scope, fn.parent_scope_max)
            self.frame.ns = fn.ns
            self.frame.self = v
            self.cur_block = fn.body_compiled
            self.pc = 0
            continue
          else:
            todo("CallMethodNoArgs: " & $meth.callable.kind)

      else:
        todo($inst.kind)

    self.pc.inc()
    if self.pc >= self.cur_block.len:
      break

proc exec*(self: VirtualMachine, code: string, module_name: string): Value =
  let compiled = compile(read_all(code))

  let ns = new_namespace(module_name)
  self.frame.update(new_frame(ns))
  self.code_mgr.data[compiled.id] = compiled
  self.cur_block = compiled

  self.exec()

include "./vm/core"
