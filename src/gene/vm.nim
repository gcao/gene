import tables, strutils, strformat, math

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
        let v = self.frame.get_register(0)  # Use register 0 for return value
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
            if v.kind == VkArray:
              let r = v.ref
              if r != nil:
                for item in r.arr:
                  case item.kind:
                    of VkInstruction:
                      new_instructions.add(item.ref.instr)
                    of VkArray:
                      let r2 = item.ref
                      if r2 != nil:
                        for item2 in r2.arr:
                          new_instructions.add(item2.ref.instr)
                    else:
                      todo($item.kind)
            cu.replace_chunk(start_pos, end_pos, new_instructions)
            self.cu = self.frame.caller_address.cu
            pc = start_pos
            inst = self.cu.instructions[pc].addr
            var old_frame = self.frame
            self.frame.update(self.frame.caller_frame)
            old_frame.free()  # Properly free the old frame
            continue

          let skip_return = self.cu.skip_return
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          var old_frame = self.frame
          self.frame.update(self.frame.caller_frame)
          old_frame.free()  # Properly free the old frame
          if not skip_return:
            self.frame.set_register(0, v)  # Use register 0 for return value
          continue
        {.pop.}

      of IkScopeStart:
        self.frame.scope = new_scope(inst.scope_arg0.ref.scope_tracker, self.frame.scope)
      of IkScopeEnd:
        self.frame.scope = self.frame.scope.parent
        discard

      of IkVar:
        {.push checks: off.}
        self.frame.scope.members.add(self.frame.get_register(0))  # Use register 0 for current value
        {.pop.}

      of IkVarResolve:
        {.push checks: off}
        self.frame.set_register(0, self.frame.scope.members[inst.var_arg0.int])  # Use register 0 for resolved value
        {.pop.}

      of IkVarResolveInherited:
        {.push checks: off}
        let index = inst.effect_arg0.int
        let parent_index = inst.effect_arg1.int
        var scope = self.frame.scope
        for i in 0..<parent_index:
          scope = scope.parent
        self.frame.set_register(0, scope.members[index])  # Use register 0 for resolved value
        {.pop.}

      of IkVarAssign:
        {.push checks: off}
        let value = self.frame.get_register(0)  # Use register 0 for value to assign
        self.frame.scope.members[inst.var_arg0.int] = value
        {.pop.}

      of IkVarAssignInherited:
        {.push checks: off}
        let value = self.frame.get_register(0)  # Use register 0 for value to assign
        let index = inst.effect_arg0.int
        let parent_index = inst.effect_arg1.int
        var scope = self.frame.scope
        for i in 0..<parent_index:
          scope = scope.parent
        scope.members[index] = value
        {.pop.}

      of IkVarValue:
        {.push checks: off}
        self.frame.scope.members.add(inst.prop_arg0)
        {.pop.}

      of IkAssign:
        {.push checks: off}
        let value = self.frame.get_register(0)  # Use register 0 for value to assign
        self.frame.ns[inst.var_arg0.Key] = value
        {.pop.}

      of IkResolveSymbol:
        case inst.var_arg0.int64:
          of SYM_UNDERSCORE:
            self.frame.set_register(0, PLACEHOLDER)  # Use register 0 for resolved symbol
          of SYM_SELF:
            self.frame.set_register(0, self.frame.self)  # Use register 0 for resolved symbol
          of SYM_GENE:
            self.frame.set_register(0, App.app.gene_ns)  # Use register 0 for resolved symbol
          else:
            let name = inst.var_arg0.Key
            let value = self.frame.ns[name]
            if value.int64 == NOT_FOUND.int64:
              not_allowed("Unknown symbol " & name.int.get_symbol())
            self.frame.set_register(0, value)  # Use register 0 for resolved symbol

      of IkSelf:
        self.frame.set_register(0, self.frame.self)  # Use register 0 for self value

      of IkSetMember:
        let name = inst.var_arg0.Key
        let value = self.frame.get_register(1)  # Use register 1 for value to set
        let obj = self.frame.get_register(0)    # Use register 0 for target object
        case obj.kind:
          of VkMap:
            obj.ref.map[name] = value
          of VkGene:
            obj.gene.props[name] = value
          of VkNamespace:
            obj.ref.ns[name] = value
          of VkClass:
            obj.ref.class.ns[name] = value
          of VkInstance:
            todo()
          else:
            todo($obj.kind)

      of IkGetMember:
        let name = inst.var_arg0.Key
        let obj = self.frame.get_register(0)  # Use register 0 for target object
        case obj.kind:
          of VkMap:
            self.frame.set_register(0, obj.ref.map[name])  # Store result in register 0
          of VkGene:
            self.frame.set_register(0, obj.gene.props[name])  # Store result in register 0
          of VkNamespace:
            self.frame.set_register(0, obj.ref.ns[name])  # Store result in register 0
          of VkClass:
            self.frame.set_register(0, obj.ref.class.ns[name])  # Store result in register 0
          of VkInstance:
            todo()
          else:
            todo($obj.kind)

      of IkGetChild:
        let i = inst.var_arg0.int
        let obj = self.frame.get_register(0)  # Use register 0 for target object
        case obj.kind:
          of VkArray:
            self.frame.set_register(0, obj.ref.arr[i])  # Store result in register 0
          of VkGene:
            self.frame.set_register(0, obj.gene.children[i])  # Store result in register 0
          else:
            todo($obj.kind)

      of IkSetChild:
        let i = inst.var_arg0.int
        let value = self.frame.get_register(1)  # Use register 1 for value to set
        let obj = self.frame.get_register(0)    # Use register 0 for target object
        case obj.kind:
          of VkArray:
            obj.ref.arr[i] = value
          of VkGene:
            obj.gene.children[i] = value
          else:
            todo($obj.kind)

      of IkPushValue:
        self.frame.set_register(0, inst.push_value)  # Use register 0 for pushed value
      of IkPushNil:
        self.frame.set_register(0, NIL)  # Use register 0 for nil value
      of IkPop:
        discard  # No-op with registers

      of IkArrayStart:
        self.frame.set_register(0, new_array_value())

      of IkArrayAddChild:
        let arr = self.frame.get_register(0)
        let child = self.frame.get_register(1)
        arr.ref.arr.add(child)

      of IkArrayEnd:
        discard  # Array is already in register 0

      of IkMapStart:
        self.frame.set_register(0, new_map_value())  # Use register 0 for new map
      of IkMapSetProp:
        let key = inst.prop_arg0.Key
        let value = self.frame.get_register(1)  # Use register 1 for value to set
        var map = self.frame.get_register(0)  # Use register 0 for target map
        if map.kind == VkMap:
          if map.ref == nil:
            map = new_map_value()  # Create new map if ref is nil
            self.frame.set_register(0, map)  # Store new map back in register 0
          map.ref.map[key] = value  # Set the value in the map
        else:
          todo("Expected map in register 0")
      of IkMapEnd:
        discard

      of IkGeneStart:
        self.frame.set_register(0, new_gene_value())  # Use register 0 for new gene

      of IkGeneStartDefault:
        {.push checks: off}
        let gene_type = self.frame.get_register(0)  # Use register 0 for gene type
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
            init_registers(r.frame, MAX_REGISTERS)  # Initialize registers
            self.frame.set_register(0, r.to_ref_value())  # Use register 0 for frame value
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
            init_registers(r.frame, MAX_REGISTERS)  # Initialize registers
            self.frame.set_register(0, r.to_ref_value())  # Use register 0 for frame value
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
            init_registers(r.frame, MAX_REGISTERS)  # Initialize registers
            self.frame.set_register(0, r.to_ref_value())  # Use register 0 for frame value
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
            init_registers(r.frame, MAX_REGISTERS)  # Initialize registers
            self.frame.set_register(0, r.to_ref_value())  # Use register 0 for frame value
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
            self.frame.set_register(0, r.to_ref_value())  # Use register 0 for frame value
            pc = inst.prop_arg0.int
            inst = self.cu.instructions[pc].addr
            continue

          else:
            discard

        {.pop.}

      of IkGeneSetType:
        {.push checks: off}
        let value = self.frame.get_register(1)  # Use register 1 for type value
        self.frame.get_register(0).gene.type = value  # Use register 0 for target gene
        {.pop.}
      of IkGeneSetProp:
        {.push checks: off}
        let key = inst.var_arg0.Key
        let value = self.frame.get_register(1)  # Use register 1 for property value
        self.frame.get_register(0).gene.props[key] = value  # Use register 0 for target gene
        {.pop.}
      of IkGeneAddChild:
        {.push checks: off}
        let child = self.frame.get_register(1)  # Use register 1 for child value
        let v = self.frame.get_register(0)  # Use register 0 for target gene/frame
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
        let kind = self.frame.get_register(0).kind  # Use register 0 for current value
        case kind:
          of VkFrame:
            let frame = self.frame.get_register(0).ref.frame
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
            let frame = self.frame.get_register(0).ref.native_frame
            case frame.kind:
              of NfFunction:
                let f = frame.target.ref.native_fn
                self.frame.set_register(0, f(self, frame.args))  # Use register 0 for function result
              else:
                todo($frame.kind)

          else:
            discard

        {.pop.}

      of IkAdd:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        if first.kind == VkFloat or second.kind == VkFloat:
          self.frame.set_register(0, Value(first.float + second.float))  # Store result in register 0
        else:
          self.frame.set_register(0, Value(first.int + second.int))  # Store result in register 0

      of IkSub:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        if first.kind == VkFloat or second.kind == VkFloat:
          self.frame.set_register(0, Value(first.float - second.float))  # Store result in register 0
        else:
          self.frame.set_register(0, Value(first.int - second.int))  # Store result in register 0

      of IkMul:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.int * second.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) * second.float).to_value)
              else:
                todo("Multiplication not supported between " & $first.kind & " and " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.float * float(second.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float * second.float).to_value)
              else:
                todo("Multiplication not supported between " & $first.kind & " and " & $second.kind)
          else:
            todo("Multiplication not supported for " & $first.kind)

      of IkDiv:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                if second.int == 0:
                  not_allowed("Division by zero")
                self.frame.set_register(0, (float(first.int) / float(second.int)).to_value)
              of VkFloat:
                if second.float == 0.0:
                  not_allowed("Division by zero")
                self.frame.set_register(0, (float(first.int) / second.float).to_value)
              else:
                todo("Division not supported between " & $first.kind & " and " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                if second.int == 0:
                  not_allowed("Division by zero")
                self.frame.set_register(0, (first.float / float(second.int)).to_value)
              of VkFloat:
                if second.float == 0.0:
                  not_allowed("Division by zero")
                self.frame.set_register(0, (first.float / second.float).to_value)
              else:
                todo("Division not supported between " & $first.kind & " and " & $second.kind)
          else:
            todo("Division not supported for " & $first.kind)

      of IkPow:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        if first.kind == VkFloat or second.kind == VkFloat:
          self.frame.set_register(0, Value(first.float.pow(second.float)))  # Store result in register 0
        else:
          self.frame.set_register(0, Value(first.int.float64.pow(second.int.float64)))  # Store result in register 0

      of IkLt:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.int < second.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) < second.float).to_value)
              else:
                todo("Less than not supported between " & $first.kind & " and " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.float < float(second.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float < second.float).to_value)
              else:
                todo("Less than not supported between " & $first.kind & " and " & $second.kind)
          else:
            todo("Less than not supported for " & $first.kind)

      of IkLe:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.int <= second.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) <= second.float).to_value)
              else:
                todo("Less than or equal not supported between " & $first.kind & " and " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.float <= float(second.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float <= second.float).to_value)
              else:
                todo("Less than or equal not supported between " & $first.kind & " and " & $second.kind)
          else:
            todo("Less than or equal not supported for " & $first.kind)

      of IkGt:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.int > second.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) > second.float).to_value)
              else:
                todo("Greater than not supported between " & $first.kind & " and " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.float > float(second.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float > second.float).to_value)
              else:
                todo("Greater than not supported between " & $first.kind & " and " & $second.kind)
          else:
            todo("Greater than not supported for " & $first.kind)

      of IkGe:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.int >= second.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) >= second.float).to_value)
              else:
                todo("Greater than or equal not supported between " & $first.kind & " and " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.float >= float(second.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float >= second.float).to_value)
              else:
                todo("Greater than or equal not supported between " & $first.kind & " and " & $second.kind)
          else:
            todo("Greater than or equal not supported for " & $first.kind)

      of IkEq:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.int == second.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) == second.float).to_value)
              else:
                self.frame.set_register(0, false.to_value)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.float == float(second.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float == second.float).to_value)
              else:
                self.frame.set_register(0, false.to_value)
          else:
            self.frame.set_register(0, (first == second).to_value)

      of IkNe:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.int != second.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) != second.float).to_value)
              else:
                self.frame.set_register(0, true.to_value)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.set_register(0, (first.float != float(second.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float != second.float).to_value)
              else:
                self.frame.set_register(0, true.to_value)
          else:
            self.frame.set_register(0, (first != second).to_value)

      of IkAnd:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        if first.to_bool():
          self.frame.set_register(0, second.to_bool().to_value)
        else:
          self.frame.set_register(0, false.to_value)

      of IkOr:
        let second = self.frame.get_register(0)  # Use register 0 for second operand
        let first = self.frame.get_register(1)   # Use register 1 for first operand
        if first.to_bool():
          self.frame.set_register(0, true.to_value)
        else:
          self.frame.set_register(0, second.to_bool().to_value)

      of IkCompileInit:
        let input = self.frame.get_register(0)  # Use register 0 for input value
        let compiled = compile_init(input)
        let r = new_ref(VkCompiledUnit)
        r.cu = compiled
        self.frame.set_register(0, r.to_ref_value())  # Store result in register 0

      of IkCallInit:
        {.push checks: off}
        let compiled = self.frame.get_register(1).ref.cu  # Use register 1 for compiled unit
        let obj = self.frame.get_register(0)  # Use register 0 for target object
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
        self.frame.set_register(0, v)  # Store result in register 0
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
        self.frame.set_register(0, v)  # Store result in register 0

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
        self.frame.set_register(0, v)  # Store result in register 0
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
        self.frame.set_register(0, v)  # Store result in register 0
        {.pop.}

      of IkReturn:
        {.push checks: off}
        if self.frame.caller_frame == nil:
          not_allowed("Return from top level")
        else:
          let v = self.frame.get_register(0)  # Use register 0 for return value
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          var old_frame = self.frame
          self.frame.update(self.frame.caller_frame)
          old_frame.free()  # Properly free the old frame
          self.frame.set_register(0, v)  # Store result in register 0
          continue
        {.pop.}

      of IkNamespace:
        let name = inst.var_arg0
        let ns = new_namespace(name.str)
        let r = new_ref(VkNamespace)
        r.ns = ns
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        self.frame.set_register(0, v)  # Store result in register 0

      of IkClass:
        let name = inst.var_arg0
        let class = new_class(name.str)
        let r = new_ref(VkClass)
        r.class = class
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        self.frame.set_register(0, v)  # Store result in register 0

      of IkNew:
        let v = self.frame.get_register(0)  # Use register 0 for input value
        let instance = new_ref(VkInstance)
        instance.instance_class = v.gene.type.ref.class
        self.frame.set_register(0, instance.to_ref_value())  # Store result in register 0

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
        class.parent = self.frame.get_register(0).ref.class  # Use register 0 for parent class
        let r = new_ref(VkClass)
        r.class = class
        self.frame.ns[name.Key] = r.to_ref_value()
        self.frame.set_register(0, r.to_ref_value())  # Store result in register 0

      of IkResolveMethod:
        let v = self.frame.get_register(0)
        let class = v.get_class()
        let meth = class.get_method(inst.var_arg0.str)
        let r = new_ref(VkBoundMethod)
        r.bound_method = BoundMethod(
          self: v,
          # class: class,
          `method`: meth,
        )
        self.frame.set_register(0, r.to_ref_value())  # Store result in register 0

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
      of IkJumpIfFalse:
        let cond = self.frame.get_register(0)  # Use register 0 for condition
        if not cond.to_bool():
          pc = inst.jump_arg0.int
          inst = self.cu.instructions[pc].addr
          continue

      of IkJumpIfTrue:
        let cond = self.frame.get_register(0)  # Use register 0 for condition
        if cond.to_bool():
          pc = inst.jump_arg0.int
          inst = self.cu.instructions[pc].addr
          continue

      of IkSubValue:
        let value = inst.value_arg0  # Second operand is literal value
        let first = self.frame.get_register(0)  # First operand from register 0
        case first.kind:
          of VkInt:
            case value.kind:
              of VkInt:
                self.frame.set_register(0, (first.int - value.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) - value.float).to_value)
              else:
                todo("Subtraction not supported between " & $first.kind & " and " & $value.kind)
          of VkFloat:
            case value.kind:
              of VkInt:
                self.frame.set_register(0, (first.float - float(value.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float - value.float).to_value)
              else:
                todo("Subtraction not supported between " & $first.kind & " and " & $value.kind)
          else:
            todo("Subtraction not supported for " & $first.kind)

      of IkLtValue:
        let value = inst.value_arg0  # Second operand is literal value
        let first = self.frame.get_register(0)  # First operand from register 0
        case first.kind:
          of VkInt:
            case value.kind:
              of VkInt:
                self.frame.set_register(0, (first.int < value.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) < value.float).to_value)
              else:
                todo("Less than not supported between " & $first.kind & " and " & $value.kind)
          of VkFloat:
            case value.kind:
              of VkInt:
                self.frame.set_register(0, (first.float < float(value.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float < value.float).to_value)
              else:
                todo("Less than not supported between " & $first.kind & " and " & $value.kind)
          else:
            todo("Less than not supported for " & $first.kind)

      of IkJump:
        pc = inst.jump_arg0.int
        inst = self.cu.instructions[pc].addr
        continue

      of IkLeValue:
        let value = inst.value_arg0  # Second operand is literal value
        let first = self.frame.get_register(1)  # First operand from register 1
        case first.kind:
          of VkInt:
            case value.kind:
              of VkInt:
                self.frame.set_register(0, (first.int <= value.int).to_value)
              of VkFloat:
                self.frame.set_register(0, (float(first.int) <= value.float).to_value)
              else:
                todo("Less than or equal not supported between " & $first.kind & " and " & $value.kind)
          of VkFloat:
            case value.kind:
              of VkInt:
                self.frame.set_register(0, (first.float <= float(value.int)).to_value)
              of VkFloat:
                self.frame.set_register(0, (first.float <= value.float).to_value)
              else:
                todo("Less than or equal not supported between " & $first.kind & " and " & $value.kind)
          else:
            todo("Less than or equal not supported for " & $first.kind)

      else:
        todo($inst.kind)

    {.push checks: off}
    pc.inc()
    inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
    {.pop}

proc exec*(self: VirtualMachine, code: string, module_name: string = "main"): Value =
  let compiled = compile(read_all(code))
  let ns = new_namespace(module_name)
  var frame = new_frame(ns)
  self.frame.update(frame)
  self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
  self.cu = compiled

  self.exec()

include "./vm/core"
