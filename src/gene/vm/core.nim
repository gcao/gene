import strutils

# Show the code
# JIT the code (create a temporary block, reuse the frame)
# Execute the code
# Show the result
proc debug(self: VirtualMachine, args: Value): Value =
  todo()

proc println(self: VirtualMachine, args: Value): Value =
  var s = ""
  for i, k in args.gene.children:
    s &= $k
    if i < args.gene.children.len - 1:
      s &= " "
  echo s

proc trace_start(self: VirtualMachine, args: Value): Value =
  self.trace = true
  self.frame.push(NIL)

proc trace_end(self: VirtualMachine, args: Value): Value =
  self.trace = false
  self.frame.push(NIL)

proc print_stack(self: VirtualMachine, args: Value): Value =
  var s = "Stack: "
  for i, reg in self.frame.stack:
    if i > 0:
      s &= ", "
    if i == self.frame.stack_index.int:
      s &= "=> "
    s &= $self.frame.stack[i]
  echo s
  self.frame.push(NIL)

proc print_instructions(self: VirtualMachine, args: Value): Value =
  echo self.cu
  self.frame.push(NIL)

proc to_ctor(node: Value): Function =
  let name = "ctor"

  let matcher = new_arg_matcher()
  matcher.parse(node.gene.children[0])
  matcher.check_hint()

  var body: seq[Value] = @[]
  for i in 1..<node.gene.children.len:
    body.add node.gene.children[i]

  # body = wrap_with_try(body)
  result = new_fn(name, matcher, body)

proc class_ctor(self: VirtualMachine, args: Value): Value =
  let fn = to_ctor(args)
  fn.ns = self.frame.ns
  let r = new_ref(VkFunction)
  r.fn = fn
  self.frame.self.ref.class.constructor = r.to_ref_value()

proc class_fn(self: VirtualMachine, args: Value): Value =
  let x = args.gene.type.ref.bound_method.self
  # define a fn like method on a class
  let fn = to_function(args)

  let r = new_ref(VkFunction)
  r.fn = fn
  let m = Method(
     name: fn.name,
    callable: r.to_ref_value(),
  )
  case x.kind:
  of VkClass:
    let class = x.ref.class
    m.class = class
    fn.ns = class.ns
    class.methods[m.name.to_key()] = m
  # of VkMixin:
  #   fn.ns = x.mixin.ns
  #   x.mixin.methods[m.name] = m
  else:
    not_allowed()

proc vm_compile(self: VirtualMachine, args: Value): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    let compiler = Compiler(output: new_compilation_unit())
    let scope_tracker = self.frame.caller_frame.scope.tracker
    # compiler.output.scope_tracker = scope_tracker
    compiler.scope_trackers.add(scope_tracker)
    compiler.compile(args.gene.children[0])
    let instrs = new_ref(VkArray)
    for instr in compiler.output.instructions:
      instrs.arr.add instr.to_value()
    result = instrs.to_ref_value()

proc vm_push(self: VirtualMachine, args: Value): Value =
  new_instr(IkPushValue, args.gene.children[0])

proc vm_add(self: VirtualMachine, args: Value): Value =
  new_instr(IkAdd)

proc current_ns(self: VirtualMachine, args: Value): Value =
  # Return the current namespace
  let r = new_ref(VkNamespace)
  r.ns = self.frame.ns
  result = r.to_ref_value()

# vm_not function removed - now handled by IkNot instruction at compile time

# vm_spread function removed - ... is now handled as compile-time keyword

proc vm_parse(self: VirtualMachine, args: Value): Value =
  # Parse Gene code from string
  if args.gene.children.len != 1:
    not_allowed("$parse expects exactly 1 argument")
  let arg = args.gene.children[0]
  case arg.kind:
    of VkString:
      let code = arg.str
      # Use the actual Gene parser to parse the code
      try:
        let parsed = read_all(code)
        if parsed.len > 0:
          return parsed[0]
        else:
          return NIL
      except:
        # Fallback to simple parsing for basic literals
        case code:
          of "true": 
            return TRUE
          of "false": 
            return FALSE
          of "nil": 
            return NIL
          else:
            # Try to parse as number
            try:
              let int_val = parseInt(code)
              return int_val.to_value()
            except ValueError:
              try:
                let float_val = parseFloat(code)
                return float_val.to_value()
              except ValueError:
                # Return as symbol for now
                return code.to_symbol_value()
    else:
      not_allowed("$parse expects a string argument")

