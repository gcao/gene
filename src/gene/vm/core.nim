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
  let self = args.gene.type.ref.bound_method.self
  # define a fn like method on a class
  let fn = to_function(args)

  let r = new_ref(VkFunction)
  r.fn = fn
  let m = Method(
     name: fn.name,
    callable: r.to_ref_value(),
  )
  case self.kind:
  of VkClass:
    let class = self.ref.class
    m.class = class
    fn.ns = class.ns
    class.methods[m.name.to_key()] = m
  # of VkMixin:
  #   fn.ns = self.mixin.ns
  #   self.mixin.methods[m.name] = m
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

VMCreatedCallbacks.add proc() =
  App.app.gene_ns.ns["debug".to_key()] = debug
  App.app.gene_ns.ns["println".to_key()] = println
  App.app.gene_ns.ns["trace_start".to_key()] = trace_start
  App.app.gene_ns.ns["trace_end".to_key()] = trace_end
  App.app.gene_ns.ns["print_stack".to_key()] = print_stack
  App.app.gene_ns.ns["print_instructions".to_key()] = print_instructions

  let class = new_class("Class")
  class.def_native_macro_method "ctor", class_ctor
  class.def_native_macro_method "fn", class_fn
  let r = new_ref(VkClass)
  r.class = class
  App.app.class_class = r.to_ref_value()

  let vm_ns = new_namespace("vm")
  App.app.gene_ns.ns["vm".to_key()] = vm_ns.to_value()
  vm_ns["compile".to_key()] = NativeFn(vm_compile)
  vm_ns["PUSH".to_key()] = vm_push
  vm_ns["ADD" .to_key()] = vm_add
