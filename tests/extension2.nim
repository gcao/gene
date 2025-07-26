include ../src/gene/extension/boilerplate

type
  Extension2 = ref object of CustomValue
    name: string

proc new_extension2*(vm: VirtualMachine, args: Value): Value {.gcsafe.} =
  let r = new_ref(VkCustom)
  r.custom_data = Extension2(
    name: if args.gene.children.len > 0: args.gene.children[0].str else: ""
  )
  result = r.to_ref_value()

proc extension2_name*(vm: VirtualMachine, args: Value): Value {.gcsafe.} =
  if args.gene.children.len > 0 and args.gene.children[0].kind == VkCustom:
    let ext = cast[Extension2](args.gene.children[0].ref.custom_data)
    return ext.name.to_value()
  "".to_value()

{.push dynlib exportc.}

proc init*(vm: ptr VirtualMachine): Namespace =
  result = new_namespace("extension2")
  
  # Register functions
  var new_ext2_ref = new_ref(VkNativeFn)
  new_ext2_ref.native_fn = new_extension2
  result["new_extension2".to_key()] = new_ext2_ref.to_ref_value()
  
  var ext2_name_ref = new_ref(VkNativeFn)
  ext2_name_ref.native_fn = extension2_name
  result["extension2_name".to_key()] = ext2_name_ref.to_ref_value()

{.pop.}