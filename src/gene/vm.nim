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
            let start_pos = caller_instr.arg0.int
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
        self.frame.scope = new_scope(inst.arg0.ref.scope_tracker, self.frame.scope)
      of IkScopeEnd:
        self.frame.scope = self.frame.scope.parent
        discard

      of IkVar:
        {.push checks: off.}
        self.frame.scope.members.add(self.frame.current())
        {.pop.}

      of IkVarValue:
        {.push checks: off}
        let index = inst.arg1.int
        let value = inst.arg0
        # Ensure the scope has enough space for the index
        while self.frame.scope.members.len <= index:
          self.frame.scope.members.add(NIL)
        self.frame.scope.members[index] = value
        # Also push the value to the stack (like IkVar)
        self.frame.push(value)
        {.pop.}

      of IkVarResolve:
        {.push checks: off}
        when not defined(release):
          if self.trace:
            echo fmt"IkVarResolve: arg0={inst.arg0}, arg0.int={inst.arg0.int}, scope.members.len={self.frame.scope.members.len}"
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
        {.push checks: off}
        let value = self.frame.current()
        self.frame.scope.members[inst.arg0.int] = value
        {.pop.}

      of IkVarAssignInherited:
        {.push checks: off}
        let value = self.frame.current()
        {.pop.}
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
          of SYM_NS:
            # Return current namespace
            let r = new_ref(VkNamespace)
            r.ns = self.frame.ns
            self.frame.push(r.to_ref_value())
          else:
            let name = cast[Key](inst.arg0)
            var value = self.frame.ns[name]
            if value.int64 == NOT_FOUND.int64:
              # Try global namespace
              value = App.app.global_ns.ns[name]
              if value.int64 == NOT_FOUND.int64:
                # Try gene namespace
                value = App.app.gene_ns.ns[name]
                if value.int64 == NOT_FOUND.int64:
                  not_allowed("Unknown symbol")
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
          of VkArray:
            # Arrays don't support named members, this is likely an error
            not_allowed("Cannot set named member '" & name.int.get_symbol() & "' on array")
          else:
            todo($target.kind)
        self.frame.push(value)

      of IkGetMember:
        let name = inst.arg0.Key
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
          of VkEnum:
            # Access enum member
            let member_name = $name
            if member_name in value.ref.enum_def.members:
              self.frame.push(value.ref.enum_def.members[member_name].to_value())
            else:
              not_allowed("enum " & value.ref.enum_def.name & " has no member " & member_name)
          of VkInstance:
            todo()
            # self.frame.push(value.ref.instance_props[name])
          else:
            todo($value.kind)

      of IkSetChild:
        let i = inst.arg0.int
        var new_value: Value
        self.frame.pop2(new_value)
        var target: Value
        self.frame.pop2(target)
        case target.kind:
          of VkArray:
            target.ref.arr[i] = new_value
          of VkGene:
            target.gene.children[i] = new_value
          else:
            when not defined(release):
              if self.trace:
                echo fmt"IkSetChild unsupported kind: {target.kind}"
            todo($target.kind)
        self.frame.push(new_value)

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
            when not defined(release):
              if self.trace:
                echo fmt"IkGetChild unsupported kind: {value.kind}"
            todo($value.kind)
      of IkGetChildDynamic:
        # Get child using index from stack
        # Stack order: [... collection index]
        var index: Value
        self.frame.pop2(index)
        var collection: Value  
        self.frame.pop2(collection)
        let i = index.int
        when not defined(release):
          if self.trace:
            echo fmt"IkGetChildDynamic: collection={collection}, index={index}"
        case collection.kind:
          of VkArray:
            self.frame.push(collection.ref.arr[i])
          of VkGene:
            self.frame.push(collection.gene.children[i])
          of VkRange:
            # Calculate the i-th element in the range
            let start = collection.ref.range_start.int
            let step = if collection.ref.range_step == NIL: 1 else: collection.ref.range_step.int
            let value = start + (i * step)
            self.frame.push(value.Value)
          else:
            when not defined(release):
              if self.trace:
                echo fmt"IkGetChildDynamic unsupported kind: {collection.kind}"
            todo($collection.kind)

      of IkJump:
        {.push checks: off}
        pc = inst.arg0.int
        inst = self.cu.instructions[pc].addr
        continue
        {.pop.}
      of IkJumpIfFalse:
        {.push checks: off}
        var value: Value
        self.frame.pop2(value)
        when not defined(release):
          if self.trace:
            echo fmt"IkJumpIfFalse: value={value}, to_bool={value.to_bool()}, jumping={not value.to_bool()}"
        if not value.to_bool():
          pc = inst.arg0.int
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkJumpIfMatchSuccess:
        {.push checks: off}
        # if self.frame.match_result.fields[inst.arg0.int64] == MfSuccess:
        if self.frame.scope.members.len > inst.arg0.int:
          pc = inst.arg1.int
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkLoopStart, IkLoopEnd:
        discard

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
        self.frame.push(inst.arg0)
        when not defined(release):
          if self.trace:
            echo fmt"IkPushValue: pushed {inst.arg0}"
      of IkPushNil:
        self.frame.push(NIL)
      of IkPop:
        let value = self.frame.pop()
        when not defined(release):
          if self.trace:
            echo fmt"IkPop: popped {value}"
      of IkDup:
        let value = self.frame.current()
        when not defined(release):
          if self.trace:
            echo fmt"IkDup: duplicating {value}"
        self.frame.push(value)
      of IkDup2:
        # Duplicate top two stack elements
        let top = self.frame.pop()
        let second = self.frame.pop()
        self.frame.push(second)
        self.frame.push(top)
        self.frame.push(second)
        self.frame.push(top)
      of IkDupSecond:
        # Duplicate second element from stack
        # Stack: [... second top] -> [... second top second]
        let top = self.frame.pop()
        let second = self.frame.pop()
        when not defined(release):
          if self.trace:
            echo fmt"IkDupSecond: top={top}, second={second}"
        self.frame.push(second)  # Put second back
        self.frame.push(top)     # Put top back
        self.frame.push(second)  # Push duplicate of second
      of IkSwap:
        # Swap top two stack elements
        let top = self.frame.pop()
        let second = self.frame.pop()
        self.frame.push(top)
        self.frame.push(second)
      of IkOver:
        # Copy second element to top: [a b] -> [a b a]
        let top = self.frame.pop()
        let second = self.frame.current()
        when not defined(release):
          if self.trace:
            echo fmt"IkOver: top={top}, second={second}"
        self.frame.push(top)
        self.frame.push(second)
      of IkLen:
        # Get length of collection
        let value = self.frame.pop()
        let length = value.size()
        when not defined(release):
          if self.trace:
            echo fmt"IkLen: size({value}) = {length}"
        self.frame.push(length.Value)

      of IkArrayStart:
        self.frame.push(new_array_value())
      of IkArrayAddChild:
        var child: Value
        self.frame.pop2(child)
        case child.kind:
          of VkExplode:
            # Expand the exploded array into individual elements
            case child.ref.explode_value.kind:
              of VkArray:
                for item in child.ref.explode_value.ref.arr:
                  self.frame.current().ref.arr.add(item)
              else:
                not_allowed("Can only explode arrays")
          else:
            self.frame.current().ref.arr.add(child)
      of IkArrayEnd:
        when not defined(release):
          if self.trace:
            echo fmt"IkArrayEnd: array on stack = {self.frame.current()}"
            # Let's also check what happens next
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
            # if inst.arg1 == 2:
            #   not_allowed("Macro not allowed here")
            # inst.arg1 = 1

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
            pc = inst.arg0.int
            inst = self.cu.instructions[pc].addr
            continue

          of VkMacro:
            # if inst.arg1 == 1:
            #   not_allowed("Macro expected here")
            # inst.arg1 = 2

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
            # if inst.arg1 == 2:
            #   not_allowed("Macro not allowed here")
            # inst.arg1 = 1

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
            pc = inst.arg0.int
            inst = self.cu.instructions[pc].addr
            continue

          of VkCompileFn:
            # if inst.arg1 == 1:
            #   not_allowed("Macro expected here")
            # inst.arg1 = 2

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
            pc = inst.arg0.int
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
        case v.kind:
          of VkFrame:
            v.ref.frame.scope.members.add(child)
          of VkNativeFrame:
            v.ref.native_frame.args.gene.children.add(child)
          of VkGene:
            case child.kind:
              of VkExplode:
                # Expand the exploded array into individual elements
                case child.ref.explode_value.kind:
                  of VkArray:
                    for item in child.ref.explode_value.ref.arr:
                      v.gene.children.add(item)
                  else:
                    not_allowed("Can only explode arrays")
              else:
                v.gene.children.add(child)
          of VkNil:
            # Skip adding to nil - this might happen in conditional contexts
            discard
          of VkBoundMethod:
            # For bound methods, we might need to handle arguments
            # For now, treat similar to nil and skip
            discard
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
                self.frame.push(first.int64 + second.int64)
              of VkFloat:
                self.frame.push(first.int64.float + second.float)
              else:
                todo("Unsupported second operand for addition: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(first.float + second.int64.float)
              of VkFloat:
                self.frame.push(first.float + second.float)
              else:
                todo("Unsupported second operand for addition: " & $second)
          else:
            todo("Unsupported first operand for addition: " & $first)
        {.pop.}

      of IkSub:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        let first = self.frame.current()
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.replace(first.int64 - second.int64)
              of VkFloat:
                self.frame.replace(first.int64.float - second.float)
              else:
                todo("Unsupported second operand for subtraction: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.replace(first.float - second.int64.float)
              of VkFloat:
                self.frame.replace(first.float - second.float)
              else:
                todo("Unsupported second operand for subtraction: " & $second)
          else:
            todo("Unsupported first operand for subtraction: " & $first)
        {.pop.}
      of IkSubValue:
        {.push checks: off}
        let first = self.frame.current()
        case first.kind:
          of VkInt:
            case inst.arg0.kind:
              of VkInt:
                self.frame.replace(first.int64 - inst.arg0.int64)
              of VkFloat:
                self.frame.replace(first.int64.float - inst.arg0.float)
              else:
                todo("Unsupported arg0 type for IkSubValue: " & $inst.arg0.kind)
          of VkFloat:
            case inst.arg0.kind:
              of VkInt:
                self.frame.replace(first.float - inst.arg0.int64.float)
              of VkFloat:
                self.frame.replace(first.float - inst.arg0.float)
              else:
                todo("Unsupported arg0 type for IkSubValue: " & $inst.arg0.kind)
          else:
            todo("Unsupported operand type for IkSubValue: " & $first.kind)
        {.pop.}

      of IkMul:
        {.push checks: off}
        let second = self.frame.pop()
        let first = self.frame.pop()
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(first.int64 * second.int64)
              of VkFloat:
                self.frame.push(first.int64.float * second.float)
              else:
                todo("Unsupported second operand for multiplication: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(first.float * second.int64.float)
              of VkFloat:
                self.frame.push(first.float * second.float)
              else:
                todo("Unsupported second operand for multiplication: " & $second)
          else:
            todo("Unsupported first operand for multiplication: " & $first)
        {.pop.}

      of IkDiv:
        let second = self.frame.pop()
        let first = self.frame.pop()
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(first.int64.float / second.int64.float)
              of VkFloat:
                self.frame.push(first.int64.float / second.float)
              else:
                todo("Unsupported second operand for division: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(first.float / second.int64.float)
              of VkFloat:
                self.frame.push(first.float / second.float)
              else:
                todo("Unsupported second operand for division: " & $second)
          else:
            todo("Unsupported first operand for division: " & $first)

      of IkLt:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        let first = self.frame.current()
        when not defined(release):
          if self.trace:
            echo fmt"IkLt: {first} < {second} = {first.int < second.int}"
        self.frame.replace(self.frame.current().int64 < second.int64)
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
        if first.to_bool:
          self.frame.push(second)
        else:
          self.frame.push(first)

      of IkOr:
        let second = self.frame.pop()
        let first = self.frame.pop()
        if first.to_bool:
          self.frame.push(first)
        else:
          self.frame.push(second)

      of IkNot:
        let value = self.frame.pop()
        if value.to_bool:
          self.frame.push(FALSE)
        else:
          self.frame.push(TRUE)

      of IkSpread:
        # Spread operator - pop array and create explode marker
        let value = self.frame.pop()
        case value.kind:
          of VkArray:
            let r = new_ref(VkExplode)
            r.explode_value = value
            self.frame.push(r.to_ref_value())
          else:
            not_allowed("... can only spread arrays")

      of IkCreateRange:
        let step = self.frame.pop()
        let `end` = self.frame.pop()
        let start = self.frame.pop()
        let range_value = new_range_value(start, `end`, step)
        self.frame.push(range_value)

      of IkCreateEnum:
        let name = self.frame.pop()
        if name.kind != VkString:
          not_allowed("enum name must be a string")
        let enum_def = new_enum(name.str)
        self.frame.push(enum_def.to_value())

      of IkEnumAddMember:
        let value = self.frame.pop()
        let name = self.frame.pop()
        let enum_val = self.frame.current()
        if name.kind != VkString:
          not_allowed("enum member name must be a string")
        if value.kind != VkInt:
          not_allowed("enum member value must be an integer")
        if enum_val.kind != VkEnum:
          not_allowed("can only add members to enums")
        enum_val.add_member(name.str, value.int)

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
        let f = to_function(inst.arg0)
        f.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        f.parent_scope.update(self.frame.scope)
        
        f.scope_tracker = new_scope_tracker(inst.arg0.ref.scope_tracker)

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
        let m = to_macro(inst.arg0)
        m.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        m.parent_scope.update(self.frame.scope)
        m.scope_tracker = new_scope_tracker(inst.arg0.ref.scope_tracker)
        
        let r = new_ref(VkMacro)
        r.macro = m
        let v = r.to_ref_value()
        m.ns[m.name.to_key()] = v
        self.frame.push(v)

      of IkBlock:
        {.push checks: off}
        let b = to_block(inst.arg0)
        b.frame = self.frame
        b.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        b.frame.update(self.frame)
        b.scope_tracker = new_scope_tracker(inst.arg0.ref.scope_tracker)

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
        let f = to_compile_fn(inst.arg0)
        f.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        f.parent_scope.update(self.frame.scope)
        f.scope_tracker = new_scope_tracker(inst.arg0.ref.scope_tracker)

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

      of IkThrow:
        {.push checks: off}
        let value = self.frame.pop()
        # TODO: Implement proper exception handling
        # For now, just raise a Nim exception
        raise new_exception(types.Exception, "Gene exception: " & $value)
        {.pop.}
        
      of IkTryStart:
        # TODO: Push exception handler info onto a stack
        discard
        
      of IkTryEnd:
        # TODO: Pop exception handler info from stack
        discard
        
      of IkCatchStart:
        # TODO: Set up catch block context
        discard
        
      of IkCatchEnd:
        # TODO: Clean up catch block context
        discard
        
      of IkFinally:
        # TODO: Implement finally block
        discard

      else:
        todo($inst.kind)

    {.push checks: off}
    pc.inc()
    inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
    {.pop}

proc exec*(self: VirtualMachine, code: string, module_name: string): Value =
  let compiled = compile(read_all(code))

  let ns = new_namespace(module_name)
  # Add eval function to the module namespace
  ns["eval".to_key()] = App.app.global_ns.ns["eval".to_key()]
  self.frame.update(new_frame(ns))
  self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
  self.frame.self = NIL  # Set default self to nil
  self.cu = compiled

  self.exec()

include "./vm/core"
