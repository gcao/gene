import tables, strutils

import ./types
import "./compiler/if"
import ./fusion

const DEBUG = false

#################### Definitions #################
proc compile*(self: Compiler, input: Value)
proc compile_with(self: Compiler, gene: ptr Gene)
proc compile_tap(self: Compiler, gene: ptr Gene)
proc compile_parse(self: Compiler, gene: ptr Gene)
proc compile_render(self: Compiler, gene: ptr Gene)
proc compile_emit(self: Compiler, gene: ptr Gene)

proc compile(self: Compiler, input: seq[Value]) =
  for i, v in input:
    self.compile(v)
    if i < input.len - 1:
      self.output.instructions.add(Instruction(kind: IkPop))

proc compile_literal(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))

# Translate $x to gene/x and $x/y to gene/x/y
proc translate_symbol(input: Value): Value =
  case input.kind:
    of VkSymbol:
      let s = input.str
      if s.starts_with("$"):
        # Special case for $ns - translate to special symbol
        if s == "$ns":
          result = cast[Value](SYM_NS)
        else:
          result = @["gene", s[1..^1]].to_complex_symbol()
      else:
        result = input
    of VkComplexSymbol:
      result = input
      let r = input.ref
      if r.csymbol[0] == "":
        r.csymbol[0] = "self"
      elif r.csymbol[0].starts_with("$"):
        # Special case for $ns - translate first part to special symbol  
        if r.csymbol[0] == "$ns":
          r.csymbol[0] = "SPECIAL_NS"
        else:
          r.csymbol.insert("gene", 0)
          r.csymbol[1] = r.csymbol[1][1..^1]
    else:
      not_allowed($input)

proc compile_complex_symbol(self: Compiler, input: Value) =
  if self.quote_level > 0:
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))
  else:
    let r = translate_symbol(input).ref
    let key = r.csymbol[0].to_key()
    if r.csymbol[0] == "SPECIAL_NS":
      # Handle $ns/... specially
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: cast[Value](SYM_NS)))
    elif self.scope_tracker.mappings.has_key(key):
      self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: self.scope_tracker.mappings[key].to_value()))
    else:
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
    for s in r.csymbol[1..^1]:
      let (is_int, i) = to_int(s)
      if is_int:
        self.output.instructions.add(Instruction(kind: IkGetChild, arg0: i))
      elif s.starts_with("."):
        self.output.instructions.add(Instruction(kind: IkCallMethodNoArgs, arg0: s[1..^1]))
      elif s == "...":
        # Handle spread operator for variables like "a..."
        self.output.instructions.add(Instruction(kind: IkSpread))
      else:
        self.output.instructions.add(Instruction(kind: IkGetMember, arg0: s.to_key()))

proc compile_symbol(self: Compiler, input: Value) =
  if self.quote_level > 0:
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))
  else:
    let input = translate_symbol(input)
    if input.kind == VkSymbol:
      let symbol_str = input.str
      if symbol_str == "self":
        # Special handling for self - push the current frame's self
        self.output.instructions.add(Instruction(kind: IkPushSelf))
        return
      elif symbol_str == "super":
        # Special handling for super - will be handled differently when it's a function call
        self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))
        return
      elif symbol_str.startsWith("@") and symbol_str.len > 1:
        # Handle @shorthand syntax: @test -> (@ "test"), @0 -> (@ 0)
        let selector = new_gene("@".to_symbol_value())
        let prop_name = symbol_str[1..^1]
        
        # Check if it contains / for complex selectors like @test/0
        if "/" in prop_name:
          # Handle @test/0 or @0/test
          let parts = prop_name.split("/")
          for part in parts:
            # Try to parse as int for numeric indices
            try:
              let index = parseInt(part)
              selector.children.add(index.to_value())
            except ValueError:
              selector.children.add(part.to_value())
        else:
          # Simple @test case
          # Try to parse as int for @0 syntax
          try:
            let index = parseInt(prop_name)
            selector.children.add(index.to_value())
          except ValueError:
            selector.children.add(prop_name.to_value())
        
        self.output.instructions.add(Instruction(kind: IkPushValue, arg0: selector.to_gene_value()))
        return
      elif symbol_str.endsWith("..."):
        # Handle variable spread like "a..." - strip the ... and add spread
        let base_symbol = symbol_str[0..^4].to_symbol_value()  # Remove "..."
        let key = base_symbol.str.to_key()
        let found = self.scope_tracker.locate(key)
        if found.local_index >= 0:
          if found.parent_index == 0:
            self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
          else:
            self.output.instructions.add(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
        else:
          self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
        self.output.instructions.add(Instruction(kind: IkSpread))
        return
      let key = input.str.to_key()
      let found = self.scope_tracker.locate(key)
      if found.local_index >= 0:
        if found.parent_index == 0:
          self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
        else:
          self.output.instructions.add(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
      else:
        self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
    elif input.kind == VkComplexSymbol:
      self.compile_complex_symbol(input)

proc compile_array(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkArrayStart))
  for child in input.ref.arr:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkArrayAddChild))
  self.output.instructions.add(Instruction(kind: IkArrayEnd))

proc compile_map(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkMapStart))
  for k, v in input.ref.map:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkMapSetProp, arg0: k))
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
    self.output.instructions.add(Instruction(kind: IkScopeStart, arg0: self.scope_tracker.to_value()))
    # Mark that we added a scope start, even for empty scopes
    self.scope_tracker.scope_started = true

proc end_scope(self: Compiler) =
  # If we added a ScopeStart (either because we have variables or we explicitly marked it),
  # we need to add the corresponding ScopeEnd
  if self.scope_tracker.next_index > 0 or self.scope_tracker.scope_started:
    self.output.instructions.add(Instruction(kind: IkScopeEnd))
  discard self.scope_trackers.pop()

proc compile_if(self: Compiler, gene: ptr Gene) =
  normalize_if(gene)

  self.start_scope()

  # Compile main condition
  self.compile(gene.props[COND_KEY.to_key()])
  var next_label = new_label()
  let end_label = new_label()
  self.output.instructions.add(Instruction(kind: IkJumpIfFalse, arg0: next_label.to_value()))

  # Compile then branch
  self.start_scope()
  self.compile(gene.props[THEN_KEY.to_key()])
  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.to_value()))

  # Handle elif branches if they exist
  if gene.props.has_key(ELIF_KEY.to_key()):
    let elifs = gene.props[ELIF_KEY.to_key()]
    case elifs.kind:
      of VkArray:
        # Process elif conditions and bodies in pairs
        for i in countup(0, elifs.ref.arr.len - 1, 2):
          self.output.instructions.add(Instruction(kind: IkNoop, label: next_label))
          
          if i < elifs.ref.arr.len - 1:
            # Compile elif condition
            self.compile(elifs.ref.arr[i])
            next_label = new_label()
            self.output.instructions.add(Instruction(kind: IkJumpIfFalse, arg0: next_label.to_value()))
            
            # Compile elif body
            self.start_scope()
            self.compile(elifs.ref.arr[i + 1])
            self.end_scope()
            self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.to_value()))
      else:
        discard

  # Compile else branch
  self.output.instructions.add(Instruction(kind: IkNoop, label: next_label))
  self.start_scope()
  self.compile(gene.props[ELSE_KEY.to_key()])
  self.end_scope()

  self.output.instructions.add(Instruction(kind: IkNoop, label: end_label))

  self.end_scope()

