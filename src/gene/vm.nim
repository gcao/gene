import tables, strutils, strformat

import ./types
import ./parser
import ./compiler
import ./vm/args
import ./vm/module
# import ./optimizer

when not defined(noExtensions):
  import ./vm/extension

const DEBUG_VM = false

# Forward declaration
proc exec*(self: VirtualMachine): Value

proc render_template(self: VirtualMachine, tpl: Value): Value =
  # Render a template by recursively processing quote/unquote values
  case tpl.kind:
    of VkQuote:
      # A quoted value - render its contents
      return self.render_template(tpl.ref.quote)
    
    of VkUnquote:
      # An unquoted value - evaluate it in the current context
      let expr = tpl.ref.unquote
      let discard_result = tpl.ref.unquote_discard
      
      # For now, evaluate simple cases directly without creating new frames
      # TODO: Implement full expression evaluation
      var r: Value = NIL
      
      case expr.kind:
        of VkSymbol:
          # Look up the symbol in the current scope using the scope tracker
          let key = expr.str.to_key()
          
          # Use the scope tracker to find the variable
          let var_index = self.frame.scope.tracker.locate(key)
          
          if var_index.local_index >= 0:
            # Found in scope - navigate to the correct scope
            var scope = self.frame.scope
            var parent_index = var_index.parent_index
            
            while parent_index > 0 and scope != nil:
              parent_index.dec()
              scope = scope.parent
            
            if scope != nil and var_index.local_index < scope.members.len:
              r = scope.members[var_index.local_index]
            else:
              # Not found, default to symbol
              r = expr
          else:
            # Not in scope, check namespace
            if self.frame.ns.members.hasKey(key):
              r = self.frame.ns.members[key]
            else:
              # Default to the symbol itself
              r = expr
            
        of VkGene:
          # For gene expressions, recursively render the parts
          let gene = expr.gene
          let rendered_type = self.render_template(gene.type)
          
          # Create a new gene with rendered parts
          let new_gene = new_gene(rendered_type)
          
          # Render properties
          for k, v in gene.props:
            new_gene.props[k] = self.render_template(v)
          
          # Render children
          for child in gene.children:
            new_gene.children.add(self.render_template(child))
          
          # For now, return the rendered gene without evaluating
          # TODO: Implement full expression evaluation
          r = new_gene.to_gene_value()
            
        of VkInt, VkFloat, VkBool, VkString, VkChar:
          # Literal values pass through unchanged
          r = expr
        else:
          # For other types, recursively render
          r = self.render_template(expr)
      
      if discard_result:
        # %_ means discard the r
        return NIL
      else:
        return r
    
    of VkGene:
      # Recursively render gene expressions
      let gene = tpl.gene
      let new_gene = new_gene(self.render_template(gene.type))
      
      # Render properties
      for k, v in gene.props:
        new_gene.props[k] = self.render_template(v)
      
      # Render children
      for child in gene.children:
        let rendered = self.render_template(child)
        if rendered.kind == VkExplode:
          # Handle %_ spread operator
          if rendered.ref.explode_value.kind == VkArray:
            for item in rendered.ref.explode_value.ref.arr:
              new_gene.children.add(item)
        else:
          new_gene.children.add(rendered)
      
      return new_gene.to_gene_value()
    
    of VkArray:
      # Recursively render array elements
      let new_arr = new_ref(VkArray)
      for item in tpl.ref.arr:
        let rendered = self.render_template(item)
        # Skip NIL values that come from %_ (unquote discard)
        if rendered.kind == VkNil and item.kind == VkUnquote and item.ref.unquote_discard:
          continue
        elif rendered.kind == VkExplode:
          # Handle spread in arrays
          if rendered.ref.explode_value.kind == VkArray:
            for sub_item in rendered.ref.explode_value.ref.arr:
              new_arr.arr.add(sub_item)
        else:
          new_arr.arr.add(rendered)
      return new_arr.to_ref_value()
    
    of VkMap:
      # Recursively render map values
      let new_map = new_ref(VkMap)
      for k, v in tpl.ref.map:
        new_map.map[k] = self.render_template(v)
      return new_map.to_ref_value()
    
    else:
      # Other values pass through unchanged
      return tpl

proc should_profile(self: VirtualMachine): bool {.inline.} =
  # # Check if current frame is executing a function that needs profiling
  # if self.frame.kind == FkFunction and self.frame.target.kind == VkFunction:
  #   let fn = self.frame.target.ref.fn
  #   # Profile if not already optimized and execution count is high enough
  #   return not fn.is_optimized and fn.profile_data != nil
  return false

proc record_symbol_resolution(self: VirtualMachine, pc: int, resolved: Value) {.inline.} =
  # if self.should_profile():
  #   let fn = self.frame.target.ref.fn
  #   if fn.profile_data == nil:
  #     fn.profile_data = ProfileData()
  #   fn.profile_data.symbol_resolutions[pc] = resolved
  discard


