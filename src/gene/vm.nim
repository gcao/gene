import tables, strutils, strformat

import ./types
import ./parser
import ./compiler

proc exec*(self: VirtualMachine): Value =
  var pc = 0
  var inst = self.cur_block.instructions[pc].addr

  when not defined(release):
    var indent = ""

  while true:
    when not defined(release):
      if self.trace:
        if inst.kind == IkStart: # This is part of INDENT_LOGIC
          indent &= "  "
        # self.print_stack()
        echo fmt"{indent}{pc:03} {inst[]}"

    {.computedGoto.}
    case inst.kind:
      of IkNoop:
        discard

      of IkStart:
        when not defined(release):
          if not self.trace: # This is part of INDENT_LOGIC
            indent &= "  "
        # if self.cur_block.matcher != nil:
        #   self.handle_args(self.cur_block.matcher, self.frame.args)

      of IkEnd:
        {.push checks: off}
        when not defined(release):
          indent.delete(indent.len-2..indent.len-1)
        let v = self.frame.default
        if self.frame.caller == nil:
          return v
        else:
          let skip_return = self.cur_block.skip_return
          self.cur_block = self.frame.caller.cu
          pc = self.frame.caller.pc
          inst = self.cur_block.instructions[pc].addr
          self.frame.update(self.frame.caller.frame)
          self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
          if not skip_return:
            self.frame.push(v)
          continue
        {.pop.}

      of IkVar:
        {.push checks: off.}
        self.frame.scope.members.add(self.frame.current())
        {.pop.}

      of IkVarResolve:
        {.push checks: off}
        self.frame.push(self.frame.scope.members[inst.arg0.int])
        {.pop.}

      of IkVarResolveInherited:
        {.push checks: off}
        var parent_index = inst.arg1.int32
        var scope = self.frame.scope
        while parent_index > 0:
          parent_index.dec()
          scope = scope.parent
        self.frame.push(scope.members[inst.arg0.int])
        {.pop.}

      of IkVarAssign:
        {.push checks: off}
        let value = self.frame.current()
        self.frame.scope.members[inst.arg0.int] = value
        {.pop.}

      of IkVarAssignInherited:
        {.push checks: off}
        let value = self.frame.current()
        var scope = self.frame.scope
        var parent_index = inst.arg1.int32
        while parent_index > 0:
          parent_index.dec()
          scope = scope.parent
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
            todo()
            # target.ref.instance_props[name] = value
          else:
            todo($target.kind)
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
            todo()
            # self.frame.push(value.ref.instance_props[name])
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
        {.push checks: off}
        pc = inst.arg0.int
        inst = self.cur_block.instructions[pc].addr
        continue
        {.pop.}
      of IkJumpIfFalse:
        {.push checks: off}
        var value: Value
        self.frame.pop2(value)
        if not value.to_bool():
          pc = inst.arg0.int
          inst = self.cur_block.instructions[pc].addr
          continue
        {.pop.}

      of IkJumpIfMatchSuccess:
        {.push checks: off}
        # if self.frame.match_result.fields[inst.arg0.int64] == MfSuccess:
        if self.frame.scope.members.len > inst.arg0.int:
          pc = inst.arg1.int
          inst = self.cur_block.instructions[pc].addr
          continue
        {.pop.}

      of IkLoopStart, IkLoopEnd:
        discard

      of IkContinue:
        {.push checks: off}
        pc = self.cur_block.find_loop_start(pc)
        inst = self.cur_block.instructions[pc].addr
        continue
        {.pop.}

      of IkBreak:
        {.push checks: off}
        pc = self.cur_block.find_loop_end(pc)
        inst = self.cur_block.instructions[pc].addr
        continue
        {.pop.}

      of IkPushValue:
        self.frame.push(inst.arg0)
      of IkPushNil:
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
        {.push checks: off}
        let gene_type = self.frame.current()
        case gene_type.kind:
          of VkFunction:
            var r = new_ref(VkScope)
            `=sink`(r.scope, new_scope())
            self.frame.push(r.to_ref_value())
            pc = inst.arg0.int
            inst = self.cur_block.instructions[pc].addr
            continue
          else:
            discard

        var v: Value
        self.frame.pop2(v)
        self.frame.push(new_gene_value(v))
        case inst.arg1.int:
          of 1:   # Fn
            case v.kind:
              of VkFunction, VkNativeFn, VkNativeFn2:
                pc = inst.arg0.int
                inst = self.cur_block.instructions[pc].addr
                continue
              of VkMacro:
                not_allowed("Macro not allowed here")
              of VkBoundMethod:
                if v.ref.bound_method.method.is_macro:
                  not_allowed("Macro not allowed here")
                else:
                  pc = inst.arg0.int
                  inst = self.cur_block.instructions[pc].addr
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
                inst.arg1 = 1
                pc = inst.arg0.int
                inst = self.cur_block.instructions[pc].addr
                continue
              of VkMacro:
                inst.arg1 = 2
              of VkBoundMethod:
                if v.ref.bound_method.method.is_macro:
                  inst.arg1 = 2
                else:
                  inst.arg1 = 1
                  pc = inst.arg0.int
                  inst = self.cur_block.instructions[pc].addr
                  continue
              else:
                todo($v.kind)
        {.pop.}

      of IkGeneSetType:
        {.push checks: off}
        var value: Value
        self.frame.pop2(value)
        self.frame.current().gene.type = value
        {.pop.}
      of IkGeneSetProp:
        {.push checks: off}
        let key = inst.arg0.Key
        var value: Value
        self.frame.pop2(value)
        self.frame.current().gene.props[key] = value
        {.pop.}
      of IkGeneAddChild:
        {.push checks: off}
        var child: Value
        self.frame.pop2(child)
        let v = self.frame.current()
        if v.kind == VkScope:
          v.ref.scope.members.add(child)
        else:
          v.gene.children.add(child)
        {.pop.}

      of IkGeneEnd:
        {.push checks: off}
        if self.frame.current().kind == VkScope:
          let scope = self.frame.pop().ref.scope
          let v = self.frame.current()
          case v.kind:
            of VkFunction:
              discard self.frame.pop()

              let f = v.ref.fn
              if f.body_compiled == nil:
                f.compile()

              pc.inc()
              self.frame = new_frame(CallSite(frame: self.frame, cu: self.cur_block, pc: pc), scope)
              self.frame.scope.set_parent(f.parent_scope, f.parent_scope_max)
              `=copy`(self.frame.ns, f.ns)
              # self.frame.ns = f.ns
              self.cur_block = f.body_compiled
              pc = 0
              inst = self.cur_block.instructions[pc].addr
              continue
            else:
              todo($v.kind)

        let v = self.frame.current()
        let gene_type = v.gene.type
        if gene_type != nil:
          case gene_type.kind:
            of VkMacro:
              discard self.frame.pop()

              gene_type.ref.macro.compile()

              pc.inc()
              self.frame = new_frame(CallSite(frame: self.frame, cu: self.cur_block, pc: pc))
              self.frame.scope.set_parent(gene_type.ref.macro.parent_scope, gene_type.ref.macro.parent_scope_max)
              self.frame.ns = gene_type.ref.macro.ns
              self.frame.args = v
              self.cur_block = gene_type.ref.macro.body_compiled
              pc = 0
              inst = self.cur_block.instructions[pc].addr
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
                  let fn = meth.callable.ref.fn
                  fn.compile()

                  pc.inc()
                  self.frame = new_frame(CallSite(frame: self.frame, cu: self.cur_block, pc: pc))
                  self.frame.scope.set_parent(fn.parent_scope, fn.parent_scope_max)
                  self.frame.ns = fn.ns
                  self.frame.self = gene_type.ref.bound_method.self
                  self.frame.args = v
                  self.cur_block = fn.body_compiled
                  pc = 0
                  inst = self.cur_block.instructions[pc].addr
                  continue
                else:
                  todo("Bound method: " & $meth.callable.kind)

            else:
              discard
        {.pop.}

      of IkAdd:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        self.frame.replace(self.frame.current().int + second.int)
        {.pop.}

      of IkSub:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        self.frame.replace(self.frame.current().int - second.int)
        {.pop.}
      of IkSubValue:
        {.push checks: off}
        self.frame.replace(self.frame.current().int - inst.arg0.int)
        {.pop.}

      of IkMul:
        self.frame.push(self.frame.pop().int * self.frame.pop().int)

      of IkDiv:
        let second = self.frame.pop().int
        let first = self.frame.pop().int
        self.frame.push(first / second)

      of IkLt:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        self.frame.replace(self.frame.current().int < second.int)
        {.pop.}
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
        let r = new_ref(VkCompiledUnit)
        r.cu = compiled
        self.frame.push(r.to_ref_value())

      of IkCallInit:
        {.push checks: off}
        let compiled = self.frame.pop().ref.cu
        let obj = self.frame.current()
        var ns: Namespace
        case obj.kind:
          of VkNamespace:
            ns = obj.ref.ns
          of VkClass:
            ns = obj.ref.class.ns
          else:
            todo($obj.kind)

        pc.inc()
        self.frame = new_frame(CallSite(frame: self.frame, cu: self.cur_block, pc: pc))
        self.frame.self = obj
        self.frame.ns = ns
        self.cur_block = compiled
        pc = 0
        inst = self.cur_block.instructions[pc].addr
        continue
        {.pop.}

      of IkFunction:
        {.push checks: off}
        let f = to_function(inst.arg0)
        f.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        f.parent_scope_tracker = inst.arg0.ref.scope_tracker
        f.parent_scope.update(self.frame.scope)
        f.parent_scope_max = self.frame.scope.max
        let r = new_ref(VkFunction)
        r.fn = f
        let v = r.to_ref_value()
        f.ns[f.name.to_key()] = v
        self.frame.push(v)
        {.pop.}

      of IkMacro:
        let m = to_macro(inst.arg0)
        m.ns = self.frame.ns
        let r = new_ref(VkMacro)
        r.macro = m
        let v = r.to_ref_value()
        m.ns[m.name.to_key()] = v
        self.frame.push(v)

      of IkReturn:
        {.push checks: off}
        if self.frame.caller == nil:
          not_allowed("Return from top level")
        else:
          let v = self.frame.pop()
          self.cur_block = self.frame.caller.cu
          pc = self.frame.caller.pc
          inst = self.cur_block.instructions[pc].addr
          self.frame.update(self.frame.caller.frame)
          self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
          self.frame.push(v)
          continue
        {.pop.}

      of IkNamespace:
        let name = inst.arg0
        let ns = new_namespace(name.str)
        let r = new_ref(VkNamespace)
        r.ns = ns
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        self.frame.push(v)

      of IkClass:
        let name = inst.arg0
        let class = new_class(name.str)
        let r = new_ref(VkClass)
        r.class = class
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
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

            pc.inc()
            self.frame = new_frame(CallSite(frame: self.frame, cu: self.cur_block, pc: pc))
            self.frame.self = instance.to_ref_value()
            self.frame.ns = class.constructor.ref.fn.ns
            self.cur_block = compiled
            pc = 0
            inst = self.cur_block.instructions[pc].addr
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
            pc.inc()
            inst = self.cur_block.instructions[pc].addr

            let fn = meth.callable.ref.fn
            fn.compile()

            self.frame = new_frame(CallSite(frame: self.frame, cu: self.cur_block, pc: pc))
            self.frame.scope.set_parent(fn.parent_scope, fn.parent_scope_max)
            self.frame.ns = fn.ns
            self.frame.self = v
            self.cur_block = fn.body_compiled
            pc = 0
            inst = self.cur_block.instructions[pc].addr
            continue
          else:
            todo("CallMethodNoArgs: " & $meth.callable.kind)

      else:
        todo($inst.kind)

    {.push checks: off}
    pc.inc()
    inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
    {.pop.}

proc exec*(self: VirtualMachine, code: string, module_name: string): Value =
  let compiled = compile(read_all(code))

  let ns = new_namespace(module_name)
  self.frame.update(new_frame(ns))
  self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
  self.cur_block = compiled

  self.exec()

include "./vm/core"
