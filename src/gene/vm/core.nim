# Show the code
# JIT the code (create a temporary block, reuse the frame)
# Execute the code
# Show the result
proc debug(self: VirtualMachine, args: Value): Value =
  todo()

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

VMCreatedCallbacks.add proc() =
  App.app.gene_ns.ns["debug".to_key()] = debug
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