proc compile_caller_eval(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_async(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_await(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_selector(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_at_selector(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_set(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_import(self: Compiler, gene: ptr Gene)  # Forward declaration

proc compile_var(self: Compiler, gene: ptr Gene) =
  let name = gene.children[0]
  
  # Handle namespace variables like $ns/a
  if name.kind == VkComplexSymbol:
    let parts = name.ref.csymbol
    if parts.len >= 2 and parts[0] == "$ns":
      # This is a namespace variable, store it directly in namespace
      if gene.children.len > 1:
        # Compile the value
        self.compile(gene.children[1])
      else:
        # No value, use NIL
        self.output.instructions.add(Instruction(kind: IkPushValue, arg0: NIL))
      
      # Store in namespace
      let var_name = parts[1..^1].join("/")
      self.output.instructions.add(Instruction(kind: IkNamespaceStore, arg0: var_name.to_symbol_value()))
      return
  
  # Regular variable handling
  if name.kind != VkSymbol:
    not_allowed("Variable name must be a symbol")
    
  let index = self.scope_tracker.next_index
  self.scope_tracker.mappings[name.str.to_key()] = index
  if gene.children.len > 1:
    self.compile(gene.children[1])
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    self.output.instructions.add(Instruction(kind: IkVar, arg0: index.to_value()))
  else:
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    self.output.instructions.add(Instruction(kind: IkVarValue, arg0: NIL, arg1: index))

proc compile_assignment(self: Compiler, gene: ptr Gene) =
  let `type` = gene.type
  let operator = gene.children[0].str
  
  if `type`.kind == VkSymbol:
    # For compound assignment, we need to load the current value first
    if operator != "=":
      let key = `type`.str.to_key()
      let found = self.scope_tracker.locate(key)
      if found.local_index >= 0:
        if found.parent_index == 0:
          self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
        else:
          self.output.instructions.add(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
      else:
        self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
      
      # Compile the right-hand side value
      self.compile(gene.children[1])
      
      # Apply the operation
      case operator:
        of "+=":
          self.output.instructions.add(Instruction(kind: IkAdd))
        of "-=":
          self.output.instructions.add(Instruction(kind: IkSub))
        else:
          not_allowed("Unsupported compound assignment operator: " & operator)
    else:
      # Regular assignment - compile the value
      self.compile(gene.children[1])
    
    # Store the result
    let key = `type`.str.to_key()
    let found = self.scope_tracker.locate(key)
    if found.local_index >= 0:
      if found.parent_index == 0:
        self.output.instructions.add(Instruction(kind: IkVarAssign, arg0: found.local_index.to_value()))
      else:
        self.output.instructions.add(Instruction(kind: IkVarAssignInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
    else:
      self.output.instructions.add(Instruction(kind: IkAssign, arg0: `type`))
  elif `type`.kind == VkComplexSymbol:
    let r = translate_symbol(`type`).ref
    let key = r.csymbol[0].to_key()
    
    # Load the target object first (for both regular and compound assignment)
    if r.csymbol[0] == "SPECIAL_NS":
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: cast[Value](SYM_NS)))
    elif self.scope_tracker.mappings.has_key(key):
      self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: self.scope_tracker.mappings[key].to_value()))
    else:
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
      
    # Navigate to parent object (if nested property access)
    if r.csymbol.len > 2:
      for s in r.csymbol[1..^2]:
        let (is_int, i) = to_int(s)
        if is_int:
          self.output.instructions.add(Instruction(kind: IkGetChild, arg0: i))
        elif s.starts_with("."):
          self.output.instructions.add(Instruction(kind: IkCallMethodNoArgs, arg0: s[1..^1]))
        else:
          self.output.instructions.add(Instruction(kind: IkGetMember, arg0: s.to_key()))
    
    if operator != "=":
      # For compound assignment, duplicate the target object on the stack
      # Stack: [target] -> [target, target]
      self.output.instructions.add(Instruction(kind: IkDup))
      
      # Get current value
      let last_segment = r.csymbol[^1]
      let (is_int, i) = to_int(last_segment)
      if is_int:
        self.output.instructions.add(Instruction(kind: IkGetChild, arg0: i))
      else:
        self.output.instructions.add(Instruction(kind: IkGetMember, arg0: last_segment.to_key()))
      
      # Compile the right-hand side value
      self.compile(gene.children[1])
      
      # Apply the operation
      case operator:
        of "+=":
          self.output.instructions.add(Instruction(kind: IkAdd))
        of "-=":
          self.output.instructions.add(Instruction(kind: IkSub))
        else:
          not_allowed("Unsupported compound assignment operator: " & operator)
      
      # Now stack should be: [target, new_value]
      # Set the property
      let last_segment2 = r.csymbol[^1]
      let (is_int2, i2) = to_int(last_segment2)
      if is_int2:
        self.output.instructions.add(Instruction(kind: IkSetChild, arg0: i2))
      else:
        self.output.instructions.add(Instruction(kind: IkSetMember, arg0: last_segment2.to_key()))
    else:
      # Regular assignment
      self.compile(gene.children[1])
      
      let last_segment = r.csymbol[^1]
      let (is_int, i) = to_int(last_segment)
      if is_int:
        self.output.instructions.add(Instruction(kind: IkSetChild, arg0: i))
      else:
        self.output.instructions.add(Instruction(kind: IkSetMember, arg0: last_segment.to_key()))
  else:
    not_allowed($`type`)

proc compile_loop(self: Compiler, gene: ptr Gene) =
  let start_label = new_label()
  let end_label = new_label()
  
  # Track this loop
  self.loop_stack.add(LoopInfo(start_label: start_label, end_label: end_label))
  
  self.output.instructions.add(Instruction(kind: IkLoopStart, label: start_label))
  self.compile(gene.children)
  self.output.instructions.add(Instruction(kind: IkContinue, arg0: start_label.to_value()))
  self.output.instructions.add(Instruction(kind: IkLoopEnd, label: end_label))
  
  # Pop loop from stack
  discard self.loop_stack.pop()

proc compile_while(self: Compiler, gene: ptr Gene) =
  if gene.children.len < 1:
    not_allowed("while expects at least 1 argument (condition)")
  
  let label = new_label()
  let end_label = new_label()
  
  # Track this loop
  self.loop_stack.add(LoopInfo(start_label: label, end_label: end_label))
  
  # Mark loop start
  self.output.instructions.add(Instruction(kind: IkLoopStart, label: label))
  
  # Compile and test condition
  self.compile(gene.children[0])
  self.output.instructions.add(Instruction(kind: IkJumpIfFalse, arg0: end_label.to_value()))
  
  # Compile body (remaining children)
  if gene.children.len > 1:
    for i in 1..<gene.children.len:
      self.compile(gene.children[i])
  
  # Jump back to condition
  self.output.instructions.add(Instruction(kind: IkContinue, arg0: label.to_value()))
  
  # Mark loop end
  self.output.instructions.add(Instruction(kind: IkLoopEnd, label: end_label))
  
  # Pop loop from stack
  discard self.loop_stack.pop()

proc compile_repeat(self: Compiler, gene: ptr Gene) =
  if gene.children.len < 1:
    not_allowed("repeat expects at least 1 argument (count)")
  
  # For now, implement a simple version without index/total variables
  if gene.props.has_key(INDEX_KEY.to_key()) or gene.props.has_key(TOTAL_KEY.to_key()):
    not_allowed("repeat with index/total variables not yet implemented in VM")
  
  let start_label = new_label()
  let end_label = new_label()
  
  # Track this loop
  self.loop_stack.add(LoopInfo(start_label: start_label, end_label: end_label))
  
  # Compile count expression
  self.compile(gene.children[0])
  
  # Initialize loop counter to 0
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: 0.to_value()))
  
  # Don't create a scope for the loop body - let each iteration handle its own scoping
  
  # Mark loop start
  self.output.instructions.add(Instruction(kind: IkLoopStart, label: start_label))
  
  # Stack: [count, counter]
  # Check if counter < count
  self.output.instructions.add(Instruction(kind: IkDup2))   # [count, counter, count, counter]
  self.output.instructions.add(Instruction(kind: IkSwap))   # [count, counter, counter, count]
  self.output.instructions.add(Instruction(kind: IkLt))     # [count, counter, bool]
  self.output.instructions.add(Instruction(kind: IkJumpIfFalse, arg0: end_label.to_value()))
  
  # Compile body - wrap in a scope to isolate each iteration
  if gene.children.len > 1:
    # Start a new scope for this iteration
    self.start_scope()
    
    for i in 1..<gene.children.len:
      self.compile(gene.children[i])
      # Pop the result (we don't need it)
      self.output.instructions.add(Instruction(kind: IkPop))
    
    # End the iteration scope
    self.end_scope()
  
  # Increment counter: Stack is [count, counter]
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: 1.to_value()))  # [count, counter, 1]
  self.output.instructions.add(Instruction(kind: IkAdd))  # [count, counter+1]
  
  # Jump back to condition check
  self.output.instructions.add(Instruction(kind: IkContinue, arg0: start_label.to_value()))
  
  # Mark loop end
  self.output.instructions.add(Instruction(kind: IkLoopEnd, label: end_label))
  
  # Clean up stack (pop counter and count)
  self.output.instructions.add(Instruction(kind: IkPop))  # Remove counter
  self.output.instructions.add(Instruction(kind: IkPop))  # Remove count
  
  # No scope to end - each iteration handles its own scoping
  
  # Push nil as the result
  self.output.instructions.add(Instruction(kind: IkPushNil))
  
  # Pop loop from stack
  discard self.loop_stack.pop()

proc compile_for(self: Compiler, gene: ptr Gene) =
  # (for var in collection body...)
  if gene.children.len < 2:
    not_allowed("for expects at least 2 arguments (variable and collection)")
  
  let var_node = gene.children[0]
  if var_node.kind != VkSymbol:
    not_allowed("for loop variable must be a symbol")
  
  # Check for 'in' keyword
  if gene.children.len < 3 or gene.children[1].kind != VkSymbol or gene.children[1].str != "in":
    not_allowed("for loop requires 'in' keyword")
  
  let var_name = var_node.str
  let collection = gene.children[2]
  
  # Create a scope for the entire for loop to hold temporary variables
  self.start_scope()
  
  # Store collection in a temporary variable
  self.compile(collection)
  let collection_index = self.scope_tracker.next_index
  self.scope_tracker.mappings["$for_collection".to_key()] = collection_index
  self.add_scope_start()
  self.scope_tracker.next_index.inc()
  self.output.instructions.add(Instruction(kind: IkVar, arg0: collection_index.to_value()))
  
  # Store index in a temporary variable, initialized to 0
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: 0.to_value()))
  let index_var = self.scope_tracker.next_index
  self.scope_tracker.mappings["$for_index".to_key()] = index_var
  self.scope_tracker.next_index.inc()
  self.output.instructions.add(Instruction(kind: IkVar, arg0: index_var.to_value()))
  
  let start_label = new_label()
  let end_label = new_label()
  
  # Track this loop
  self.loop_stack.add(LoopInfo(start_label: start_label, end_label: end_label))
  
  # Mark loop start
  self.output.instructions.add(Instruction(kind: IkLoopStart, label: start_label))
  
  # Check if index < collection.length
  # Load index
  self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: index_var.to_value()))
  # Load collection
  self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: collection_index.to_value()))
  # Get length
  self.output.instructions.add(Instruction(kind: IkLen))
  # Compare
  self.output.instructions.add(Instruction(kind: IkLt))
  self.output.instructions.add(Instruction(kind: IkJumpIfFalse, arg0: end_label.to_value()))
  
  # Create scope for loop iteration
  self.start_scope()
  
  # Get current element: collection[index]
  # Load collection
  self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: collection_index.to_value()))
  # Load index
  self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: index_var.to_value()))
  # Get element
  self.output.instructions.add(Instruction(kind: IkGetChildDynamic))
  
  # Store element in loop variable
  let var_index = self.scope_tracker.next_index
  self.scope_tracker.mappings[var_name.to_key()] = var_index
  self.add_scope_start()
  self.scope_tracker.next_index.inc()
  self.output.instructions.add(Instruction(kind: IkVar, arg0: var_index.to_value()))
  
  # Compile body (remaining children after 'in' and collection)
  if gene.children.len > 3:
    for i in 3..<gene.children.len:
      self.compile(gene.children[i])
      # Pop the result (we don't need it)
      self.output.instructions.add(Instruction(kind: IkPop))
  
  # End the iteration scope
  self.end_scope()
  
  # Increment index
  # Load current index
  self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: index_var.to_value()))
  # Add 1
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: 1.to_value()))
  self.output.instructions.add(Instruction(kind: IkAdd))
  # Store back
  self.output.instructions.add(Instruction(kind: IkVarAssign, arg0: index_var.to_value()))
  
  # Jump back to condition check
  self.output.instructions.add(Instruction(kind: IkContinue, arg0: start_label.to_value()))
  
  # Mark loop end
  self.output.instructions.add(Instruction(kind: IkLoopEnd, label: end_label))
  
  # End the for loop scope
  self.end_scope()
  
  # Push nil as the result
  self.output.instructions.add(Instruction(kind: IkPushNil))
  
  # Pop loop from stack
  discard self.loop_stack.pop()