proc vm_with(self: VirtualMachine, args: Value): Value =
  # $with sets self to the first argument and executes the body, returns the original value
  if args.gene.children.len < 2:
    not_allowed("$with expects at least 2 arguments")
  
  let original_value = args.gene.children[0]
  let old_self = self.frame.self
  self.frame.self = original_value
  
  # Execute the body (all arguments after the first)
  for i in 1..<args.gene.children.len:
    discard # Body execution would happen during compilation/evaluation
  
  self.frame.self = old_self
  return original_value

proc vm_tap(self: VirtualMachine, args: Value): Value =
  # $tap executes the body with self set to the first argument, returns the original value
  if args.gene.children.len < 2:
    not_allowed("$tap expects at least 2 arguments")
  
  let original_value = args.gene.children[0]
  let old_self = self.frame.self
  
  # If second argument is a symbol, bind it to the value
  var binding_name: string = ""
  var body_start_index = 1
  if args.gene.children.len > 2 and args.gene.children[1].kind == VkSymbol:
    binding_name = args.gene.children[1].str
    body_start_index = 2
  else:
    self.frame.self = original_value
  
  # Execute the body
  for i in body_start_index..<args.gene.children.len:
    discard # Body execution would happen during compilation/evaluation
  
  self.frame.self = old_self
  return original_value

proc vm_eval(self: VirtualMachine, args: Value): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    # eval evaluates symbols and expressions, returns the last value
    if args.gene.children.len == 0:
      return NIL
    
    var result = NIL
    for arg in args.gene.children:
      case arg.kind:
        of VkSymbol:
          # Look up the symbol - first check local scope, then namespaces
          let key = arg.str.to_key()
          
          # Check if it's a local variable first
          if self.frame.scope != nil and self.frame.scope.tracker != nil:
            let found = self.frame.scope.tracker.locate(key)
            if found.local_index >= 0:
              # Variable found in scope
              var scope = self.frame.scope
              var parent_index = found.parent_index
              while parent_index > 0:
                parent_index.dec()
                scope = scope.parent
              result = scope.members[found.local_index]
            else:
              # Not a local variable, look in namespaces
              var value = self.frame.ns[key]
              if value.int64 == NOT_FOUND.int64:
                # Try global namespace
                value = App.app.global_ns.ns[key]
                if value.int64 == NOT_FOUND.int64:
                  # Try gene namespace
                  value = App.app.gene_ns.ns[key]
                  if value.int64 == NOT_FOUND.int64:
                    not_allowed("Unknown symbol: " & arg.str)
              result = value
          else:
            # No scope available, just look in namespaces
            var value = self.frame.ns[key]
            if value.int64 == NOT_FOUND.int64:
              # Try global namespace
              value = App.app.global_ns.ns[key]
              if value.int64 == NOT_FOUND.int64:
                # Try gene namespace
                value = App.app.gene_ns.ns[key]
                if value.int64 == NOT_FOUND.int64:
                  not_allowed("Unknown symbol: " & arg.str)
            result = value
        of VkGene:
          # For Gene expressions, compile and execute them
          let compiled = compile(@[arg])
          let vm = VirtualMachine()
          let ns = new_namespace("eval")
          vm.frame.update(new_frame(ns))
          vm.frame.ref_count.dec()
          vm.frame.self = NIL
          vm.cu = compiled
          result = vm.exec()
        else:
          # For other types, just return the value as-is
          result = arg
    
    return result

# TODO: Implement while loop properly - needs compiler-level support like loop/if

