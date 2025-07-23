import tables, strutils

import ./types
import "./compiler/if"

#################### Definitions #################
proc compile*(self: Compiler, input: Value)
proc compile_with(self: Compiler, gene: ptr Gene)
proc compile_tap(self: Compiler, gene: ptr Gene)
proc compile_parse(self: Compiler, gene: ptr Gene)

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
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: r.csymbol[0].to_symbol_value()))
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
      if symbol_str.endsWith("..."):
        # Handle variable spread like "a..." - strip the ... and add spread
        let base_symbol = symbol_str[0..^4].to_symbol_value()  # Remove "..."
        let key = cast[Key](base_symbol)
        let found = self.scope_tracker.locate(key)
        if found.local_index >= 0:
          if found.parent_index == 0:
            self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
          else:
            self.output.instructions.add(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
        else:
          self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: base_symbol))
        self.output.instructions.add(Instruction(kind: IkSpread))
        return
      let key = cast[Key](input)
      let found = self.scope_tracker.locate(key)
      if found.local_index >= 0:
        if found.parent_index == 0:
          self.output.instructions.add(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
        else:
          self.output.instructions.add(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
      else:
        self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: input))
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

proc compile_var(self: Compiler, gene: ptr Gene) =
  let name = gene.children[0]
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
        self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: `type`))
      
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
      self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: r.csymbol[0].to_symbol_value()))
      
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
  if self.loop_stack.len == 0:
    not_allowed("break used outside of a loop")
  
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  
  # Get the current loop's end label
  let current_loop = self.loop_stack[^1]
  self.output.instructions.add(Instruction(kind: IkBreak, arg0: current_loop.end_label.to_value()))

proc compile_continue(self: Compiler, gene: ptr Gene) =
  if self.loop_stack.len == 0:
    not_allowed("continue used outside of a loop")
  
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  
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
  let try_end_label = new_label()
  let catch_end_label = new_label()
  let finally_label = new_label()
  let end_label = new_label()
  
  # Mark start of try block
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
  self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.to_value()))
  
  # Handle catch blocks
  self.output.instructions.add(Instruction(kind: IkNoop, label: catch_end_label))
  while i < gene.children.len:
    let child = gene.children[i]
    if child.kind == VkSymbol and child.str == "catch":
      inc i
      if i < gene.children.len:
        # TODO: Handle catch patterns (exception types)
        self.output.instructions.add(Instruction(kind: IkCatchStart))
        
        # Skip pattern for now, just compile body
        inc i
        while i < gene.children.len:
          let body_child = gene.children[i]
          if body_child.kind == VkSymbol and (body_child.str == "catch" or body_child.str == "finally"):
            break
          self.compile(body_child)
          inc i
        
        self.output.instructions.add(Instruction(kind: IkCatchEnd))
        self.output.instructions.add(Instruction(kind: IkJump, arg0: end_label.to_value()))
    elif child.kind == VkSymbol and child.str == "finally":
      inc i
      # TODO: Implement finally block
      break
    else:
      inc i
  
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
  if gene.children.len > 0:
    let first = gene.children[0]
    if first.kind == VkSymbol:
      case first.str:
        of "=", "+=", "-=":
          self.compile_assignment(gene)
          return
        of "+":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkAdd))
          return
        of "-":
          self.compile(`type`)
          if gene.children[1].is_literal():
            self.output.instructions.add(Instruction(kind: IkSubValue, arg0: gene.children[1]))
          else:
            self.compile(gene.children[1])
            self.output.instructions.add(Instruction(kind: IkSub))
          return
        of "*":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkMul))
          return
        of "/":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.output.instructions.add(Instruction(kind: IkDiv))
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
      of "void":
        # Compile all arguments but return nil
        for child in gene.children:
          self.compile(child)
          self.output.instructions.add(Instruction(kind: IkPop))
        self.output.instructions.add(Instruction(kind: IkPushNil))
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
      else:
        let s = `type`.str
        if s.starts_with("."):
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

  self.compile_gene_unknown(gene)

proc compile*(self: Compiler, input: Value) =
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
    else:
      todo($input.kind)

proc update_jumps(self: CompilationUnit) =
  for i in 0..<self.instructions.len:
    let inst = self.instructions[i]
    case inst.kind
      of IkJump, IkJumpIfFalse, IkContinue, IkBreak, IkGeneStartDefault:
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
      of IkJumpIfMatchSuccess:
        self.instructions[i].arg1 = self.find_label(inst.arg1.Label).int32
      else:
        discard

# # Clean up scopes by removing unnecessary ScopeStart and ScopeEnd instructions
# proc cleanup_scopes(self: CompilationUnit) =
#   todo("cleanup_scopes")

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
  m.body_compiled = self.output
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
  self.output.instructions.add(Instruction(kind: IkRot))  # Rotate: original_self, dup_value, value -> value, original_self, dup_value
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

proc compile_init*(input: Value): CompilationUnit =
  let self = Compiler(output: new_compilation_unit())
  self.output.skip_return = true
  self.output.instructions.add(Instruction(kind: IkStart))
  self.start_scope()

  self.compile(input)

  self.end_scope()
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()
  result = self.output

proc replace_chunk*(self: var CompilationUnit, start_pos: int, end_pos: int, replacement: sink seq[Instruction]) =
  self.instructions[start_pos..end_pos] = replacement
