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

proc vm_spread(self: VirtualMachine, args: Value): Value =
  # Spread operator - returns a special marker value that array construction recognizes
  if args.gene.children.len != 1:
    not_allowed("... expects exactly 1 argument")
  let arg = args.gene.children[0]
  case arg.kind:
    of VkArray:
      # Create a special explode marker
      let r = new_ref(VkExplode)
      r.explode_value = arg
      result = r.to_ref_value()
    else:
      not_allowed("... can only spread arrays")

proc vm_parse(self: VirtualMachine, args: Value): Value =
  # Parse Gene code from string
  if args.gene.children.len != 1:
    not_allowed("$parse expects exactly 1 argument")
  let arg = args.gene.children[0]
  case arg.kind:
    of VkString:
      # TODO: Use the actual Gene parser here
      # For now, implement basic parsing for common cases
      let code = arg.str
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

# TODO: Implement while loop properly - needs compiler-level support like loop/if

VMCreatedCallbacks.add proc() =
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
  # not is now handled by IkNot instruction at compile time, no need to register
  App.app.gene_ns.ns["...".to_key()] = vm_spread
  App.app.gene_ns.ns["parse".to_key()] = vm_parse  # $parse translates to gene/parse
  
  # Also add to global namespace
  App.app.global_ns.ns["...".to_key()] = vm_spread
  App.app.global_ns.ns["parse".to_key()] = vm_parse
  

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