VmCreatedCallbacks.add proc() =
  # Initialize basic classes needed by get_class
  var r: ptr Reference
  
  # nil_class
  let nil_class = new_class("Nil")
  r = new_ref(VkClass)
  r.class = nil_class
  App.app.nil_class = r.to_ref_value()
  
  # bool_class
  let bool_class = new_class("Bool")
  r = new_ref(VkClass)
  r.class = bool_class
  App.app.bool_class = r.to_ref_value()
  
  # int_class
  let int_class = new_class("Int")
  r = new_ref(VkClass)
  r.class = int_class
  App.app.int_class = r.to_ref_value()
  
  # string_class
  let string_class = new_class("String")
  r = new_ref(VkClass)
  r.class = string_class
  App.app.string_class = r.to_ref_value()
  
  # symbol_class
  let symbol_class = new_class("Symbol")
  r = new_ref(VkClass)
  r.class = symbol_class
  App.app.symbol_class = r.to_ref_value()
  
  # complex_symbol_class
  let complex_symbol_class = new_class("ComplexSymbol")
  r = new_ref(VkClass)
  r.class = complex_symbol_class
  App.app.complex_symbol_class = r.to_ref_value()
  
  # array_class
  let array_class = new_class("Array")
  r = new_ref(VkClass)
  r.class = array_class
  App.app.array_class = r.to_ref_value()
  
  # map_class
  let map_class = new_class("Map")
  r = new_ref(VkClass)
  r.class = map_class
  App.app.map_class = r.to_ref_value()
  
  # set_class
  let set_class = new_class("Set")
  r = new_ref(VkClass)
  r.class = set_class
  App.app.set_class = r.to_ref_value()
  
  # gene_class
  let gene_class = new_class("Gene")
  r = new_ref(VkClass)
  r.class = gene_class
  App.app.gene_class = r.to_ref_value()
  
  # function_class
  let function_class = new_class("Function")
  r = new_ref(VkClass)
  r.class = function_class
  App.app.function_class = r.to_ref_value()
  
  # char_class
  let char_class = new_class("Char")
  r = new_ref(VkClass)
  r.class = char_class
  App.app.char_class = r.to_ref_value()
  
  # application_class
  let application_class = new_class("Application")
  r = new_ref(VkClass)
  r.class = application_class
  App.app.application_class = r.to_ref_value()
  
  # package_class
  let package_class = new_class("Package")
  r = new_ref(VkClass)
  r.class = package_class
  App.app.package_class = r.to_ref_value()
  
  # namespace_class
  let namespace_class = new_class("Namespace")
  r = new_ref(VkClass)
  r.class = namespace_class
  App.app.namespace_class = r.to_ref_value()

  App.app.gene_ns.ns["debug".to_key()] = debug
  App.app.gene_ns.ns["println".to_key()] = println
  App.app.gene_ns.ns["trace_start".to_key()] = trace_start
  App.app.gene_ns.ns["trace_end".to_key()] = trace_end
  App.app.gene_ns.ns["print_stack".to_key()] = print_stack
  App.app.gene_ns.ns["print_instructions".to_key()] = print_instructions
  App.app.gene_ns.ns["ns".to_key()] = current_ns
  # not and ... are now handled by compile-time instructions, no need to register
  App.app.gene_ns.ns["parse".to_key()] = vm_parse  # $parse translates to gene/parse
  App.app.gene_ns.ns["with".to_key()] = vm_with    # $with translates to gene/with
  App.app.gene_ns.ns["tap".to_key()] = vm_tap      # $tap translates to gene/tap
  App.app.gene_ns.ns["eval".to_key()] = vm_eval    # eval function
  
  # Also add to global namespace
  App.app.global_ns.ns["parse".to_key()] = vm_parse
  App.app.global_ns.ns["with".to_key()] = vm_with
  App.app.global_ns.ns["tap".to_key()] = vm_tap
  App.app.global_ns.ns["eval".to_key()] = vm_eval
  
  

  let class = new_class("Class")
  class.def_native_macro_method "ctor", class_ctor
  class.def_native_macro_method "fn", class_fn
  r = new_ref(VkClass)
  r.class = class
  App.app.class_class = r.to_ref_value()

  let vm_ns = new_namespace("vm")
  App.app.gene_ns.ns["vm".to_key()] = vm_ns.to_value()
  vm_ns["compile".to_key()] = NativeFn(vm_compile)
  vm_ns["PUSH".to_key()] = vm_push
  vm_ns["ADD" .to_key()] = vm_add
