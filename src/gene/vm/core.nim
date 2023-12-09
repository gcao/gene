proc to_ctor(node: Value): Function =
  let name = "ctor"

  let matcher = new_arg_matcher()
  matcher.parse(node.gene.children[0])

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
  let class = new_class("Class")
  class.def_native_macro_method "ctor", class_ctor
  class.def_native_macro_method "fn", class_fn
  let r = new_ref(VkClass)
  r.class = class
  App.ref.app.class_class = r.to_ref_value()