proc compile_enum(self: Compiler, gene: ptr Gene) =
  # (enum Color red green blue)
  # (enum Status ^values [ok error pending])
  if gene.children.len < 1:
    not_allowed("enum expects at least a name")
  
  let name_node = gene.children[0]
  if name_node.kind != VkSymbol:
    not_allowed("enum name must be a symbol")
  
  let enum_name = name_node.str
  
  # Create the enum
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: enum_name.to_value()))
  self.output.instructions.add(Instruction(kind: IkCreateEnum))
  
  # Check if ^values prop is used
  var start_idx = 1
  if gene.props.has_key("values".to_key()):
    # Values are provided in the ^values property
    let values_array = gene.props["values".to_key()]
    if values_array.kind != VkArray:
      not_allowed("enum ^values must be an array")
    
    var value = 0
    for member in values_array.ref.arr:
      if member.kind != VkSymbol:
        not_allowed("enum member must be a symbol")
      # Push member name and value
      self.output.instructions.add(Instruction(kind: IkPushValue, arg0: member.str.to_value()))
      self.output.instructions.add(Instruction(kind: IkPushValue, arg0: value.to_value()))
      self.output.instructions.add(Instruction(kind: IkEnumAddMember))
      value.inc()
  else:
    # Members are provided as children
    var value = 0
    var i = start_idx
    while i < gene.children.len:
      let member = gene.children[i]
      if member.kind != VkSymbol:
        not_allowed("enum member must be a symbol")
      
      # Check if next child is '=' for custom value
      if i + 2 < gene.children.len and 
         gene.children[i + 1].kind == VkSymbol and 
         gene.children[i + 1].str == "=":
        # Custom value provided
        i += 2
        if gene.children[i].kind != VkInt:
          not_allowed("enum member value must be an integer")
        value = gene.children[i].int
      
      # Push member name and value
      self.output.instructions.add(Instruction(kind: IkPushValue, arg0: member.str.to_value()))
      self.output.instructions.add(Instruction(kind: IkPushValue, arg0: value.to_value()))
      self.output.instructions.add(Instruction(kind: IkEnumAddMember))
      
      value.inc()
      i.inc()
  
  # Store the enum in the namespace  
  let index = self.scope_tracker.next_index
  self.scope_tracker.mappings[enum_name.to_key()] = index
  self.add_scope_start()
  self.scope_tracker.next_index.inc()
  self.output.instructions.add(Instruction(kind: IkVar, arg0: index.to_value()))