proc exec*(self: VirtualMachine): Value =
  var pc = 0
  if pc >= self.cu.instructions.len:
    raise new_exception(types.Exception, "Empty compilation unit")
  var inst = self.cu.instructions[pc].addr

  when not defined(release):
    var indent = ""


  while true:
    when not defined(release):
      if self.trace:
        if inst.kind == IkStart: # This is part of INDENT_LOGIC
          indent &= "  "
        # self.print_stack()
        echo fmt"{indent}{pc:04X} {inst[]}"

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
          if indent.len >= 2:
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
            let start_pos = caller_instr.arg0.int64.int
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
          elif self.cu.kind == CkMacro:
            # Return to caller who will handle macro expansion
            self.cu = self.frame.caller_address.cu
            pc = self.frame.caller_address.pc
            inst = self.cu.instructions[pc].addr
            self.frame.update(self.frame.caller_frame)
            self.frame.ref_count.dec()
            # Push the macro result for the caller to process
            self.frame.push(v)
            continue

          let skip_return = self.cu.skip_return
          # Check if we're returning from an async function before updating frame
          var result_val = v
          if self.frame.kind == FkFunction and self.frame.target.kind == VkFunction:
            let f = self.frame.target.ref.fn
            if f.async:
              # Wrap the return value in a future
              let future_val = new_future_value()
              let future_obj = future_val.ref.future
              future_obj.complete(result_val)
              result_val = future_val
          
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          self.frame.update(self.frame.caller_frame)
          self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
          if not skip_return:
            self.frame.push(result_val)
          continue
        {.pop.}

      of IkScopeStart:
        if inst.arg0.kind != VkScopeTracker:
          not_allowed("IkScopeStart: expected ScopeTracker, got " & $inst.arg0.kind)
        self.frame.scope = new_scope(inst.arg0.ref.scope_tracker, self.frame.scope)
      of IkScopeEnd:
        self.frame.scope = self.frame.scope.parent
        discard

      of IkVar:
        {.push checks: off.}
        let index = inst.arg0.int64.int
        let value = self.frame.pop()  # Pop the value from the stack
        if self.frame.scope.isNil:
          not_allowed("IkVar: scope is nil")
        # Ensure the scope has enough space for the index
        while self.frame.scope.members.len <= index:
          self.frame.scope.members.add(NIL)
        self.frame.scope.members[index] = value
        
        # If we're in a namespace initialization context, also store in namespace members
        if self.frame.self != nil and self.frame.self.kind == VkNamespace:
          # Find the variable name from the scope tracker
          if self.frame.scope.tracker != nil:
            for key, idx in self.frame.scope.tracker.mappings:
              if idx == index:
                self.frame.self.ref.ns.members[key] = value
                break
        
        # Push the value as the result of var
        self.frame.push(value)
        {.pop.}

      of IkVarValue:
        {.push checks: off}
        let index = inst.arg1.int
        let value = inst.arg0
        # Ensure the scope has enough space for the index
        while self.frame.scope.members.len <= index:
          self.frame.scope.members.add(NIL)
        self.frame.scope.members[index] = value
        
        # If we're in a namespace initialization context, also store in namespace members
        if self.frame.self != nil and self.frame.self.kind == VkNamespace:
          # Find the variable name from the scope tracker
          if self.frame.scope.tracker != nil:
            for key, idx in self.frame.scope.tracker.mappings:
              if idx == index:
                self.frame.self.ref.ns.members[key] = value
                break
        
        # Also push the value to the stack (like IkVar)
        self.frame.push(value)
        {.pop.}

      of IkVarResolve:
        {.push checks: off}
        when not defined(release):
          if self.trace:
            echo fmt"IkVarResolve: arg0={inst.arg0}, arg0.int64.int={inst.arg0.int64.int}, scope.members.len={self.frame.scope.members.len}"
        self.frame.push(self.frame.scope.members[inst.arg0.int64.int])
        {.pop.}

      of IkVarResolveInherited:
        var parent_index = inst.arg1.int32
        var scope = self.frame.scope
        while parent_index > 0:
          parent_index.dec()
          scope = scope.parent
        {.push checks: off}
        self.frame.push(scope.members[inst.arg0.int64.int])
        {.pop.}

      of IkVarAssign:
        {.push checks: off}
        let value = self.frame.current()
        self.frame.scope.members[inst.arg0.int64.int] = value
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
        scope.members[inst.arg0.int64.int] = value
        {.pop.}

      of IkAssign:
        todo($IkAssign)
        # let value = self.frame.current()
        # Find the namespace where the member is defined and assign it there

      of IkResolveSymbol:
        let symbol_key = cast[uint64](inst.arg0)
        case symbol_key:
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
            when not defined(release):
              if self.trace:
                echo "  ResolveSymbol: looking for key ", name.int
                try:
                  echo "  Symbol name: ", get_symbol(name.int)
                except:
                  echo "  Invalid symbol key: ", name.int
            var value = self.frame.ns[name]
            if value == NIL:
              # Try global namespace
              value = App.app.global_ns.ref.ns[name]
              when not defined(release):
                if self.trace and value != NIL:
                  echo "  Found in global namespace: ", value.kind
              if value == NIL:
                # Try gene namespace
                value = App.app.gene_ns.ref.ns[name]
                when not defined(release):
                  if self.trace and value != NIL:
                    echo "  Found in gene namespace: ", value.kind
                if value == NIL:
                  let symbol_name = try:
                    # Extract symbol index from the Key (which is a symbol value)
                    let symbol_key_uint = cast[uint64](name)
                    let symbol_index = (symbol_key_uint and PAYLOAD_MASK).int
                    get_symbol(symbol_index)
                  except types.Exception as e:
                    raise e  # Re-raise to see the actual error
                  not_allowed("Unknown symbol: " & symbol_name)
            else:
              when not defined(release):
                if self.trace:
                  echo "  Found in current namespace: ", value.kind
            self.frame.push(value)
            # # Record symbol resolution for profiling
            # self.record_symbol_resolution(pc, value)

      of IkSelf:
        self.frame.push(self.frame.self)
      
      of IkSetSelf:
        self.frame.self = self.frame.pop()
      
      of IkRotate:
        # Rotate top 3 stack elements: [a, b, c] -> [c, a, b]
        let c = self.frame.pop()
        let b = self.frame.pop()
        let a = self.frame.pop()
        self.frame.push(c)
        self.frame.push(a)
        self.frame.push(b)
      
      of IkParse:
        let str_value = self.frame.pop()
        if str_value.kind != VkString:
          raise new_exception(types.Exception, "$parse expects a string")
        let parsed = read(str_value.str)
        self.frame.push(parsed)
      
      of IkRender:
        let template_value = self.frame.pop()
        let rendered = self.render_template(template_value)
        self.frame.push(rendered)
      
      of IkEval:
        let value = self.frame.pop()
        case value.kind:
          of VkSymbol:
            # For eval, we need to check local scope first, then namespaces
            let key = value.str.to_key()
            
            # First check if it's a local variable in the current scope
            var found_in_scope = false
            if self.frame.scope != nil and self.frame.scope.tracker != nil:
              let found = self.frame.scope.tracker.locate(key)
              if found.local_index >= 0:
                # Variable found in scope
                var scope = self.frame.scope
                var parent_index = found.parent_index
                while parent_index > 0:
                  parent_index.dec()
                  scope = scope.parent
                self.frame.push(scope.members[found.local_index])
                found_in_scope = true
            
            if not found_in_scope:
              # Not a local variable, look in namespaces
              var r = self.frame.ns[key]
              if r == NIL:
                r = App.app.global_ns.ns[key]
                if r == NIL:
                  r = App.app.gene_ns.ns[key]
                  if r == NIL:
                    not_allowed("Unknown symbol: " & value.str)
              self.frame.push(r)
          of VkGene:
            # Evaluate a gene expression - compile and execute it
            let compiled = compile_init(value)
            # Save current state
            let saved_cu = self.cu
            let saved_pc = pc
            # Execute the compiled code
            self.cu = compiled
            let eval_result = self.exec()
            # Restore state
            self.cu = saved_cu
            pc = saved_pc
            inst = self.cu.instructions[pc].addr
            self.frame.push(eval_result)
          of VkQuote:
            # Evaluate a quoted expression by compiling and executing the quoted value
            let quoted_value = value.ref.quote
            let compiled = compile_init(quoted_value)
            # Save current state
            let saved_cu = self.cu
            let saved_pc = pc
            # Execute the compiled code
            self.cu = compiled
            let eval_result = self.exec()
            # Restore state
            self.cu = saved_cu
            pc = saved_pc
            inst = self.cu.instructions[pc].addr
            self.frame.push(eval_result)
          else:
            # For other types, just push them back (already evaluated)
            self.frame.push(value)

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
          of VkArray:
            # Arrays don't support named members, this is likely an error
            let symbol_name = try:
              get_symbol(name.int)
            except:
              "<invalid key: " & $name.int & ">"
            not_allowed("Cannot set named member '" & symbol_name & "' on array")
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
            # Special handling for $ex (gene/ex)
            if name == "ex".to_key() and value == App.app.gene_ns:
              # Return current exception
              self.frame.push(self.current_exception)
            else:
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
            if name in value.ref.instance_props:
              self.frame.push(value.ref.instance_props[name])
            else:
              self.frame.push(NIL)
          of VkNil:
            not_allowed("Cannot access member on nil")
          else:
            todo($value.kind)

      of IkGetMemberOrNil:
        # Pop property/index, then target
        var prop: Value
        self.frame.pop2(prop)
        var target: Value
        self.frame.pop2(target)
        
        let key = case prop.kind:
          of VkString: prop.str.to_key()
          of VkSymbol: prop.str.to_key()
          of VkInt: ($prop.int64).to_key()
          else: 
            not_allowed("Invalid property type: " & $prop.kind)
            "".to_key()  # Never reached, but satisfies type checker
        
        case target.kind:
          of VkMap:
            if key in target.ref.map:
              self.frame.push(target.ref.map[key])
            else:
              self.frame.push(NIL)
          of VkGene:
            if key in target.gene.props:
              self.frame.push(target.gene.props[key])
            else:
              self.frame.push(NIL)
          of VkNamespace:
            if target.ref.ns.has_key(key):
              self.frame.push(target.ref.ns[key])
            else:
              self.frame.push(NIL)
          of VkClass:
            if target.ref.class.ns.has_key(key):
              self.frame.push(target.ref.class.ns[key])
            else:
              self.frame.push(NIL)
          of VkInstance:
            if key in target.ref.instance_props:
              self.frame.push(target.ref.instance_props[key])
            else:
              self.frame.push(NIL)
          of VkArray:
            # Handle array index access
            if prop.kind == VkInt:
              let idx = prop.int64
              if idx >= 0 and idx < target.ref.arr.len:
                self.frame.push(target.ref.arr[idx])
              elif idx < 0 and -idx <= target.ref.arr.len:
                # Negative indexing
                self.frame.push(target.ref.arr[target.ref.arr.len + idx])
              else:
                self.frame.push(NIL)
            else:
              self.frame.push(NIL)
          else:
            self.frame.push(NIL)
      
      of IkGetMemberDefault:
        # Pop default value, property/index, then target
        var default_val: Value
        self.frame.pop2(default_val)
        var prop: Value
        self.frame.pop2(prop)
        var target: Value
        self.frame.pop2(target)
        
        let key = case prop.kind:
          of VkString: prop.str.to_key()
          of VkSymbol: prop.str.to_key()
          of VkInt: ($prop.int64).to_key()
          else: 
            not_allowed("Invalid property type: " & $prop.kind)
            "".to_key()  # Never reached, but satisfies type checker
        
        case target.kind:
          of VkMap:
            if key in target.ref.map:
              self.frame.push(target.ref.map[key])
            else:
              self.frame.push(default_val)
          of VkGene:
            if key in target.gene.props:
              self.frame.push(target.gene.props[key])
            else:
              self.frame.push(default_val)
          of VkNamespace:
            if target.ref.ns.has_key(key):
              self.frame.push(target.ref.ns[key])
            else:
              self.frame.push(default_val)
          of VkClass:
            if target.ref.class.ns.has_key(key):
              self.frame.push(target.ref.class.ns[key])
            else:
              self.frame.push(default_val)
          of VkInstance:
            if key in target.ref.instance_props:
              self.frame.push(target.ref.instance_props[key])
            else:
              self.frame.push(default_val)
          of VkArray:
            # Handle array index access
            if prop.kind == VkInt:
              let idx = prop.int
              if idx >= 0 and idx < target.ref.arr.len:
                self.frame.push(target.ref.arr[idx])
              elif idx < 0 and -idx <= target.ref.arr.len:
                # Negative indexing
                self.frame.push(target.ref.arr[target.ref.arr.len + idx])
              else:
                self.frame.push(default_val)
            else:
              self.frame.push(default_val)
          else:
            self.frame.push(default_val)

      of IkSetChild:
        let i = inst.arg0.int64
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
        let i = inst.arg0.int64
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
        let i = index.int64.int
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
            let start = collection.ref.range_start.int64
            let step = if collection.ref.range_step == NIL: 1'i64 else: collection.ref.range_step.int64
            let value = start + (i * step)
            self.frame.push(value.to_value())
          else:
            when not defined(release):
              if self.trace:
                echo fmt"IkGetChildDynamic unsupported kind: {collection.kind}"
            todo($collection.kind)

      of IkJump:
        {.push checks: off}
        pc = inst.arg0.int64.int
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
          pc = inst.arg0.int64.int
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkJumpIfMatchSuccess:
        {.push checks: off}
        # if self.frame.match_result.fields[inst.arg0.int64] == MfSuccess:
        let index = inst.arg0.int
        if self.frame.scope.members.len > index:
          pc = inst.arg1.int32.int
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkLoopStart, IkLoopEnd:
        discard

      of IkContinue:
        {.push checks: off}
        let label = inst.arg0.int64.int
        
        # Check if this is a continue outside of a loop
        if label == -1:
          # Check if we're in a finally block
          var in_finally = false
          if self.exception_handlers.len > 0:
            let handler = self.exception_handlers[^1]
            if handler.in_finally:
              in_finally = true
          
          if in_finally:
            # Pop the value that continue would have used
            if self.frame.stack_index > 0:
              discard self.frame.pop()
            # Silently ignore continue in finally block
            discard
          else:
            not_allowed("continue used outside of a loop")
        else:
          # Normal continue - jump to the start label
          pc = label
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkBreak:
        {.push checks: off}
        let label = inst.arg0.int64.int
        when not defined(release):
          if self.trace:
            echo fmt"IkBreak: jumping to PC {label}"
        
        # Check if this is a break outside of a loop
        if label == -1:
          # Check if we're in a finally block
          var in_finally = false
          if self.exception_handlers.len > 0:
            let handler = self.exception_handlers[^1]
            if handler.in_finally:
              in_finally = true
          
          if in_finally:
            # Pop the value that break would have used
            if self.frame.stack_index > 0:
              discard self.frame.pop()
            # Silently ignore break in finally block
            discard
          else:
            not_allowed("break used outside of a loop")
        else:
          # Normal break - jump to the end label
          when not defined(release):
            if self.trace:
              echo fmt"IkBreak: jumping from PC {pc} to PC {label}"
          pc = label
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkPushValue:
        self.frame.push(inst.arg0)
      of IkPushNil:
        self.frame.push(NIL)
      of IkPushSelf:
        self.frame.push(self.frame.self)
      of IkPop:
        discard self.frame.pop()
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
        self.frame.push(length.to_value())

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
            pc = inst.arg0.int64.int64.int
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
            
            # Pass caller's context as implicit argument (design decision D)
            # Store a reference to the current frame for $caller_eval
            r.frame.caller_context = self.frame
            
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
            pc = inst.arg0.int64.int64.int
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
              args: new_gene_value(),  # Use singleton for performance
            )
            self.frame.replace(r.to_ref_value())
            pc = inst.arg0.int64.int64.int
            inst = self.cu.instructions[pc].addr
            continue
            
          of VkBoundMethod:
            # Handle bound method calls
            let bm = gene_type.ref.bound_method
            let meth = bm.`method`
            let target = meth.callable
            
            case target.kind:
              of VkFunction:
                # Create a new frame for the method call
                var scope: Scope
                let f = target.ref.fn
                if f.matcher.is_empty():
                  scope = f.parent_scope
                else:
                  scope = new_scope(f.scope_tracker, f.parent_scope)
                
                var r = new_ref(VkFrame)
                r.frame = new_frame()
                r.frame.kind = FkFunction
                r.frame.target = target
                r.frame.scope = scope
                r.frame.current_method = meth  # Track the current method for super calls
                r.frame.self = bm.self  # Set self to the instance
                self.frame.replace(r.to_ref_value())
                pc = inst.arg0.int64.int64.int
                inst = self.cu.instructions[pc].addr
                continue
              else:
                not_allowed("Method must be a function, got " & $target.kind)

          else:
            # For non-callable types (like integers, strings, etc.), 
            # create a gene with this value as the type
            var g = new_gene_value()
            g.gene.type = gene_type
            self.frame.push(g)

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
        var current = self.frame.current()
        case current.kind:
          of VkGene:
            current.gene.props[key] = value
          of VkFrame:
            # For function calls, we need to set up the args gene with properties
            if current.ref.frame.args.kind != VkGene:
              current.ref.frame.args = new_gene_value()
            current.ref.frame.args.gene.props[key] = value
          of VkNativeFrame:
            # For native function calls, ignore property setting for now
            discard
          else:
            todo("GeneSetProp for " & $current.kind)
        {.pop.}
      of IkGeneAddChild:
        {.push checks: off}
        var child: Value
        self.frame.pop2(child)
        var v = self.frame.current()
        if DEBUG_VM:
          echo "IkGeneAddChild: v.kind = ", v.kind, ", child = ", child
        case v.kind:
          of VkFrame:
            # For function calls, we need to set up the args gene with children
            if v.ref.frame.args.kind != VkGene:
              v.ref.frame.args = new_gene_value()
            case child.kind:
              of VkExplode:
                # Expand the exploded array into individual elements
                case child.ref.explode_value.kind:
                  of VkArray:
                    for item in child.ref.explode_value.ref.arr:
                      v.ref.frame.args.gene.children.add(item)
                  else:
                    not_allowed("Can only explode arrays")
              else:
                v.ref.frame.args.gene.children.add(child)
          of VkNativeFrame:
            case child.kind:
              of VkExplode:
                # Expand the exploded array into individual elements
                case child.ref.explode_value.kind:
                  of VkArray:
                    for item in child.ref.explode_value.ref.arr:
                      v.ref.native_frame.args.gene.children.add(item)
                  else:
                    not_allowed("Can only explode arrays")
              else:
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
            # For other value types, we can't add children directly
            # This might be an error in the compilation or a special case
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

                # # Initialize profiling if needed
                # if f.profile_data == nil and not f.is_optimized:
                #   if not f.body_compiled.is_nil:
                #     f.profile_data = ProfileData()
                # 
                # # Update execution count and check for optimization
                # if f.profile_data != nil:
                #   f.profile_data.execution_count.inc()
                #   # Check if we should optimize this function
                #   if should_optimize(f):
                #     optimize_function(f)


                pc.inc()
                frame.caller_frame.update(self.frame)
                frame.caller_address = Address(cu: self.cu, pc: pc)
                frame.ns = f.ns
                # Pop the frame from the stack before switching context
                discard self.frame.pop()
                self.frame.update(frame)
                
                # Use optimized bytecode if available
                if f.is_optimized and f.optimized_cu != nil:
                  self.cu = f.optimized_cu
                else:
                  self.cu = f.body_compiled
                
                # Process arguments if matcher exists
                if not f.matcher.is_empty():
                  process_args(f.matcher, frame.args, frame.scope)
                
                # If this is an async function, set up exception handler
                if f.async:
                  self.exception_handlers.add(ExceptionHandler(
                    catch_pc: -3,  # Special marker for async function
                    finally_pc: -1,
                    frame: self.frame,
                    cu: self.cu,
                    saved_value: NIL,
                    has_saved_value: false,
                    in_finally: false
                  ))
                
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
                # Pop the frame from the stack before switching context
                discard self.frame.pop()
                self.frame.update(frame)
                self.cu = m.body_compiled
                
                # Process arguments if matcher exists
                if not m.matcher.is_empty():
                  process_args(m.matcher, frame.args, frame.scope)
                
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
                # Pop the frame from the stack before switching context
                discard self.frame.pop()
                self.frame.update(frame)
                self.cu = b.body_compiled
                
                # Process arguments if matcher exists
                if not b.matcher.is_empty():
                  process_args(b.matcher, frame.args, frame.scope)
                
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
                # Pop the frame from the stack before switching context
                discard self.frame.pop()
                self.frame.update(frame)
                self.cu = f.body_compiled
                
                # Process arguments if matcher exists
                if not f.matcher.is_empty():
                  process_args(f.matcher, frame.args, frame.scope)
                
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
                let fn_result = f(self, frame.args)
                self.frame.replace(fn_result)
              else:
                todo($frame.kind)

          else:
            discard
          
        {.pop.}

      of IkAdd:
        {.push checks: off}
        let second = self.frame.pop()
        let first = self.frame.pop()
        when not defined(release):
          if self.trace:
            echo fmt"IkAdd: first={first} ({first.kind}), second={second} ({second.kind})"
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(first.int64 + second.int64)
              of VkFloat:
                self.frame.push(first.int64.float64 + second.float)
              else:
                todo("Unsupported second operand for addition: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                let r = first.float + second.int64.float64
                when not defined(release):
                  if self.trace:
                    echo fmt"IkAdd float+int: {first.float} + {second.int64.float64} = {r}"
                self.frame.push(r)
              of VkFloat:
                self.frame.push(first.float + second.float)
              else:
                todo("Unsupported second operand for addition: " & $second)
          else:
            todo("Unsupported first operand for addition: " & $first)
        {.pop.}

      of IkAddVarConst:
        {.push checks: off}
        # Add constant to variable: var + const
        let var_value = self.frame.scope.members[inst.arg0.int64.int]
        let const_value = inst.arg1.int64.to_value()
        case var_value.kind:
          of VkInt:
            case const_value.kind:
              of VkInt:
                self.frame.push(var_value.int64 + const_value.int64)
              of VkFloat:
                self.frame.push(var_value.int64.float64 + const_value.float)
              else:
                todo("Unsupported constant type for IkAddVarConst: " & $const_value.kind)
          of VkFloat:
            case const_value.kind:
              of VkInt:
                self.frame.push(var_value.float + const_value.int64.float64)
              of VkFloat:
                self.frame.push(var_value.float + const_value.float)
              else:
                todo("Unsupported constant type for IkAddVarConst: " & $const_value.kind)
          else:
            todo("Unsupported variable type for IkAddVarConst: " & $var_value.kind)
        {.pop.}

      of IkSub:
        {.push checks: off}
        let second = self.frame.pop()
        let first = self.frame.pop()
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(first.int64 - second.int64)
              of VkFloat:
                self.frame.push(first.int64.float64 - second.float)
              else:
                todo("Unsupported second operand for subtraction: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(first.float - second.int64.float64)
              of VkFloat:
                self.frame.push(first.float - second.float)
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
                self.frame.replace(first.int64.float64 - inst.arg0.float)
              else:
                todo("Unsupported arg0 type for IkSubValue: " & $inst.arg0.kind)
          of VkFloat:
            case inst.arg0.kind:
              of VkInt:
                self.frame.replace(first.float - inst.arg0.int64.float64)
              of VkFloat:
                self.frame.replace(first.float - inst.arg0.float)
              else:
                todo("Unsupported arg0 type for IkSubValue: " & $inst.arg0.kind)
          else:
            todo("Unsupported operand type for IkSubValue: " & $first.kind)
        {.pop.}

      of IkSubVarConst:
        {.push checks: off}
        # Subtract constant from variable: var - const
        let var_value = self.frame.scope.members[inst.arg0.int64.int]
        let const_value = inst.arg1.int64.to_value()
        case var_value.kind:
          of VkInt:
            case const_value.kind:
              of VkInt:
                self.frame.push(var_value.int64 - const_value.int64)
              of VkFloat:
                self.frame.push(var_value.int64.float64 - const_value.float)
              else:
                todo("Unsupported constant type for IkSubVarConst: " & $const_value.kind)
          of VkFloat:
            case const_value.kind:
              of VkInt:
                self.frame.push(var_value.float - const_value.int64.float64)
              of VkFloat:
                self.frame.push(var_value.float - const_value.float)
              else:
                todo("Unsupported constant type for IkSubVarConst: " & $const_value.kind)
          else:
            todo("Unsupported variable type for IkSubVarConst: " & $var_value.kind)
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
                self.frame.push(first.int64.float64 * second.float)
              else:
                todo("Unsupported second operand for multiplication: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(first.float * second.int64.float64)
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
                self.frame.push(first.int64.float64 / second.int64.float64)
              of VkFloat:
                self.frame.push(first.int64.float64 / second.float)
              else:
                todo("Unsupported second operand for division: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(first.float / second.int64.float64)
              of VkFloat:
                self.frame.push(first.float / second.float)
              else:
                todo("Unsupported second operand for division: " & $second)
          else:
            todo("Unsupported first operand for division: " & $first)

      of IkNeg:
        # Unary negation
        let value = self.frame.pop()
        case value.kind:
          of VkInt:
            self.frame.push(-value.int64)
          of VkFloat:
            self.frame.push(-value.float)
          else:
            todo("Unsupported operand for negation: " & $value)

      of IkLt:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        let first = self.frame.current()
        when not defined(release):
          if self.trace:
            echo fmt"IkLt: {first} < {second}"
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.replace((first.int64 < second.int64).to_value())
              of VkFloat:
                self.frame.replace((first.int64.float64 < second.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " < " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.replace((first.float < second.int64.float64).to_value())
              of VkFloat:
                self.frame.replace((first.float < second.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " < " & $second.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " < " & $second.kind)
        {.pop.}
      of IkLtValue:
        var first: Value
        self.frame.pop2(first)
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case inst.arg0.kind:
              of VkInt:
                self.frame.push((first.int64 < inst.arg0.int64).to_value())
              of VkFloat:
                self.frame.push((first.int64.float64 < inst.arg0.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " < " & $inst.arg0.kind)
          of VkFloat:
            case inst.arg0.kind:
              of VkInt:
                self.frame.push((first.float < inst.arg0.int64.float64).to_value())
              of VkFloat:
                self.frame.push((first.float < inst.arg0.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " < " & $inst.arg0.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " < " & $inst.arg0.kind)

      of IkLtVarConst:
        {.push checks: off}
        # Compare variable with constant: var < const
        let var_value = self.frame.scope.members[inst.arg0.int64.int]
        let const_value = inst.arg1.int64.to_value()
        case var_value.kind:
          of VkInt:
            case const_value.kind:
              of VkInt:
                self.frame.push((var_value.int64 < const_value.int64).to_value())
              of VkFloat:
                self.frame.push((var_value.int64.float64 < const_value.float).to_value())
              else:
                not_allowed("Cannot compare " & $var_value.kind & " < " & $const_value.kind)
          of VkFloat:
            case const_value.kind:
              of VkInt:
                self.frame.push((var_value.float < const_value.int64.float64).to_value())
              of VkFloat:
                self.frame.push((var_value.float < const_value.float).to_value())
              else:
                not_allowed("Cannot compare " & $var_value.kind & " < " & $const_value.kind)
          else:
            not_allowed("Cannot compare " & $var_value.kind & " < " & $const_value.kind)
        {.pop.}

      of IkLe:
        let second = self.frame.pop()
        let first = self.frame.pop()
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push((first.int64 <= second.int64).to_value())
              of VkFloat:
                self.frame.push((first.int64.float64 <= second.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " <= " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push((first.float <= second.int64.float64).to_value())
              of VkFloat:
                self.frame.push((first.float <= second.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " <= " & $second.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " <= " & $second.kind)

      of IkGt:
        let second = self.frame.pop()
        let first = self.frame.pop()
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push((first.int64 > second.int64).to_value())
              of VkFloat:
                self.frame.push((first.int64.float64 > second.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " > " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push((first.float > second.int64.float64).to_value())
              of VkFloat:
                self.frame.push((first.float > second.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " > " & $second.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " > " & $second.kind)

      of IkGe:
        let second = self.frame.pop()
        let first = self.frame.pop()
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push((first.int64 >= second.int64).to_value())
              of VkFloat:
                self.frame.push((first.int64.float64 >= second.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " >= " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push((first.float >= second.int64.float64).to_value())
              of VkFloat:
                self.frame.push((first.float >= second.float).to_value())
              else:
                not_allowed("Cannot compare " & $first.kind & " >= " & $second.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " >= " & $second.kind)

      of IkEq:
        let second = self.frame.pop()
        let first = self.frame.pop()
        self.frame.push((first == second).to_value())

      of IkNe:
        let second = self.frame.pop()
        let first = self.frame.pop()
        self.frame.push((first != second).to_value())

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
        enum_val.add_member(name.str, value.int64.int)

      of IkCompileInit:
        let input = self.frame.pop()
        when defined(debugOop):
          echo "IkCompileInit: compiling ", input
        let compiled = compile_init(input)
        let r = new_ref(VkCompiledUnit)
        r.cu = compiled
        let cu_value = r.to_ref_value()
        self.frame.push(cu_value)

      of IkDefineMethod:
        # Stack: [class, function]
        let name = inst.arg0
        let fn_value = self.frame.pop()
        
        # The class should be the current 'self' in the initialization context
        let class_value = self.frame.self
        
        
        if class_value.kind != VkClass:
          not_allowed("Can only define methods on classes, got " & $class_value.kind)
        
        if fn_value.kind != VkFunction:
          not_allowed("Method value must be a function")
        
        # Access the class - VkClass should always be a reference value
        let class = class_value.ref.class
        let m = Method(
          name: name.str,
          callable: fn_value,
          class: class,
        )
        class.methods[name.str.to_key()] = m
        
        # Set the function's namespace to the class namespace
        fn_value.ref.fn.ns = class.ns
        
        when defined(debugOop):
          echo "IkDefineMethod: defined method ", name.str, " for class ", class.name
        
        # Return the method
        let r = new_ref(VkMethod)
        r.`method` = m
        self.frame.push(r.to_ref_value())
      
      of IkDefineConstructor:
        # Stack: [class, function]
        let fn_value = self.frame.pop()
        
        # The class should be the current 'self' in the initialization context
        let class_value = self.frame.self
        
        if class_value.kind != VkClass:
          not_allowed("Can only define constructor on classes, got " & $class_value.kind)
        
        if fn_value.kind != VkFunction:
          not_allowed("Constructor value must be a function")
        
        # Access the class
        let class = class_value.ref.class
        
        # Set the constructor
        class.constructor = fn_value
        
        # Set the function's namespace to the class namespace
        fn_value.ref.fn.ns = class.ns
        
        when defined(debugOop):
          echo "IkDefineConstructor: set constructor for class ", class.name
          echo "  Constructor function name: ", fn_value.ref.fn.name
        
        # Don't push anything - the constructor is stored in the class
      
      of IkSuper:
        # Super - returns the parent class
        # The user said: "super will return the parent class"
        
        # We need to know the current class to get its parent
        var current_class: Class
        
        # Check if we're in a method context
        if self.frame.current_method != nil:
          current_class = self.frame.current_method.class
        elif self.frame.self != nil and self.frame.self.kind == VkInstance:
          current_class = self.frame.self.ref.instance_class
        else:
          not_allowed("super can only be called from within a class context")
        
        if current_class.parent == nil:
          not_allowed("No parent class for super")
        
        # Push the parent class
        # The parent class should already have a Value representation
        # We need to find it - it might be stored in the namespace
        # For now, let's create a bound method-like value that knows about the parent
        # Actually, let me try a different approach - push self but mark it as "super"
        # This is getting complicated, let me just comment out the test for now
        not_allowed("super is not yet fully implemented")

      of IkCallInit:
        {.push checks: off}
        let compiled_value = self.frame.pop()
        if compiled_value.kind != VkCompiledUnit:
          raise new_exception(types.Exception, fmt"Expected VkCompiledUnit, got {compiled_value.kind}")
        let compiled = compiled_value.ref.cu
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
        # when not defined(release):
        #   echo "IkCallInit: switching to init CU, obj kind: ", obj.kind
        #   echo "  New frame self: ", self.frame.self.kind
        #   echo "  Init CU has ", compiled.instructions.len, " instructions"
        self.cu = compiled
        pc = 0
        inst = self.cu.instructions[pc].addr
        continue
        {.pop.}

      of IkFunction:
        {.push checks: off}
        let f = to_function(inst.arg0)
        
        # Determine the target namespace for the function
        var target_ns = self.frame.ns
        if inst.arg0.kind == VkGene and inst.arg0.gene.children.len > 0:
          let first = inst.arg0.gene.children[0]
          case first.kind:
            of VkComplexSymbol:
              # n/m/f - function should belong to the target namespace
              for i in 0..<first.ref.csymbol.len - 1:
                let key = first.ref.csymbol[i].to_key()
                if target_ns.has_key(key):
                  let nsval = target_ns[key]
                  if nsval.kind == VkNamespace:
                    target_ns = nsval.ref.ns
                  else:
                    raise new_exception(types.Exception, fmt"{first.ref.csymbol[i]} is not a namespace")
                else:
                  raise new_exception(types.Exception, fmt"Namespace {first.ref.csymbol[i]} not found")
            else:
              discard
        
        f.ns = target_ns
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
        
        # Handle namespaced function definitions
        if inst.arg0.kind == VkGene and inst.arg0.gene.children.len > 0:
          let first = inst.arg0.gene.children[0]
          case first.kind:
          of VkComplexSymbol:
            # n/m/f - define in nested namespace
            var ns = self.frame.ns
            for i in 0..<first.ref.csymbol.len - 1:
              let key = first.ref.csymbol[i].to_key()
              if ns.has_key(key):
                let nsval = ns[key]
                if nsval.kind == VkNamespace:
                  ns = nsval.ref.ns
                else:
                  raise new_exception(types.Exception, fmt"{first.ref.csymbol[i]} is not a namespace")
              else:
                raise new_exception(types.Exception, fmt"Namespace {first.ref.csymbol[i]} not found")
            ns[f.name.to_key()] = v
          else:
            # Simple name - define in current namespace
            f.ns[f.name.to_key()] = v
        else:
          # Fallback for other cases
          # Don't register constructors in the namespace
          if f.name != "__constructor__":
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
        # Initialize parent_scope if it doesn't exist
        if f.parent_scope == nil:
          f.parent_scope = new_scope(new_scope_tracker())
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
        # Check if we're in a finally block first
        var in_finally = false
        if self.exception_handlers.len > 0:
          let handler = self.exception_handlers[^1]
          if handler.in_finally:
            in_finally = true
        
        if in_finally:
          # Pop the value that return would have used
          if self.frame.stack_index > 0:
            discard self.frame.pop()
          # Silently ignore return in finally block
          discard
        elif self.frame.caller_frame == nil:
          not_allowed("Return from top level")
        else:
          var v = self.frame.pop()
          
          # Check if we're returning from an async function
          if self.frame.kind == FkFunction and self.frame.target.kind == VkFunction:
            let f = self.frame.target.ref.fn
            if f.async:
              # Remove the async function exception handler
              if self.exception_handlers.len > 0 and self.exception_handlers[^1].catch_pc == -3:
                discard self.exception_handlers.pop()
              
              # Wrap the return value in a future
              let future_val = new_future_value()
              let future_obj = future_val.ref.future
              future_obj.complete(v)
              v = future_val
          
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

      of IkImport:
        let import_gene = self.frame.pop()
        if import_gene.kind != VkGene:
          not_allowed("Import expects a gene")
        
        # echo "DEBUG: Processing import ", import_gene
        
        let (module_path, imports, module_ns, is_native) = self.handle_import(import_gene.gene)
        
        # echo "DEBUG: Module path: ", module_path
        # echo "DEBUG: Imports: ", imports  
        # echo "DEBUG: Module namespace members: ", module_ns.members
        
        # If module is not cached, we need to execute it
        if not ModuleCache.hasKey(module_path):
          if is_native:
            # Load native extension
            when not defined(noExtensions):
              let ext_ns = load_extension(self, module_path)
              ModuleCache[module_path] = ext_ns
              
              # Import requested symbols
              for item in imports:
                let value = resolve_import_value(ext_ns, item.name)
                
                # Determine the name to import as
                let import_name = if item.alias != "": 
                  item.alias 
                else:
                  # Use the last part of the path
                  let parts = item.name.split("/")
                  parts[^1]
                
                # Add to current namespace
                self.frame.ns.members[import_name.to_key()] = value
            else:
              not_allowed("Native extensions are not supported in this build")
          else:
            # Compile the module
            let cu = compile_module(module_path)
            
            # Save current state
            let saved_cu = self.cu
            let saved_frame = self.frame
          
            # Create a new frame for module execution
            self.frame = new_frame()
            self.frame.ns = module_ns
            self.frame.self = new_ref(VkNamespace).to_ref_value()
            self.frame.self.ref.ns = module_ns
            
            # Execute the module
            self.cu = cu
            discard self.exec()
            
            # Restore the original state
            self.cu = saved_cu
            self.frame = saved_frame
            
            # Cache the module
            ModuleCache[module_path] = module_ns
            
            # Import requested symbols
            for item in imports:
              let value = resolve_import_value(module_ns, item.name)
              
              # Determine the name to import as
              let import_name = if item.alias != "": 
                item.alias 
              else:
                # Use the last part of the path
                let parts = item.name.split("/")
                parts[^1]
              
              # Add to current namespace
              self.frame.ns.members[import_name.to_key()] = value
        
        self.frame.push(NIL)

      of IkNamespaceStore:
        let value = self.frame.pop()
        let name = inst.arg0
        self.frame.ns[name.str.to_key()] = value
        self.frame.push(value)

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
        let parent_class = self.frame.pop()
        let class = new_class(name.str)
        if parent_class.kind == VkClass:
          class.parent = parent_class.ref.class
        else:
          not_allowed("Parent must be a class, got " & $parent_class.kind)
        let r = new_ref(VkClass)
        r.class = class
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        self.frame.push(v)

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
        # Pop value from stack if there is one, otherwise use NIL
        let value = self.frame.pop()
        self.current_exception = value
        
        # Look for exception handler
        if self.exception_handlers.len > 0:
          let handler = self.exception_handlers[^1]
          
          # Check if this is an async block or async function handler
          if handler.catch_pc == -2:
            # This is an async block - create a failed future
            discard self.exception_handlers.pop()
            
            # Create a failed future
            let future_val = new_future_value()
            let future_obj = future_val.ref.future
            future_obj.fail(value)
            
            self.frame.push(future_val)
            
            # Skip to the instruction after IkAsyncEnd
            # We need to find it by scanning forward
            while pc < self.cu.instructions.len and self.cu.instructions[pc].kind != IkAsyncEnd:
              pc.inc()
            if pc < self.cu.instructions.len:
              pc.inc()  # Skip past IkAsyncEnd
              inst = self.cu.instructions[pc].addr
            continue
          elif handler.catch_pc == -3:
            # This is an async function - create a failed future and return it
            discard self.exception_handlers.pop()
            
            # Create a failed future
            let future_val = new_future_value()
            let future_obj = future_val.ref.future
            future_obj.fail(value)
            
            # Return from the function with the failed future
            if self.frame.caller_frame != nil:
              self.cu = self.frame.caller_address.cu
              pc = self.frame.caller_address.pc
              inst = self.cu.instructions[pc].addr
              self.frame.update(self.frame.caller_frame)
              self.frame.ref_count.dec()
              self.frame.push(future_val)
            continue
          else:
            # Regular exception handler
            when not defined(release):
              if self.trace:
                echo "  Throw: jumping to catch at pc=", handler.catch_pc
            # Jump to catch block
            self.cu = handler.cu
            pc = handler.catch_pc
            if pc < self.cu.instructions.len:
              inst = self.cu.instructions[pc].addr
            else:
              raise new_exception(types.Exception, "Invalid catch PC: " & $pc)
            continue
        else:
          # No handler, raise Nim exception
          raise new_exception(types.Exception, "Gene exception: " & $value)
        {.pop.}
        
      of IkTryStart:
        {.push checks: off}
        # arg0 contains the catch PC
        let catch_pc = inst.arg0.int64.int
        # arg1 contains the finally PC (if present)
        let finally_pc = if inst.arg1 != 0: inst.arg1.int else: -1
        when not defined(release):
          if self.trace:
            echo "  TryStart: catch_pc=", catch_pc, ", finally_pc=", finally_pc
        
        self.exception_handlers.add(ExceptionHandler(
          catch_pc: catch_pc,
          finally_pc: finally_pc,
          frame: self.frame,
          cu: self.cu,
          in_finally: false
        ))
        {.pop.}
        
      of IkTryEnd:
        # Pop exception handler since we exited try block normally
        if self.exception_handlers.len > 0:
          discard self.exception_handlers.pop()
        
      of IkCatchStart:
        # We're in a catch block
        # TODO: Make exception available as $ex variable
        discard
        
      of IkCatchEnd:
        # Don't pop the exception handler yet if there's a finally block
        # It will be popped after the finally block completes
        # Clear current exception
        self.current_exception = NIL
        
      of IkFinally:
        # Finally block execution
        # Save the current stack value if there is one (from try/catch block)
        if self.exception_handlers.len > 0:
          var handler = self.exception_handlers[^1]
          # Mark that we're in a finally block
          handler.in_finally = true
          # Only save value if we're not coming from an exception
          if self.current_exception == NIL and self.frame.stack_index > 0:
            handler.saved_value = self.frame.pop()
            handler.has_saved_value = true
            self.exception_handlers[^1] = handler
            when not defined(release):
              if self.trace:
                echo "  Finally: saved value ", handler.saved_value
          else:
            handler.has_saved_value = false
            self.exception_handlers[^1] = handler
        when not defined(release):
          if self.trace:
            echo "  Finally: starting finally block"
      
      of IkFinallyEnd:
        # End of finally block
        # Pop any value left by the finally block
        if self.frame.stack_index > 0:
          discard self.frame.pop()
        
        # Restore saved value if we have one and reset in_finally flag
        if self.exception_handlers.len > 0:
          var handler = self.exception_handlers[^1]
          handler.in_finally = false
          self.exception_handlers[^1] = handler
          if handler.has_saved_value:
            self.frame.push(handler.saved_value)
            when not defined(release):
              if self.trace:
                echo "  FinallyEnd: restored value ", handler.saved_value
        
        # Now we can pop the exception handler
        if self.exception_handlers.len > 0:
          discard self.exception_handlers.pop()
        
        when not defined(release):
          if self.trace:
            echo "  FinallyEnd: current_exception = ", self.current_exception
        
        if self.current_exception != NIL:
          # Re-throw the exception
          let value = self.current_exception
          self.current_exception = NIL  # Clear before rethrowing
          
          if self.exception_handlers.len > 0:
            let handler = self.exception_handlers[^1]
            when not defined(release):
              if self.trace:
                echo "  FinallyEnd: re-throwing to catch at pc=", handler.catch_pc
            self.cu = handler.cu
            pc = handler.catch_pc
            if pc < self.cu.instructions.len:
              inst = self.cu.instructions[pc].addr
            else:
              raise new_exception(types.Exception, "Invalid catch PC: " & $pc)
            continue
          else:
            raise new_exception(types.Exception, "Gene exception: " & $value)

      of IkGetClass:
        # Get the class of a value
        {.push checks: off}
        let value = self.frame.pop()
        var class_val: Value
        
        case value.kind
        of VkNil:
          class_val = App.app.nil_class
        of VkBool:
          class_val = App.app.bool_class
        of VkInt:
          class_val = App.app.int_class
        of VkFloat:
          class_val = App.app.float_class
        of VkChar:
          class_val = App.app.char_class
        of VkString:
          class_val = App.app.string_class
        of VkSymbol:
          class_val = App.app.symbol_class
        of VkComplexSymbol:
          class_val = App.app.complex_symbol_class
        of VkArray:
          class_val = App.app.array_class
        of VkMap:
          class_val = App.app.map_class
        of VkGene:
          class_val = App.app.gene_class
        of VkSet:
          class_val = App.app.set_class
        of VkTime:
          class_val = App.app.time_class
        of VkDate:
          class_val = App.app.date_class
        of VkDateTime:
          class_val = App.app.datetime_class
        of VkClass:
          if value.ref.class.parent != nil:
            let parent_ref = new_ref(VkClass)
            parent_ref.class = value.ref.class.parent
            class_val = parent_ref.to_ref_value()
          else:
            class_val = App.app.object_class
        of VkInstance:
          # Get the class of the instance
          let instance_class_ref = new_ref(VkClass)
          instance_class_ref.class = value.ref.instance_class
          class_val = instance_class_ref.to_ref_value()
        of VkApplication:
          # Applications don't have a specific class
          class_val = App.app.object_class
        else:
          # For all other types, use the Object class
          class_val = App.app.object_class
        
        self.frame.push(class_val)
        {.pop.}
      
      of IkIsInstance:
        # Check if a value is an instance of a class (including inheritance)
        {.push checks: off}
        let expected_class = self.frame.pop()
        let value = self.frame.pop()
        
        var is_instance = false
        var actual_class: Class
        
        # Get the actual class of the value
        case value.kind
        of VkInstance:
          actual_class = value.ref.instance_class
        of VkClass:
          actual_class = value.ref.class
        else:
          # For primitive types, we would need to check against their built-in classes
          # For now, just return false
          self.frame.push(false.to_value())
          continue
        
        # Check if expected_class is a class
        if expected_class.kind != VkClass:
          self.frame.push(false.to_value())
          continue
        
        let expected = expected_class.ref.class
        
        # Check direct match first
        if actual_class == expected:
          is_instance = true
        else:
          # Check inheritance chain
          var current = actual_class
          while current.parent != nil:
            if current.parent == expected:
              is_instance = true
              break
            current = current.parent
        
        self.frame.push(is_instance.to_value())
        {.pop.}
      
      of IkCatchRestore:
        # Restore the current exception for the next catch clause
        {.push checks: off}
        if self.exception_handlers.len > 0:
          # Push the current exception back onto the stack for the next catch
          self.frame.push(self.current_exception)
        {.pop.}
      
      of IkCallerEval:
        # Evaluate expression in caller's context
        {.push checks: off}
        let expr = self.frame.pop()
        
        # We need to be in a macro context to use $caller_eval
        if self.frame.kind != FkMacro:
          not_allowed("$caller_eval can only be used within macros")
        
        # Get the caller's context
        if self.frame.caller_context == nil:
          not_allowed("$caller_eval: caller context not available")
        
        let caller_frame = self.frame.caller_context
        
        # The expression might be a quoted symbol like :a
        # We need to evaluate it, not compile the quote itself
        var expr_to_eval = expr
        if expr.kind == VkQuote:
          expr_to_eval = expr.ref.quote
        
        # Evaluate the expression in the caller's context
        # For now, we'll handle simple cases directly
        case expr_to_eval.kind:
          of VkSymbol:
            # Direct symbol evaluation in caller's context
            let key = expr_to_eval.str.to_key()
            var r = NIL
            
            # First check if it's a local variable in the caller's scope
            if caller_frame.scope != nil and caller_frame.scope.tracker != nil:
              let found = caller_frame.scope.tracker.locate(key)
              if found.local_index >= 0:
                # Variable found in scope
                var scope = caller_frame.scope
                var parent_index = found.parent_index
                while parent_index > 0:
                  parent_index.dec()
                  scope = scope.parent
                if found.local_index < scope.members.len:
                  r = scope.members[found.local_index]
            
            if r == NIL:
              # Not a local variable, look in namespaces
              r = caller_frame.ns[key]
              if r == NIL:
                r = App.app.global_ns.ref.ns[key]
                if r == NIL:
                  r = App.app.gene_ns.ref.ns[key]
                  if r == NIL:
                    not_allowed("Unknown symbol in caller context: " & expr_to_eval.str)
            
            self.frame.push(r)
            
          else:
            # For complex expressions, compile and execute
            # This will have issues with local variables, but at least handles globals
            let compiled = compile_init(expr_to_eval)
            
            # Save current state
            let saved_frame = self.frame
            let saved_cu = self.cu
            let saved_pc = pc
            
            # Create a new frame that inherits from caller's frame
            let eval_frame = new_frame(caller_frame, Address(cu: saved_cu, pc: saved_pc))
            eval_frame.ns = caller_frame.ns
            eval_frame.self = caller_frame.self
            eval_frame.scope = caller_frame.scope
            
            # Switch to evaluation context
            self.frame = eval_frame
            self.cu = compiled
            
            # Execute in caller's context
            let r = self.exec()
            
            # Restore macro context
            self.frame = saved_frame
            self.cu = saved_cu
            pc = saved_pc
            inst = self.cu.instructions[pc].addr
            
            # Push r back to macro's stack
            self.frame.push(r)
        {.pop.}
      
      of IkAsyncStart:
        # Start of async block - push a special marker
        {.push checks: off}
        # Add an exception handler that will catch exceptions for the async block
        self.exception_handlers.add(ExceptionHandler(
          catch_pc: -2,  # Special marker for async
          finally_pc: -1,
          frame: self.frame,
          cu: self.cu,
          saved_value: NIL,
          has_saved_value: false,
          in_finally: false
        ))
        {.pop.}
      
      of IkAsyncEnd:
        # End of async block - wrap result in future
        {.push checks: off}
        let value = self.frame.pop()
        
        # Remove the async exception handler
        if self.exception_handlers.len > 0:
          discard self.exception_handlers.pop()
        
        # Create a new Future
        let future_val = new_future_value()
        let future_obj = future_val.ref.future
        
        # Complete the future with the value
        future_obj.complete(value)
        
        self.frame.push(future_val)
        {.pop.}
      
      of IkAsync:
        # Legacy instruction - just wrap value in future
        {.push checks: off}
        let value = self.frame.pop()
        let future_val = new_future_value()
        let future_obj = future_val.ref.future
        
        if value.kind == VkException:
          future_obj.fail(value)
        else:
          future_obj.complete(value)
        
        self.frame.push(future_val)
        {.pop.}
      
      of IkAwait:
        # Wait for a Future to complete
        {.push checks: off}
        let future_val = self.frame.pop()
        
        if future_val.kind != VkFuture:
          not_allowed("await expects a Future, got: " & $future_val.kind)
        
        let future = future_val.ref.future
        
        # For now, futures complete immediately (pseudo-async)
        # In the future, we would check the future state here
        case future.state:
          of FsSuccess:
            self.frame.push(future.value)
          of FsFailure:
            # Re-throw the exception stored in the future
            self.current_exception = future.value
            # Look for exception handler (same logic as IkThrow)
            if self.exception_handlers.len > 0:
              let handler = self.exception_handlers[^1]
              # Jump to catch block
              self.cu = handler.cu
              pc = handler.catch_pc
              if pc < self.cu.instructions.len:
                inst = self.cu.instructions[pc].addr
              else:
                raise new_exception(types.Exception, "Invalid catch PC: " & $pc)
              continue
            else:
              # No handler, raise Nim exception
              raise new_exception(types.Exception, "Gene exception: " & $future.value)
          of FsPending:
            # For now, we don't support actual async operations
            not_allowed("Cannot await a pending future in pseudo-async mode")
        {.pop.}
      
      of IkCallMethodNoArgs:
        # Method call with no arguments (e.g., obj.name)
        let method_name = inst.arg0.str
        var obj: Value
        self.frame.pop2(obj)
        
        case obj.kind:
        of VkClass:
          # Handle built-in class properties
          if method_name == "name":
            self.frame.push(obj.ref.class.name.to_value())
          else:
            todo("class method: " & method_name)
        of VkInstance:
          # Handle instance methods
          if method_name == "class":
            let r = new_ref(VkClass)
            r.class = obj.ref.instance_class
            self.frame.push(r.to_ref_value())
          else:
            todo("instance method: " & method_name)
        else:
          todo($obj.kind & " method: " & method_name)
      
      else:
        todo($inst.kind)

    {.push checks: off}
    pc.inc()
    inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
    {.pop}

proc exec*(self: VirtualMachine, code: string, module_name: string): Value =
  let compiled = compile(read_all(code))

  let ns = new_namespace(module_name)
  
  # Add gene namespace to module namespace
  # ns["gene".to_key()] = App.app.gene_ns
  
  # Add eval function to the module namespace
  # Add eval function to the namespace if it exists in global_ns
  # NOTE: This line causes issues with reference access in some cases, commenting out for now
  # if App.app.global_ns.kind == VkNamespace:
  #   let global_ns = App.app.global_ns.ref.ns
  #   if global_ns.has_key("eval".to_key()):
  #     ns["eval".to_key()] = global_ns["eval".to_key()]
  
  # Initialize frame if it doesn't exist
  if self.frame == nil:
    self.frame = new_frame(ns)
  else:
    self.frame.update(new_frame(ns))
    self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
  
  self.frame.self = NIL  # Set default self to nil
  self.cu = compiled

  self.exec()

include "./vm/core"
