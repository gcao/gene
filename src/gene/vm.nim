import tables, strutils, strformat

import ./types
import ./parser
import ./compiler

proc exec*(self: VirtualMachine): Value =
  var pc = 0
  var inst = self.cu.instructions[pc].addr

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
        # if self.cu.matcher != nil:
        #   self.handle_args(self.cu.matcher, self.frame.args)

      of IkEnd:
        {.push checks: off}
        when not defined(release):
          indent.delete(indent.len-2..indent.len-1)
        # TODO: validate that there is only one value on the stack
        let v = self.frame.current
        if self.frame.caller_frame == nil:
          return v
        else:
          if self.cu.kind == CkCompileFn:
            # Replace the caller's instructions with what's returned
            # Point the caller's pc to the first of the new instructions
            var cu = self.frame.caller_address.cu
            let end_pos = self.frame.caller_address.pc
            let caller_instr = self.frame.caller_address.cu.instructions[end_pos]
            let start_pos = caller_instr.jump_arg0.int
            var new_instructions: seq[Instruction] = @[]
            for item in v.ref.arr:
              case item.kind:
                of VkInstruction:
                  new_instructions.add(item.ref.instr)
                of VkArray:
                  for item2 in item.ref.arr:
                    new_instructions.add(item2.ref.instr)
                else:
                  todo($item.kind)
            cu.replace_chunk(start_pos, end_pos, new_instructions)
            self.cu = self.frame.caller_address.cu
            pc = start_pos
            inst = self.cu.instructions[pc].addr
            self.frame.update(self.frame.caller_frame)
            self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
            continue

          let skip_return = self.cu.skip_return
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          self.frame.update(self.frame.caller_frame)
          self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
          if not skip_return:
            self.frame.push(v)
          continue
        {.pop.}

      of IkScopeStart:
        self.frame.scope = new_scope(inst.scope_arg0.ref.scope_tracker, self.frame.scope)
      of IkScopeEnd:
        self.frame.scope = self.frame.scope.parent
        discard

      of IkVar:
        {.push checks: off.}
        self.frame.scope.members.add(self.frame.current())
        {.pop.}

      of IkVarResolve:
        {.push checks: off}
        self.frame.push(self.frame.scope.members[inst.var_arg0.int])
        {.pop.}

      of IkVarResolveInherited:
        var parent_index = inst.effect_arg1.int32
        var scope = self.frame.scope
        while parent_index > 0:
          parent_index.dec()
          scope = scope.parent
        {.push checks: off}
        self.frame.push(scope.members[inst.effect_arg0.int])
        {.pop.}

      of IkVarAssign:
        {.push checks: off}
        let value = self.frame.current()
        self.frame.scope.members[inst.var_arg0.int] = value
        {.pop.}

      of IkVarAssignInherited:
        {.push checks: off}
        let value = self.frame.current()
        {.pop.}
        var scope = self.frame.scope
        var parent_index = inst.effect_arg1.int32
        while parent_index > 0:
          parent_index.dec()
          scope = scope.parent
        {.push checks: off}
        scope.members[inst.effect_arg0.int] = value
        {.pop.}

      of IkAssign:
        todo($IkAssign)
        # let value = self.frame.current()
        # Find the namespace where the member is defined and assign it there

      of IkResolveSymbol:
        case inst.var_arg0.int64:
          of SYM_UNDERSCORE:
            self.frame.push(PLACEHOLDER)
          of SYM_SELF:
            self.frame.push(self.frame.self)
          of SYM_GENE:
            self.frame.push(App.app.gene_ns)
          else:
            let name = inst.var_arg0.Key
            let value = self.frame.ns[name]
            if value.int64 == NOT_FOUND.int64:
              not_allowed("Unknown symbol " & name.int.get_symbol())
            self.frame.push(value)

      of IkSelf:
        self.frame.push(self.frame.self)

      of IkSetMember:
        let name = inst.var_arg0.Key
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
        let name = inst.var_arg0.Key
        var value: Value
        self.frame.pop2(value)
        # echo "IkGetMember " & $value & " " & $name
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
        let i = inst.var_arg0.int
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
        pc = inst.jump_arg0.int
        inst = self.cu.instructions[pc].addr
        continue
        {.pop.}
      of IkJumpIfTrue:
        {.push checks: off}
        var value: Value
        self.frame.pop2(value)
        if value.to_bool():
          pc = inst.jump_arg0.int
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}
      of IkJumpIfFalse:
        {.push checks: off}
        var value: Value
        self.frame.pop2(value)
        if not value.to_bool():
          pc = inst.jump_arg0.int
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkJumpIfMatchSuccess:
        {.push checks: off}
        # if self.frame.match_result.fields[inst.effect_arg0.int64] == MfSuccess:
        if self.frame.scope.members.len > inst.effect_arg0.int:
          pc = inst.effect_arg1.int
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkLoopStart, IkLoopEnd:
        discard

      of IkEffectEnter:
        let config = inst.effect_arg0.ref.effect_config
        if not self.frame.effect_config.is_nil():
          config.prev = self.frame.effect_config
        self.frame.effect_config = config

      of IkEffectExit:
        if not self.frame.effect_config.is_nil():
          self.frame.effect_config = self.frame.effect_config.prev

      of IkEffectTrigger:
        {.push checks: off}
        let kind = cast[EffectKind](inst.effect_arg1)
        var value: Value
        self.frame.pop2(value)
        self.frame.effect = Effect(kind: kind, data: value)
        if self.frame.effect_config.is_nil:
          todo("Bubble effect up to the caller")
        let handler = self.frame.effect_config.handlers.get_or_default(kind, nil)
        if handler.is_nil:
          todo("Bubble effect up to the caller")
        case handler.kind:
          of EhSimple:
            pc = handler.simple_pos
            inst = self.cu.instructions[pc].addr
            continue
          else:
            todo($handler.kind)
        {.pop.}

      of IkEffectConsume:
        {.push checks: off}
        let kind = cast[EffectKind](inst.effect_arg1)
        if self.frame.effect.kind == kind:
          self.frame.push(self.frame.effect.data)
          self.frame.effect = nil
        {.pop.}

      # of IkEffectEnter:
      #   let c = inst.arg0.ref.effect_config
      #   if not self.frame.effect_config.is_nil():
      #     c.prev = self.frame.effect_config
      #   self.frame.effect_config = c

      # # of IkEffectExit:

      # of IkEffectTrigger:
      #   let kind = cast[EffectKind](inst.arg1)
      #   self.frame.effect = Effect(kind: kind)
      #   if self.frame.effect_config.is_nil:
      #     todo("Bubble effect up to the caller")
      #   let handler = self.frame.effect_config.handlers.get_or_default(kind, nil)
      #   if handler.is_nil:
      #     todo("Bubble effect up to the caller")
      #   case handler.kind:
      #     of EhSimple:
      #       # TODO: check effect boundary
      #       pc = handler.simple_pos
      #       inst = self.cu.instructions[pc].addr
      #     else:
      #       todo($handler.kind)
      #   {.pop.}

      # of IkEffectLoad:
      # of IkEffectConsume:

      of IkContinue:
        {.push checks: off}
        pc = self.cu.find_loop_start(pc)
        inst = self.cu.instructions[pc].addr
        continue
        {.pop.}

      of IkBreak:
        {.push checks: off}
        pc = self.cu.find_loop_end(pc)
        inst = self.cu.instructions[pc].addr
        continue
        {.pop.}

      of IkPushValue:
        self.frame.push(inst.push_value)
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
        let key = inst.prop_arg0.Key
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
            var scope: Scope
            let f = gene_type.ref.fn
            if f.matcher.is_empty():
              scope = f.parent_scope
            else:
              scope = new_scope(f.scope_tracker, f.parent_scope)

            var r = new_ref(VkFrame)
            r.frame = new_frame()
            r.frame.kind = FkFunction
            r.frame.target = gene_type
            r.frame.scope = scope
            self.frame.replace(r.to_ref_value())
            pc = inst.prop_arg0.int
            inst = self.cu.instructions[pc].addr
            continue

          of VkMacro:
            var scope: Scope
            let m = gene_type.ref.macro
            if m.matcher.is_empty():
              scope = m.parent_scope
            else:
              scope = new_scope(m.scope_tracker, m.parent_scope)

            var r = new_ref(VkFrame)
            r.frame = new_frame()
            r.frame.kind = FkMacro
            r.frame.target = gene_type
            r.frame.scope = scope
            self.frame.replace(r.to_ref_value())
            pc.inc()
            inst = self.cu.instructions[pc].addr
            continue

          of VkBlock:
            var scope: Scope
            let b = gene_type.ref.block
            if b.matcher.is_empty():
              scope = b.frame.scope
            else:
              scope = new_scope(b.scope_tracker, b.frame.scope)

            var r = new_ref(VkFrame)
            r.frame = new_frame()
            r.frame.kind = FkBlock
            r.frame.target = gene_type
            r.frame.scope = scope
            self.frame.replace(r.to_ref_value())
            pc = inst.prop_arg0.int
            inst = self.cu.instructions[pc].addr
            continue

          of VkCompileFn:
            var scope: Scope
            let f = gene_type.ref.compile_fn
            if f.matcher.is_empty():
              scope = f.parent_scope
            else:
              scope = new_scope(f.scope_tracker, f.parent_scope)

            var r = new_ref(VkFrame)
            r.frame = new_frame()
            r.frame.kind = FkCompileFn
            r.frame.target = gene_type
            r.frame.scope = scope
            self.frame.replace(r.to_ref_value())
            pc.inc()
            inst = self.cu.instructions[pc].addr
            continue

          of VkNativeFn:
            var r = new_ref(VkNativeFrame)
            r.native_frame = NativeFrame(
              kind: NfFunction,
              target: gene_type,
              args: new_gene_value(),
            )
            self.frame.replace(r.to_ref_value())
            pc = inst.prop_arg0.int
            inst = self.cu.instructions[pc].addr
            continue

          else:
            discard

        {.pop.}

      of IkGeneSetType:
        {.push checks: off}
        var value: Value
        self.frame.pop2(value)
        self.frame.current().gene.type = value
        {.pop.}
      of IkGeneSetProp:
        {.push checks: off}
        let key = inst.var_arg0.Key
        var value: Value
        self.frame.pop2(value)
        self.frame.current().gene.props[key] = value
        {.pop.}
      of IkGeneAddChild:
        {.push checks: off}
        var child: Value
        self.frame.pop2(child)
        let v = self.frame.current()
        case v.kind:
          of VkFrame:
            v.ref.frame.scope.members.add(child)
          of VkNativeFrame:
            v.ref.native_frame.args.gene.children.add(child)
          of VkGene:
            v.gene.children.add(child)
          else:
            todo("GeneAddChild: " & $v.kind)
        {.pop.}

      of IkGeneEnd:
        {.push checks: off}
        let kind = self.frame.current().kind
        case kind:
          of VkFrame:
            let frame = self.frame.current().ref.frame
            case frame.kind:
              of FkFunction:
                let f = frame.target.ref.fn
                if f.body_compiled == nil:
                  f.compile()

                pc.inc()
                frame.caller_frame.update(self.frame)
                frame.caller_address = Address(cu: self.cu, pc: pc)
                frame.ns = f.ns
                self.frame.update(frame)
                self.cu = f.body_compiled
                pc = 0
                inst = self.cu.instructions[pc].addr
                continue

              of FkMacro:
                let m = frame.target.ref.macro
                if m.body_compiled == nil:
                  m.compile()

                pc.inc()
                frame.caller_frame.update(self.frame)
                frame.caller_address = Address(cu: self.cu, pc: pc)
                frame.ns = m.ns
                self.frame.update(frame)
                self.cu = m.body_compiled
                pc = 0
                inst = self.cu.instructions[pc].addr
                continue

              of FkBlock:
                let b = frame.target.ref.block
                if b.body_compiled == nil:
                  b.compile()

                pc.inc()
                frame.caller_frame.update(self.frame)
                frame.caller_address = Address(cu: self.cu, pc: pc)
                frame.ns = b.ns
                self.frame.update(frame)
                self.cu = b.body_compiled
                pc = 0
                inst = self.cu.instructions[pc].addr
                continue

              of FkCompileFn:
                let f = frame.target.ref.compile_fn
                if f.body_compiled == nil:
                  f.compile()

                # pc.inc() # Do not increment pc, the callee will use pc to find current instruction
                frame.caller_frame.update(self.frame)
                frame.caller_address = Address(cu: self.cu, pc: pc)
                frame.ns = f.ns
                self.frame.update(frame)
                self.cu = f.body_compiled
                pc = 0
                inst = self.cu.instructions[pc].addr
                continue

              else:
                todo($frame.kind)

          of VkNativeFrame:
            let frame = self.frame.current().ref.native_frame
            case frame.kind:
              of NfFunction:
                let f = frame.target.ref.native_fn
                self.frame.replace(f(self, frame.args))
              else:
                todo($frame.kind)

          else:
            discard

        {.pop.}

      of IkAdd:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        let first = self.frame.pop()
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(first.int + second.int)
              else:
                todo("Unsupported second operand for addition: " & $second)
          else:
            todo("Unsupported first operand for addition: " & $first)
        {.pop.}

      of IkSub:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        self.frame.replace(self.frame.current().int - second.int)
        {.pop.}
      of IkSubValue:
        {.push checks: off}
        self.frame.replace(self.frame.current().int - inst.value_arg0.int)
        {.pop.}

      of IkMul:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        self.frame.replace(self.frame.current().int * second.int)
        {.pop.}

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
        self.frame.push(first.int < inst.value_arg0.int)

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
        self.frame = new_frame(self.frame, Address(cu: self.cu, pc: pc))
        self.frame.self = obj
        self.frame.ns = ns
        self.cu = compiled
        pc = 0
        inst = self.cu.instructions[pc].addr
        continue
        {.pop.}

      of IkFunction:
        {.push checks: off}
        let f = to_function(inst.var_arg0)
        f.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        f.parent_scope.update(self.frame.scope)
        f.scope_tracker = new_scope_tracker(inst.push_value.ref.scope_tracker)

        if not f.matcher.is_empty():
          for child in f.matcher.children:
            f.scope_tracker.add(child.name_key)

        let r = new_ref(VkFunction)
        r.fn = f
        let v = r.to_ref_value()
        f.ns[f.name.to_key()] = v
        self.frame.push(v)
        {.pop.}

      of IkMacro:
        let m = to_macro(inst.var_arg0)
        m.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        m.parent_scope.update(self.frame.scope)
        m.scope_tracker = new_scope_tracker(inst.push_value.ref.scope_tracker)
        let r = new_ref(VkMacro)
        r.macro = m
        let v = r.to_ref_value()
        m.ns[m.name.to_key()] = v
        self.frame.push(v)

      of IkBlock:
        {.push checks: off}
        let b = to_block(inst.var_arg0)
        b.frame = self.frame
        b.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        b.frame.update(self.frame)
        b.scope_tracker = new_scope_tracker(inst.push_value.ref.scope_tracker)

        if not b.matcher.is_empty():
          for child in b.matcher.children:
            b.scope_tracker.add(child.name_key)

        let r = new_ref(VkBlock)
        r.block = b
        let v = r.to_ref_value()
        self.frame.push(v)
        {.pop.}

      of IkCompileFn:
        {.push checks: off}
        let f = to_compile_fn(inst.var_arg0)
        f.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        f.parent_scope.update(self.frame.scope)
        f.scope_tracker = new_scope_tracker(inst.push_value.ref.scope_tracker)

        if not f.matcher.is_empty():
          for child in f.matcher.children:
            f.scope_tracker.add(child.name_key)

        let r = new_ref(VkCompileFn)
        r.compile_fn = f
        let v = r.to_ref_value()
        f.ns[f.name.to_key()] = v
        self.frame.push(v)
        {.pop.}

      of IkReturn:
        {.push checks: off}
        if self.frame.caller_frame == nil:
          not_allowed("Return from top level")
        else:
          let v = self.frame.pop()
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          self.frame.update(self.frame.caller_frame)
          self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
          self.frame.push(v)
          continue
        {.pop.}

      of IkNamespace:
        let name = inst.var_arg0
        let ns = new_namespace(name.str)
        let r = new_ref(VkNamespace)
        r.ns = ns
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        self.frame.push(v)

      of IkClass:
        let name = inst.var_arg0
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
            self.frame = new_frame(self.frame, Address(cu: self.cu, pc: pc))
            self.frame.self = instance.to_ref_value()
            self.frame.ns = class.constructor.ref.fn.ns
            self.cu = compiled
            pc = 0
            inst = self.cu.instructions[pc].addr
            continue
          of VkNil:
            discard
          else:
            todo($class.constructor.kind)

      of IkSubClass:
        let name = inst.var_arg0
        let class = new_class(name.str)
        class.parent = self.frame.pop().ref.class
        let r = new_ref(VkClass)
        r.class = class
        self.frame.ns[name.Key] = r.to_ref_value()
        self.frame.push(r.to_ref_value())

      of IkResolveMethod:
        let v = self.frame.pop()
        let class = v.get_class()
        let meth = class.get_method(inst.var_arg0.str)
        let r = new_ref(VkBoundMethod)
        r.bound_method = BoundMethod(
          self: v,
          # class: class,
          `method`: meth,
        )
        self.frame.push(r.to_ref_value())

      # Register operations
      of IkMove:
        self.frame.move_register(inst.move_dest, inst.move_src)
      of IkLoadConst:
        self.frame.set_register(inst.load_const_reg, inst.const_val)
      of IkLoadNil:
        self.frame.set_register(inst.load_nil_reg, NIL)
      of IkStore:
        let val = self.frame.get_register(inst.store_reg)
        let index = self.frame.scope.tracker.mappings[inst.store_name.Key]
        self.frame.scope.members[index] = val
      of IkLoad:
        let index = self.frame.scope.tracker.mappings[inst.load_name.Key]
        let val = self.frame.scope.members[index]
        self.frame.set_register(inst.load_reg, val)
      of IkLoadReg:
        let index = self.frame.scope.tracker.mappings[inst.load_reg_name.Key]
        let val = self.frame.scope.members[index]
        self.frame.registers[inst.load_reg_reg.int32] = val
      of IkStoreReg:
        let val = self.frame.registers[inst.store_reg_reg.int32]
        let index = self.frame.scope.tracker.mappings[inst.store_reg_name.Key]
        self.frame.scope.members[index] = val
      of IkMoveReg:
        self.frame.move_register(inst.move_dest, inst.move_src)
      of IkAddReg:
        let val = self.frame.get_register(inst.reg_reg)
        self.frame.set_register(inst.reg_reg, Value(val.int + inst.reg_value.int))
      of IkSubReg:
        let val = self.frame.get_register(inst.reg_reg)
        self.frame.set_register(inst.reg_reg, Value(val.int - inst.reg_value.int))
      of IkMulReg:
        let val = self.frame.get_register(inst.reg_reg)
        self.frame.set_register(inst.reg_reg, Value(val.int * inst.reg_value.int))
      of IkDivReg:
        let val = self.frame.get_register(inst.reg_reg)
        self.frame.set_register(inst.reg_reg, Value(val.int / inst.reg_value.int))

      # Stack operations (for backward compatibility)
      else:
        todo($inst.kind)

    {.push checks: off}
    pc.inc()
    inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
    {.pop}

proc exec*(self: VirtualMachine, code: string, module_name: string): Value =
  let compiled = compile(read_all(code))

  let ns = new_namespace(module_name)
  self.frame.update(new_frame(ns))
  self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
  self.cu = compiled

  self.exec()

include "./vm/core"