proc compile_break(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  
  if self.loop_stack.len == 0:
    # Emit a break with label -1 to indicate no loop
    # This will be checked at runtime
    self.output.instructions.add(Instruction(kind: IkBreak, arg0: (-1).to_value()))
  else:
    # Get the current loop's end label
    let current_loop = self.loop_stack[^1]
    self.output.instructions.add(Instruction(kind: IkBreak, arg0: current_loop.end_label.to_value()))

proc compile_continue(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  
  if self.loop_stack.len == 0:
    # Emit a continue with label -1 to indicate no loop
    # This will be checked at runtime
    self.output.instructions.add(Instruction(kind: IkContinue, arg0: (-1).to_value()))
  else:
    # Get the current loop's start label
    let current_loop = self.loop_stack[^1]
    self.output.instructions.add(Instruction(kind: IkContinue, arg0: current_loop.start_label.to_value()))

proc compile_throw(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    # Throw with a value
    self.compile(gene.children[0])
  else:
    # Throw without a value (re-throw current exception)
    self.output.instructions.add(Instruction(kind: IkPushNil))
  self.output.instructions.add(Instruction(kind: IkThrow))

proc compile_try(self: Compiler, gene: ptr Gene) =
  let catch_end_label = new_label()
  let finally_label = new_label()
  let end_label = new_label()
  
  # Check if there's a finally block
  var has_finally = false
  var finally_idx = -1
  for idx in 0..<gene.children.len:
    if gene.children[idx].kind == VkSymbol and gene.children[idx].str == "finally":
      has_finally = true
      finally_idx = idx
      break
  
  # Mark start of try block
  # If we have a finally, catch handler should point to finally_label
  if has_finally:
    self.output.instructions.add(Instruction(kind: IkTryStart, arg0: catch_end_label.to_value(), arg1: finally_label))
  else:
    self.output.instructions.add(Instruction(kind: IkTryStart, arg0: catch_end_label.to_value()))
  
  # Compile try body
  var i = 0
  while i < gene.children.len:
    let child = gene.children[i]
    if child.kind == VkSymbol and (child.str == "catch" or child.str == "finally"):
      break
    self.compile(child)
    inc i
  
  # Mark end of try block
  self.output.instructions.add(Instruction(kind: IkTryEnd))
  
  # If we have a finally block, we need to preserve the try block's value
  if has_finally:
    # The try block's value is on the stack - we'll handle it in the finally section
    self.output.instructions.add(Instruction(kind: IkJump, arg0: finally_label.to_value()))
  else:
    self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.to_value()))
  
  # Handle catch blocks
  self.output.instructions.add(Instruction(kind: IkNoop, label: catch_end_label))
  var catch_count = 0
  while i < gene.children.len:
    let child = gene.children[i]
    if child.kind == VkSymbol and child.str == "catch":
      inc i
      if i < gene.children.len:
        # Get the catch pattern
        let pattern = gene.children[i]
        inc i
        
        var next_catch_label: Label
        let is_catch_all = pattern.kind == VkSymbol and pattern.str == "*"
        
        # Generate catch matching code
        if is_catch_all:
          # Catch all - no need to check type
          self.output.instructions.add(Instruction(kind: IkCatchStart))
        else:
          # Type-specific catch
          next_catch_label = new_label()
          
          # Check if exception matches this type
          self.output.instructions.add(Instruction(kind: IkCatchStart))
          
          # Load the current exception and check its type
          self.output.instructions.add(Instruction(kind: IkPushValue, arg0: App.app.gene_ns))
          self.output.instructions.add(Instruction(kind: IkGetMember, arg0: "ex".to_key().to_value()))
          
          # Get the class of the exception
          self.output.instructions.add(Instruction(kind: IkGetClass))
          
          # Load the expected exception type
          self.compile(pattern)
          
          # Check if they match (including inheritance)
          self.output.instructions.add(Instruction(kind: IkIsInstance))
          
          # If not a match, jump to next catch
          self.output.instructions.add(Instruction(kind: IkJumpIfFalse, arg0: next_catch_label.to_value()))
        
        # Compile catch body
        while i < gene.children.len:
          let body_child = gene.children[i]
          if body_child.kind == VkSymbol and (body_child.str == "catch" or body_child.str == "finally"):
            break
          self.compile(body_child)
          inc i
        
        self.output.instructions.add(Instruction(kind: IkCatchEnd))
        # Jump to finally if exists, otherwise to end
        if has_finally:
          self.output.instructions.add(Instruction(kind: IkJump, arg0: finally_label.to_value()))
        else:
          self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.to_value()))
        
        # Add label for next catch if this was a type-specific catch
        if not is_catch_all:
          self.output.instructions.add(Instruction(kind: IkNoop, label: next_catch_label))
          # Pop the exception handler and push it back for the next catch
          self.output.instructions.add(Instruction(kind: IkCatchRestore))
        
        catch_count.inc
    elif child.kind == VkSymbol and child.str == "finally":
      break
    else:
      inc i
  
  # If no catch blocks handled the exception, re-throw
  if catch_count > 0:
    self.output.instructions.add(Instruction(kind: IkThrow))
  
  # Handle finally block
  if has_finally:
    self.output.instructions.add(Instruction(kind: IkNoop, label: finally_label))
    self.output.instructions.add(Instruction(kind: IkFinally))
    
    # Compile finally body
    i = finally_idx + 1
    while i < gene.children.len:
      self.compile(gene.children[i])
      inc i
    
    self.output.instructions.add(Instruction(kind: IkFinallyEnd))
  
  self.output.instructions.add(Instruction(kind: IkNoop, label: end_label))

proc compile_fn(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkFunction, arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = copy_scope_tracker(self.scope_tracker)  # Create a copy, not a reference
  self.output.instructions.add(Instruction(kind: IkNoop, arg0: r.to_ref_value()))

proc compile_return(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  self.output.instructions.add(Instruction(kind: IkReturn))

proc compile_macro(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkMacro, arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(Instruction(kind: IkNoop, arg0: r.to_ref_value()))

proc compile_block(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkBlock, arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(Instruction(kind: IkNoop, arg0: r.to_ref_value()))

proc compile_compile(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkCompileFn, arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(Instruction(kind: IkNoop, arg0: r.to_ref_value()))

proc compile_ns(self: Compiler, gene: ptr Gene) =
  self.output.instructions.add(Instruction(kind: IkNamespace, arg0: gene.children[0]))
  if gene.children.len > 1:
    let body = new_stream_value(gene.children[1..^1])
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: body))
    self.output.instructions.add(Instruction(kind: IkCompileInit))
    self.output.instructions.add(Instruction(kind: IkCallInit))

proc compile_method_definition(self: Compiler, gene: ptr Gene) =
  # Method definition: (.fn name args body...)
  if gene.children.len < 3:
    not_allowed("Method definition requires at least name, args and body")
  
  let name = gene.children[0]
  if name.kind != VkSymbol:
    not_allowed("Method name must be a symbol")
  
  # Create a function from the method definition
  # The method is similar to (fn name args body...) but bound to the class
  var fn_value = new_gene_value()
  fn_value.gene.type = "fn".to_symbol_value()
  for i in 0..<gene.children.len:
    fn_value.gene.children.add(gene.children[i])
  
  # Compile the function definition
  self.compile_fn(fn_value)
  
  # Add the method to the class
  self.output.instructions.add(Instruction(kind: IkDefineMethod, arg0: name))

proc compile_constructor_definition(self: Compiler, gene: ptr Gene) =
  # Constructor definition: (.ctor args body...)
  if gene.children.len < 2:
    not_allowed("Constructor definition requires at least args and body")
  
  # Create a function from the constructor definition
  # The constructor is similar to (fn new args body...) but bound to the class
  var fn_value = new_gene_value()
  fn_value.gene.type = "fn".to_symbol_value()
  # Add "new" as the function name
  fn_value.gene.children.add("new".to_symbol_value())
  # Add remaining children (args and body)
  for i in 0..<gene.children.len:
    fn_value.gene.children.add(gene.children[i])
  
  # Compile the function definition
  self.compile_fn(fn_value)
  
  # Set as constructor for the class
  self.output.instructions.add(Instruction(kind: IkDefineConstructor))

proc compile_class(self: Compiler, gene: ptr Gene) =
  var body_start = 1
  if gene.children.len >= 3 and gene.children[1] == "<".to_symbol_value():
    body_start = 3
    self.compile(gene.children[2])
    self.output.instructions.add(Instruction(kind: IkSubClass, arg0: gene.children[0]))
  else:
    self.output.instructions.add(Instruction(kind: IkClass, arg0: gene.children[0]))

  if gene.children.len > body_start:
    let body = new_stream_value(gene.children[body_start..^1])
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: body))
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

proc compile_super(self: Compiler, gene: ptr Gene) =
  # Super: returns the parent class
  # Usage: (super .method args...)
  if gene.children.len > 0:
    not_allowed("super takes no arguments")
  
  # Push the parent class
  self.output.instructions.add(Instruction(kind: IkSuper))

proc compile_match(self: Compiler, gene: ptr Gene) =
  # Match statement: (match pattern value)
  if gene.children.len != 2:
    not_allowed("match expects exactly 2 arguments: pattern and value")
  
  let pattern = gene.children[0]
  let value = gene.children[1]
  
  # Compile the value expression
  self.compile(value)
  
  # For now, handle simple variable binding: (match a [1])
  if pattern.kind == VkSymbol:
    # Simple variable binding - match doesn't create a new scope
    let var_name = pattern.str
    
    # Check if we're in a scope
    if self.scope_trackers.len == 0:
      not_allowed("match must be used within a scope")
    
    let var_index = self.scope_tracker.next_index
    self.scope_tracker.mappings[var_name.to_key()] = var_index
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    
    # Store the value in the variable
    self.output.instructions.add(Instruction(kind: IkVar, arg0: var_index.to_value()))
    
    # Push nil as the result of match
    self.output.instructions.add(Instruction(kind: IkPushNil))
  elif pattern.kind == VkArray:
    # Array pattern matching: (match [a b] [1 2])
    # For now, handle simple array destructuring
    
    # Store the value temporarily
    self.output.instructions.add(Instruction(kind: IkDup))
    
    for i, elem in pattern.ref.arr:
      if elem.kind == VkSymbol:
        # Extract element at index i
        self.output.instructions.add(Instruction(kind: IkDup))  # Duplicate the array
        self.output.instructions.add(Instruction(kind: IkPushValue, arg0: i.to_value()))
        self.output.instructions.add(Instruction(kind: IkGetMember))
        
        # Store in variable
        let var_name = elem.str
        let var_index = self.scope_tracker.next_index
        self.scope_tracker.mappings[var_name.to_key()] = var_index
        self.add_scope_start()
        self.scope_tracker.next_index.inc()
        self.output.instructions.add(Instruction(kind: IkVar, arg0: var_index.to_value()))
    
    # Pop the original array
    self.output.instructions.add(Instruction(kind: IkPop))
    
    # Push nil as the result of match
    self.output.instructions.add(Instruction(kind: IkPushNil))
  else:
    not_allowed("Unsupported pattern type: " & $pattern.kind)

proc compile_range(self: Compiler, gene: ptr Gene) =
  # (range start end) or (range start end step)
  if gene.children.len < 2:
    not_allowed("range requires at least 2 arguments")
  
  self.compile(gene.children[0])  # start
  self.compile(gene.children[1])  # end
  
  if gene.children.len >= 3:
    self.compile(gene.children[2])  # step
  else:
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: NIL))  # default step
  
  self.output.instructions.add(Instruction(kind: IkCreateRange))

