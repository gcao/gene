proc to_ctor(node: Value): Function =
  var name = "ctor"

  var matcher = new_arg_matcher()
  matcher.parse(node.gene.children[0])

  var body: seq[Value] = @[]
  for i in 1..<node.gene.children.len:
    body.add node.gene.children[i]

  # body = wrap_with_try(body)
  result = new_fn(name, matcher, body)

proc class_ctor(vm_data: VirtualMachineData, args: Value): Value =
  var fn = to_ctor(args)
  fn.ns = vm_data.registers.ns
  vm_data.registers.self.to_ref.class.constructor = Reference(kind: VkFunction, fn: fn)

proc class_fn(vm_data: VirtualMachineData, args: Value): Value =
  let self = args.gene.type.to_ref.bound_method.self
  # define a fn like method on a class
  var fn = to_function(args)

  var m = Method(
    name: fn.name,
    callable: Reference(kind: VkFunction, fn: fn),
  )
  case self.kind:
  of VkClass:
    let klass = self.to_ref.class
    m.class = klass
    fn.ns = klass.ns
    klass.methods[m.name] = m
  # of VkMixin:
  #   fn.ns = self.mixin.ns
  #   self.mixin.methods[m.name] = m
  else:
    not_allowed()

VMCreatedCallbacks.add proc() =
  let class = new_class("Class")
  class.def_native_macro_method "ctor", class_ctor
  class.def_native_macro_method "fn", class_fn
  App.to_ref.app.class_class = Reference(kind: VkClass, class: class).to_value()