proc compile_range_operator(self: Compiler, gene: ptr Gene) =
  # (a .. b) -> (range a b)
  if gene.children.len != 2:
    not_allowed(".. operator requires exactly 2 arguments")
  
  self.compile(gene.children[0])  # start
  self.compile(gene.children[1])  # end
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: NIL))  # default step
  self.output.instructions.add(Instruction(kind: IkCreateRange))

proc compile_gene_default(self: Compiler, gene: ptr Gene) {.inline.} =
  self.output.instructions.add(Instruction(kind: IkGeneStart))
  self.compile(gene.type)
  self.output.instructions.add(Instruction(kind: IkGeneSetType))
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
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
  # Special case: handle @ selector application
  # ((@ "test") {^test 1}) - gene.type is (@ "test"), children is [{^test 1}]
  if gene.type.kind == VkGene and gene.type.gene.type == "@".to_symbol_value():
    # This is a selector being applied
    if gene.children.len != 1:
      not_allowed("@ selector expects exactly 1 argument when called")
    
    # Compile as (./ target property)
    # gene.children[0] is the target
    # gene.type.gene.children[0] is the property
    self.compile(gene.children[0])  # target
    self.compile(gene.type.gene.children[0])  # property
    self.output.instructions.add(Instruction(kind: IkGetMemberOrNil))
    return
  
  # Check for selector syntax: (target ./ property) or (target ./property)
  if DEBUG:
    echo "DEBUG: compile_gene_unknown: gene.type = ", gene.type
    echo "DEBUG: compile_gene_unknown: gene.children.len = ", gene.children.len
    if gene.children.len > 0:
      echo "DEBUG: compile_gene_unknown: first child = ", gene.children[0]
      if gene.children[0].kind == VkComplexSymbol:
        echo "DEBUG: compile_gene_unknown: first child csymbol = ", gene.children[0].ref.csymbol
  if gene.children.len >= 1:
    let first_child = gene.children[0]
    if first_child.kind == VkSymbol and first_child.str == "./":
      # Syntax: (target ./ property [default])
      if gene.children.len < 2 or gene.children.len > 3:
        not_allowed("(target ./ property [default]) expects 2 or 3 arguments")
      
      # Compile the target
      self.compile(gene.type)
      
      # Compile the property
      self.compile(gene.children[1])
      
      # If there's a default value, compile it
      if gene.children.len == 3:
        self.compile(gene.children[2])
        self.output.instructions.add(Instruction(kind: IkGetMemberDefault))
      else:
        self.output.instructions.add(Instruction(kind: IkGetMemberOrNil))
      return
    elif first_child.kind == VkComplexSymbol and first_child.ref.csymbol.len >= 2 and first_child.ref.csymbol[0] == ".":
      # Syntax: (target ./property) where ./property is a complex symbol
      if DEBUG:
        echo "DEBUG: Handling selector with complex symbol"
      # Compile the target
      self.compile(gene.type)
      
      # The property is the second part of the complex symbol
      let prop_name = first_child.ref.csymbol[1]
      # Check if property is numeric
      try:
        let idx = prop_name.parse_int()
        if DEBUG:
          echo "DEBUG: Property is numeric: ", idx
        self.output.instructions.add(Instruction(kind: IkPushValue, arg0: idx.to_value()))
      except ValueError:
        if DEBUG:
          echo "DEBUG: Property is symbolic: ", prop_name
        self.output.instructions.add(Instruction(kind: IkPushValue, arg0: prop_name.to_symbol_value()))
      
      # Check for default value (second child of gene)
      if gene.children.len == 2:
        self.compile(gene.children[1])
        self.output.instructions.add(Instruction(kind: IkGetMemberDefault))
      else:
        self.output.instructions.add(Instruction(kind: IkGetMemberOrNil))
      return
  
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
  self.output.instructions.add(Instruction(kind: IkGeneStartDefault, arg0: fn_label.to_value()))

  # self.output.instructions.add(Instruction(kind: IkGeneStartMacro))
  self.quote_level.inc()
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.to_value()))
  self.quote_level.dec()

  # self.output.instructions.add(Instruction(kind: IkGeneStartFn, label: fn_label))
  self.output.instructions.add(Instruction(kind: IkNoop, label: fn_label))
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkGeneEnd, arg0: start_pos, label: end_label))

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
    self.output.instructions.add(Instruction(kind: IkResolveMethod, arg0: gene.type.str[1..^1]))
  else:
    self.compile(gene.type)
    let first = gene.children[0]
    gene.children.delete(0)
    self.output.instructions.add(Instruction(kind: IkResolveMethod, arg0: first.str[1..^1]))

  let fn_label = new_label()
  let end_label = new_label()
  self.output.instructions.add(Instruction(kind: IkGeneStartDefault, arg0: fn_label.to_value()))

  self.quote_level.inc()
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.to_value()))
  self.quote_level.dec()

  self.output.instructions.add(Instruction(kind: IkNoop, label: fn_label))
  for k, v in gene.props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in gene.children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))

  self.output.instructions.add(Instruction(kind: IkGeneEnd, label: end_label))

proc compile_gene(self: Compiler, input: Value) =
  let gene = input.gene
  
  # Special case: handle selector operator ./
  if not gene.type.is_nil():
    if DEBUG:
      echo "DEBUG: compile_gene: gene.type.kind = ", gene.type.kind
      if gene.type.kind == VkSymbol:
        echo "DEBUG: compile_gene: gene.type.str = '", gene.type.str, "'"
      elif gene.type.kind == VkComplexSymbol:
        echo "DEBUG: compile_gene: gene.type.csymbol = ", gene.type.ref.csymbol
    if gene.type.kind == VkSymbol and gene.type.str == "./":
      self.compile_selector(gene)
      return
    elif gene.type.kind == VkComplexSymbol and gene.type.ref.csymbol.len >= 2 and gene.type.ref.csymbol[0] == "." and gene.type.ref.csymbol[1] == "":
      # "./" is parsed as complex symbol @[".", ""]
      self.compile_selector(gene)
      return
  
  # Special case: handle range expressions like (0 .. 2)
  if gene.children.len == 2 and gene.children[0].kind == VkSymbol and gene.children[0].str == "..":
    # This is a range expression: (start .. end)
    self.compile(gene.type)  # start value
    self.compile(gene.children[1])  # end value
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: NIL))  # default step
    self.output.instructions.add(Instruction(kind: IkCreateRange))
    return
  
  # Special case: handle genes with numeric types and no children like (-1)
  if gene.children.len == 0 and gene.type.kind in {VkInt, VkFloat}:
    self.compile_literal(gene.type)
    return
  
  if self.quote_level > 0 or gene.type == "_".to_symbol_value() or gene.type.kind == VkQuote:
    self.compile_gene_default(gene)
    return

  let `type` = gene.type
  
  # Check for infix notation: (value operator args...)
  # This handles cases like (6 / 2) or (i + 1)
  if gene.children.len >= 1:
    let first_child = gene.children[0]
    if (first_child.kind == VkSymbol and first_child.str in ["+", "-", "*", "/", "%", "**", "./"]) or
       (first_child.kind == VkComplexSymbol and first_child.ref.csymbol.len >= 2 and first_child.ref.csymbol[0] == "." and first_child.ref.csymbol[1] == ""):
      # Don't convert if the type is already an operator or special form
      if `type`.kind != VkSymbol or `type`.str notin ["var", "if", "fn", "fnx", "fnxx", "macro", "do", "loop", "while", "for", "ns", "class", "try", "throw", "$", "."]:
        # Convert infix to prefix notation and compile
        # (6 / 2) becomes (/ 6 2)
        # (i + 1) becomes (+ i 1)
        let prefix_gene = create(Gene)
        prefix_gene.type = first_child  # operator becomes the type
        prefix_gene.children = @[`type`] & gene.children[1..^1]  # value and rest of args
        self.compile_gene(prefix_gene.to_gene_value())
        return
  
  # Check if type is an arithmetic operator
  if `type`.kind == VkSymbol:
    case `type`.str:
      of "+":
        if gene.children.len == 0:
          # (+) with no args returns 0
          self.output.instructions.add(Instruction(kind: IkPushValue, arg0: 0.to_value()))
          return
        elif gene.children.len == 1:
          # Unary + is identity
          self.compile(gene.children[0])
          return
        else:
          # Multi-arg addition
          self.compile(gene.children[0])
          for i in 1..<gene.children.len:
            self.compile(gene.children[i])
            self.output.instructions.add(Instruction(kind: IkAdd))
          return
      of "-":
        if gene.children.len == 0:
          not_allowed("- requires at least one argument")
        elif gene.children.len == 1:
          # Unary minus - use IkNeg instruction
          self.compile(gene.children[0])
          self.output.instructions.add(Instruction(kind: IkNeg))
          return
        else:
          # Multi-arg subtraction
          self.compile(gene.children[0])
          for i in 1..<gene.children.len:
            self.compile(gene.children[i])
            self.output.instructions.add(Instruction(kind: IkSub))
          return
      of "*":
        if gene.children.len == 0:
          # (*) with no args returns 1
          self.output.instructions.add(Instruction(kind: IkPushValue, arg0: 1.to_value()))
          return
        elif gene.children.len == 1:
          # Unary * is identity
          self.compile(gene.children[0])
          return
        else:
          # Multi-arg multiplication
          self.compile(gene.children[0])
          for i in 1..<gene.children.len:
            self.compile(gene.children[i])
            self.output.instructions.add(Instruction(kind: IkMul))
          return
      of "/":
        if gene.children.len == 0:
          not_allowed("/ requires at least one argument")
        elif gene.children.len == 1:
          # Unary / is reciprocal: 1/x
          self.output.instructions.add(Instruction(kind: IkPushValue, arg0: 1.to_value()))
          self.compile(gene.children[0])
          self.output.instructions.add(Instruction(kind: IkDiv))
          return
        else:
          # Multi-arg division
          self.compile(gene.children[0])
          for i in 1..<gene.children.len:
            self.compile(gene.children[i])
            self.output.instructions.add(Instruction(kind: IkDiv))
          return
      else:
        discard  # Not an arithmetic operator, continue with normal processing
  
  if gene.children.len > 0:
    let first = gene.children[0]
    if first.kind == VkSymbol:
      case first.str:
        of "=", "+=", "-=":
          self.compile_assignment(gene)
          return
        of "<":
          self.compile(`type`)
          if gene.children[1].is_literal():
            self.output.instructions.add(Instruction(kind: IkLtValue, arg0: gene.children[1]))
          else:
            self.compile(gene.children[1])
            self.output.instructions.add(Instruction(kind: IkLt))
          return
        of "<=":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkLe))
          return
        of ">":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkGt))
          return
        of ">=":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkGe))
          return
        of "==":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkEq))
          return
        of "!=":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkNe))
          return
        of "&&":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkAnd))
          return
        of "||":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkOr))
          return
        of "not":
          # not is a unary operator, so only compile the first argument
          self.compile(gene.children[0])
          self.output.instructions.add(Instruction(kind: IkNot))
          return
        of "...":
          # Spread operator - compile the argument and emit IkSpread
          if gene.children.len != 1:
            not_allowed("... expects exactly 1 argument")
          self.compile(gene.children[0])
          self.output.instructions.add(Instruction(kind: IkSpread))
          return
        of "..":
          self.compile_range_operator(gene)
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
      of "var":
        self.compile_var(gene)
        return
      of "loop":
        self.compile_loop(gene)
        return
      of "while":
        self.compile_while(gene)
        return
      of "repeat":
        self.compile_repeat(gene)
        return
      of "for":
        self.compile_for(gene)
        return
      of "enum":
        self.compile_enum(gene)
        return
      of "..":
        self.compile_range_operator(gene)
        return
      of "break":
        self.compile_break(gene)
        return
      of "continue":
        self.compile_continue(gene)
        return
      of "fn", "fnx", "fnxx":
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
      of "try":
        self.compile_try(gene)
        return
      of "throw":
        self.compile_throw(gene)
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
      of "super":
        self.compile_super(gene)
        return
      of "match":
        self.compile_match(gene)
        return
      of "range":
        self.compile_range(gene)
        return
      of "...":
        # Spread operator - compile the argument and emit IkSpread
        if gene.children.len != 1:
          not_allowed("... expects exactly 1 argument")
        self.compile(gene.children[0])
        self.output.instructions.add(Instruction(kind: IkSpread))
        return
      of "async":
        self.compile_async(gene)
        return
      of "await":
        self.compile_await(gene)
        return
      of "void":
        # Compile all arguments but return nil
        for child in gene.children:
          self.compile(child)
          self.output.instructions.add(Instruction(kind: IkPop))
        self.output.instructions.add(Instruction(kind: IkPushNil))
        return
      of ".fn":
        # Method definition inside class body
        self.compile_method_definition(gene)
        return
      of ".ctor":
        # Constructor definition inside class body
        self.compile_constructor_definition(gene)
        return
      of "eval":
        # Evaluate expressions
        if gene.children.len == 0:
          self.output.instructions.add(Instruction(kind: IkPushNil))
        else:
          # Compile each argument and evaluate
          for i, child in gene.children:
            self.compile(child)
            # Add eval instruction to evaluate the value
            self.output.instructions.add(Instruction(kind: IkEval))
            if i < gene.children.len - 1:
              self.output.instructions.add(Instruction(kind: IkPop))
        return
      of "import":
        self.compile_import(gene)
        return
      else:
        let s = `type`.str
        if s == "@":
          # Handle @ selector operator
          self.compile_at_selector(gene)
          return
        elif s.starts_with("."):
          # Check if this is a method definition (e.g., .fn, .ctor) or a method call
          if s == ".fn" or s == ".ctor":
            self.compile_method_definition(gene)
            return
          else:
            self.compile_method_call(gene)
            return
        elif s.starts_with("$"):
          # Handle $ prefixed operations
          case s:
            of "$with":
              self.compile_with(gene)
              return
            of "$tap":
              self.compile_tap(gene)
              return
            of "$parse":
              self.compile_parse(gene)
              return
            of "$caller_eval":
              self.compile_caller_eval(gene)
              return
            of "$set":
              self.compile_set(gene)
              return
            of "$render":
              self.compile_render(gene)
              return
            of "$emit":
              self.compile_emit(gene)
              return

  self.compile_gene_unknown(gene)

proc compile*(self: Compiler, input: Value) =
  when DEBUG:
    echo "DEBUG compile: input.kind = ", input.kind
    if input.kind == VkGene:
      echo "  gene.type = ", input.gene.type
      if input.gene.type.kind == VkSymbol:
        echo "  gene.type.str = ", input.gene.type.str
  
  case input.kind:
    of VkInt, VkBool, VkNil, VkFloat:
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
    of VkUnquote:
      # Unquote values should be compiled as literals
      # They will be processed during template rendering
      self.compile_literal(input)
    of VkFunction:
      # Functions should be compiled as literals
      self.compile_literal(input)
    else:
      todo($input.kind)

proc update_jumps(self: CompilationUnit) =
  for i in 0..<self.instructions.len:
    let inst = self.instructions[i]
    case inst.kind
      of IkJump, IkJumpIfFalse, IkContinue, IkBreak, IkGeneStartDefault:
        # Special case: -1 means no loop (for break/continue outside loops)
        if inst.kind in {IkBreak, IkContinue} and inst.arg0.int64 == -1:
          # Keep -1 as is for runtime checking
          discard
        else:
          # Labels are stored as int16 values converted to Value
          # Extract the int value and cast to Label (int16)
          # Extract the label from the NaN-boxed value
          # The label was stored as int16, so we need to extract just the low 16 bits
          when not defined(release):
            if inst.arg0.kind != VkInt:
              echo "ERROR: inst ", i, " (", inst.kind, ") arg0 is not an int: ", inst.arg0, " kind: ", inst.arg0.kind
          let label = (inst.arg0.int64.int and 0xFFFF).int16.Label
          let new_pc = self.find_label(label)
          self.instructions[i].arg0 = new_pc.to_value()
      of IkTryStart:
        # IkTryStart has arg0 for catch PC and optional arg1 for finally PC
        when not defined(release):
          if inst.arg0.kind != VkInt:
            echo "ERROR: inst ", i, " (", inst.kind, ") arg0 is not an int: ", inst.arg0, " kind: ", inst.arg0.kind
        let catch_label = (inst.arg0.int64.int and 0xFFFF).int16.Label
        let catch_pc = self.find_label(catch_label)
        self.instructions[i].arg0 = catch_pc.to_value()
        
        # Handle finally PC if present
        if inst.arg1 != 0:
          let finally_pc = self.find_label(inst.arg1.Label)
          self.instructions[i].arg1 = finally_pc.int32
      of IkJumpIfMatchSuccess:
        self.instructions[i].arg1 = self.find_label(inst.arg1.Label).int32
      else:
        discard

# Remove IkNoop instructions that don't serve as jump targets
proc optimize_noops(self: CompilationUnit) =
  # After jumps are resolved, we can remove IkNoop instructions that don't have labels
  # BUT we must keep IkNoop instructions that store data (like scope trackers)
  var new_instructions: seq[Instruction] = @[]
  
  for i, inst in self.instructions:
    if inst.kind != IkNoop:
      # Keep all non-Noop instructions
      new_instructions.add(inst)
    elif inst.label != 0:
      # Keep IkNoop if it has a label (used as jump target)
      new_instructions.add(inst)
    elif inst.arg0.kind != VkNil:
      # Keep IkNoop if it has data in arg0 (e.g., scope tracker)
      new_instructions.add(inst)
    # Skip IkNoop without labels or data
  
  self.instructions = new_instructions

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
  self.output.optimize_noops()
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
      arg0: i.to_value(),
      arg1: label,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, arg0: m.name_key.to_value()))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(f.body)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  self.output.optimize_noops()
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
      arg0: i.to_value(),
      arg1: label,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, arg0: m.name_key.to_value()))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(m.body)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  self.output.optimize_noops()
  m.body_compiled = self.output
  m.body_compiled.kind = CkMacro
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
      arg0: i.to_value(),
      arg1: label,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, arg0: m.name_key.to_value()))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(b.body)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  self.output.optimize_noops()
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
      arg0: i.to_value(),
      arg1: label,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.output.instructions.add(Instruction(kind: IkVar, arg0: m.name_key.to_value()))
      self.output.instructions.add(Instruction(kind: IkPop))
    else:
      self.output.instructions.add(Instruction(kind: IkThrow))
    self.output.instructions.add(Instruction(kind: IkNoop, label: label))

  self.compile(f.body)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  self.output.optimize_noops()
  f.body_compiled = self.output
  f.body_compiled.kind = CkCompileFn
  f.body_compiled.matcher = f.matcher

proc compile_with(self: Compiler, gene: ptr Gene) =
  # ($with value body...)
  if gene.children.len < 1:
    not_allowed("$with expects at least 1 argument")
  
  # Compile the value that will become the new self
  self.compile(gene.children[0])
  
  # Duplicate it and save current self
  self.output.instructions.add(Instruction(kind: IkDup))
  self.output.instructions.add(Instruction(kind: IkSelf))
  self.output.instructions.add(Instruction(kind: IkSwap))
  
  # Set as new self
  self.output.instructions.add(Instruction(kind: IkSetSelf))
  
  # Compile body - return last value
  if gene.children.len > 1:
    for i in 1..<gene.children.len:
      self.compile(gene.children[i])
      if i < gene.children.len - 1:
        self.output.instructions.add(Instruction(kind: IkPop))
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  
  # Restore original self (which is on stack under the result)
  self.output.instructions.add(Instruction(kind: IkSwap))
  self.output.instructions.add(Instruction(kind: IkSetSelf))

proc compile_tap(self: Compiler, gene: ptr Gene) =
  # ($tap value body...) or ($tap value :name body...)
  if gene.children.len < 1:
    not_allowed("$tap expects at least 1 argument")
  
  # Compile the value
  self.compile(gene.children[0])
  
  # Duplicate it (one to return, one to use)
  self.output.instructions.add(Instruction(kind: IkDup))
  
  # Check if there's a binding name
  var start_idx = 1
  var has_binding = false
  var binding_name: string
  
  if gene.children.len > 1 and gene.children[1].kind == VkSymbol and gene.children[1].str.starts_with(":"):
    has_binding = true
    binding_name = gene.children[1].str[1..^1]
    start_idx = 2
  
  # Save current self
  self.output.instructions.add(Instruction(kind: IkSelf))
  
  # Set as new self
  self.output.instructions.add(Instruction(kind: IkRotate))  # Rotate: original_self, dup_value, value -> value, original_self, dup_value
  self.output.instructions.add(Instruction(kind: IkSetSelf))
  
  # If has binding, create a new scope and bind the value
  if has_binding:
    self.start_scope()
    let var_index = self.scope_tracker.next_index
    self.scope_tracker.mappings[binding_name.to_key()] = var_index
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    
    # Duplicate the value again for binding
    self.output.instructions.add(Instruction(kind: IkSelf))
    self.output.instructions.add(Instruction(kind: IkVar, arg0: var_index.to_value()))
  
  # Compile body
  if gene.children.len > start_idx:
    for i in start_idx..<gene.children.len:
      self.compile(gene.children[i])
      # Pop all but last result
      self.output.instructions.add(Instruction(kind: IkPop))
  
  # End scope if we created one
  if has_binding:
    self.end_scope()
  
  # Restore original self
  self.output.instructions.add(Instruction(kind: IkSwap))  # dup_value, original_self -> original_self, dup_value
  self.output.instructions.add(Instruction(kind: IkSetSelf))
  # The dup_value remains on stack as the return value

proc compile_parse(self: Compiler, gene: ptr Gene) =
  # ($parse string)
  if gene.children.len != 1:
    not_allowed("$parse expects exactly 1 argument")
  
  # Compile the string argument
  self.compile(gene.children[0])
  
  # Parse it
  self.output.instructions.add(Instruction(kind: IkParse))

proc compile_render(self: Compiler, gene: ptr Gene) =
  # ($render template)
  if gene.children.len != 1:
    not_allowed("$render expects exactly 1 argument")
  
  # Compile the template argument
  self.compile(gene.children[0])
  
  # Render it
  self.output.instructions.add(Instruction(kind: IkRender))

proc compile_emit(self: Compiler, gene: ptr Gene) =
  # ($emit value) - used within templates to emit values
  if gene.children.len < 1:
    not_allowed("$emit expects at least 1 argument")
  
  # For now, $emit just evaluates to its argument
  # The actual emission logic is handled by the template renderer
  if gene.children.len == 1:
    self.compile(gene.children[0])
  else:
    # Multiple arguments - create an array
    let arr_gene = new_gene("Array".to_symbol_value())
    for child in gene.children:
      arr_gene.children.add(child)
    self.compile(arr_gene.to_gene_value())

proc compile_caller_eval(self: Compiler, gene: ptr Gene) =
  # ($caller_eval expr)
  if gene.children.len != 1:
    not_allowed("$caller_eval expects exactly 1 argument")
  
  # Compile the expression argument (will be evaluated in macro context first)
  self.compile(gene.children[0])
  
  # Then evaluate the result in caller's context
  self.output.instructions.add(Instruction(kind: IkCallerEval))

proc compile_async(self: Compiler, gene: ptr Gene) =
  # (async expr)
  if gene.children.len != 1:
    not_allowed("async expects exactly 1 argument")
  
  # We need to wrap the expression evaluation in exception handling
  # Generate: try expr catch e -> future.fail(e)
  
  # Push a marker for the async block
  self.output.instructions.add(Instruction(kind: IkAsyncStart))
  
  # Compile the expression
  self.compile(gene.children[0])
  
  # End async block - this will handle exceptions and wrap in future
  self.output.instructions.add(Instruction(kind: IkAsyncEnd))

proc compile_await(self: Compiler, gene: ptr Gene) =
  # (await future) or (await future1 future2 ...)
  if gene.children.len == 0:
    not_allowed("await expects at least 1 argument")
  
  if gene.children.len == 1:
    # Single future
    self.compile(gene.children[0])
    self.output.instructions.add(Instruction(kind: IkAwait))
  else:
    # Multiple futures - await each and collect results
    self.output.instructions.add(Instruction(kind: IkArrayStart))
    for child in gene.children:
      self.compile(child)
      self.output.instructions.add(Instruction(kind: IkAwait))
      self.output.instructions.add(Instruction(kind: IkArrayAddChild))
    self.output.instructions.add(Instruction(kind: IkArrayEnd))

proc compile_selector(self: Compiler, gene: ptr Gene) =
  # (./ target property [default])
  # ({^a "A"} ./ "a") -> "A"
  # ({} ./ "a" 1) -> 1 (default value)
  if gene.children.len < 2 or gene.children.len > 3:
    not_allowed("./ expects 2 or 3 arguments")
  
  # Compile the target
  self.compile(gene.children[0])
  
  # Compile the property/index
  self.compile(gene.children[1])
  
  # If there's a default value, compile it
  if gene.children.len == 3:
    self.compile(gene.children[2])
    self.output.instructions.add(Instruction(kind: IkGetMemberDefault))
  else:
    self.output.instructions.add(Instruction(kind: IkGetMemberOrNil))

proc compile_at_selector(self: Compiler, gene: ptr Gene) =
  # (@ "property") creates a selector
  # For now, we'll implement a simplified version
  # The full implementation would create a selector object
  
  # Since @ is used in contexts like ((@ "test") {^test 1}),
  # and this gets compiled as a function call where (@ "test") is the function
  # and {^test 1} is the argument, we need to handle this specially
  
  # For now, just push the property name as a special selector value
  # The VM will need to handle this when it sees a selector being called
  if gene.children.len != 1:
    not_allowed("@ expects exactly 1 argument for basic property access")
  
  # Create a special selector value - for now use a gene with type @
  let selector = new_gene("@".to_symbol_value())
  selector.children.add(gene.children[0])
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: selector.to_gene_value()))

proc compile_set(self: Compiler, gene: ptr Gene) =
  # ($set target @property value)
  # ($set a @test 1)
  if gene.children.len != 3:
    not_allowed("$set expects exactly 3 arguments")
  
  # Compile the target
  self.compile(gene.children[0])
  
  # The second argument should be a selector like @test or (@ "test")
  var selector = gene.children[1]
  
  # Handle @shorthand syntax - @test becomes (@ "test")
  if selector.kind == VkSymbol and selector.str.startsWith("@") and selector.str.len > 1:
    let prop_name = selector.str[1..^1]
    selector = new_gene("@".to_symbol_value()).to_gene_value()
    
    # Check if it contains / for complex selectors like @test/0
    if "/" in prop_name:
      # Handle @test/0 or @0/test
      let parts = prop_name.split("/")
      for part in parts:
        # Try to parse as int for numeric indices
        try:
          let index = parseInt(part)
          selector.gene.children.add(index.to_value())
        except ValueError:
          selector.gene.children.add(part.to_value())
    else:
      # Simple @test case
      # Try to parse as int for @0 syntax
      try:
        let index = parseInt(prop_name)
        selector.gene.children.add(index.to_value())
      except ValueError:
        selector.gene.children.add(prop_name.to_value())
  elif selector.kind != VkGene or selector.gene.type != "@".to_symbol_value():
    not_allowed("$set expects a selector (@property) as second argument")
  
  # Extract the property name
  if selector.gene.children.len != 1:
    not_allowed("$set selector must have exactly one property")
  
  let prop = selector.gene.children[0]
  
  # Compile the value
  self.compile(gene.children[2])
  
  # Check if property is an integer (for array/gene child access)
  if prop.kind == VkInt:
    # Use SetChild for integer indices
    self.output.instructions.add(Instruction(kind: IkSetChild, arg0: prop))
  else:
    # Use SetMember for string/symbol properties
    let prop_key = case prop.kind:
      of VkString: prop.str.to_key()
      of VkSymbol: prop.str.to_key()
      else: 
        not_allowed("Invalid property type for $set")
        "".to_key()  # Never reached, but satisfies type checker
    self.output.instructions.add(Instruction(kind: IkSetMember, arg0: prop_key.to_value()))

proc compile_import(self: Compiler, gene: ptr Gene) =
  # (import a b from "module")
  # (import from "module" a b)
  # (import a:alias b from "module")
  # (import n/f from "module")
  # (import n/[one two] from "module")
  
  # echo "DEBUG: compile_import called for ", gene
  # echo "DEBUG: gene.children = ", gene.children
  # echo "DEBUG: gene.props = ", gene.props
  
  # Compile a gene value for the import, but with "import" as a symbol type
  self.output.instructions.add(Instruction(kind: IkGeneStart))
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: "import".to_symbol_value()))
  self.output.instructions.add(Instruction(kind: IkGeneSetType))
  
  # Compile the props
  for k, v in gene.props:
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: v))
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  
  # Compile the children - they should be treated as quoted values
  for child in gene.children:
    # Import arguments are data, not code to execute
    # So compile them as literal values
    case child.kind:
    of VkSymbol, VkString:
      self.output.instructions.add(Instruction(kind: IkPushValue, arg0: child))
    of VkComplexSymbol:
      # Handle n/f syntax
      self.output.instructions.add(Instruction(kind: IkPushValue, arg0: child))
    of VkArray:
      # Handle [one two] part of n/[one two]
      self.output.instructions.add(Instruction(kind: IkPushValue, arg0: child))
    of VkGene:
      # Handle complex forms like a:alias or n/[a b]
      self.compile_gene_default(child.gene)
    else:
      self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  
  self.output.instructions.add(Instruction(kind: IkGeneEnd))
  self.output.instructions.add(Instruction(kind: IkImport))

proc compile_init*(input: Value): CompilationUnit =
  let self = Compiler(output: new_compilation_unit())
  self.output.skip_return = true
  self.output.instructions.add(Instruction(kind: IkStart))
  self.start_scope()

  self.compile(input)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  self.output.optimize_noops()
  result = apply_fusion(self.output)

proc replace_chunk*(self: var CompilationUnit, start_pos: int, end_pos: int, replacement: sink seq[Instruction]) =
  self.instructions[start_pos..end_pos] = replacement

# Compile methods for Function, Macro, Block, and CompileFn are defined above
