## Native function registration for AI/ML operations

import ../types
import ../vm
import ./ai_bindings
import std/tables

# Native function wrappers with correct signatures
proc native_tokenizer_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 1:
    return NIL
  let vocab_size = args.ref.arr[0].to_int
  return gene_tokenizer_create(vocab_size)

proc native_embedding_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 1:
    return NIL
  let dim = args.ref.arr[0].to_int
  return gene_embedding_create(dim)

proc native_model_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 2:
    return NIL
  let name = args.ref.arr[0].to_s
  let model_type = args.ref.arr[1].to_s
  return gene_model_create(name, model_type)

proc native_device_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 1:
    return NIL
  let device_type = if args.ref.arr[0].kind == VkSymbol:
    args.ref.arr[0].to_s
  else:
    args.ref.arr[0].to_s
  return gene_device_create(device_type)

proc native_model_session(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 2:
    return NIL
  return gene_model_session_create(args.ref.arr[0], args.ref.arr[1])

proc native_model_configure(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Simplified - just return success
  return TRUE

proc native_tensor_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len < 1:
    return NIL
  
  # Parse shape array
  var shape: seq[int] = @[]
  let shape_val = args.ref.arr[0]
  if shape_val.kind == VkArray:
    for v in shape_val.ref.arr:
      shape.add(v.to_int)
  
  # Parse optional dtype
  var dtype = "float32"
  if args.ref.arr.len > 1 and args.ref.arr[1].kind == VkSymbol:
    dtype = args.ref.arr[1].to_s
  
  # Parse optional device  
  var device = "cpu"
  if args.ref.arr.len > 2 and args.ref.arr[2].kind == VkSymbol:
    device = args.ref.arr[2].to_s
  
  return gene_tensor_create(shape, dtype, device)

proc native_tensor_random(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 1:
    return NIL
  
  var shape: seq[int] = @[]
  let shape_val = args.ref.arr[0]
  if shape_val.kind == VkArray:
    for v in shape_val.ref.arr:
      shape.add(v.to_int)
  
  return gene_tensor_random(shape)

proc native_tensor_zeros(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 1:
    return NIL
  
  var shape: seq[int] = @[]
  let shape_val = args.ref.arr[0]
  if shape_val.kind == VkArray:
    for v in shape_val.ref.arr:
      shape.add(v.to_int)
  
  return gene_tensor_zeros(shape)

proc native_tensor_add(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 2:
    return NIL
  return gene_tensor_add(args.ref.arr[0], args.ref.arr[1])

proc native_tensor_matmul(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 2:
    return NIL
  return gene_tensor_matmul(args.ref.arr[0], args.ref.arr[1])

proc native_tensor_transpose(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 1:
    return NIL
  return gene_tensor_transpose(args.ref.arr[0])

proc native_tensor_shape(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkArray or args.ref.arr.len != 1 or args.ref.arr[0].kind != VkTensor:
    return NIL
  
  # Return shape as array
  result = new_ref(VkArray)
  for dim in args.ref.arr[0].ref.tensor.shape:
    result.ref.arr.add(to_value(dim))

proc native_tensor_reshape(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # For now, just return the tensor unchanged
  if args.kind != VkArray or args.ref.arr.len != 2:
    return NIL
  return args.ref.arr[0]

proc native_tensor_slice(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # For now, just return the tensor unchanged
  if args.kind != VkArray or args.ref.arr.len < 1:
    return NIL
  return args.ref.arr[0]

proc native_tensor_div(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Simplified - just return first tensor
  if args.kind != VkArray or args.ref.arr.len != 2:
    return NIL
  return args.ref.arr[0]

proc native_tensor_transform(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Simplified - just return the tensor unchanged
  if args.kind != VkArray or args.ref.arr.len != 1:
    return NIL
  return args.ref.arr[0]

# Register all native functions
proc register_ai_natives*(vm: VirtualMachine) =
  # Get the global namespace from App
  let global_ns = App.app.global_ns.ref.ns
  
  # Tokenizer namespace
  let tokenizer_ns = new_namespace("tokenizer")
  tokenizer_ns.members["create"] = new_native_fn("tokenizer/create", native_tokenizer_create)
  global_ns.members["tokenizer"] = tokenizer_ns.to_value()
  
  # Embedding namespace
  let embedding_ns = new_namespace("embedding")
  embedding_ns.members["create"] = new_native_fn("embedding/create", native_embedding_create)
  global_ns.members["embedding"] = embedding_ns.to_value()
  
  # Model namespace
  let model_ns = new_namespace("model")
  model_ns.members["create"] = new_native_fn("model/create", native_model_create)
  model_ns.members["session"] = new_native_fn("model/session", native_model_session)
  model_ns.members["configure"] = new_native_fn("model/configure", native_model_configure)
  global_ns.members["model"] = model_ns.to_value()
  
  # Device namespace
  let device_ns = new_namespace("device")
  device_ns.members["create"] = new_native_fn("device/create", native_device_create)
  global_ns.members["device"] = device_ns.to_value()
  
  # Tensor namespace
  let tensor_ns = new_namespace("tensor")
  tensor_ns.members["create"] = new_native_fn("tensor/create", native_tensor_create)
  tensor_ns.members["random"] = new_native_fn("tensor/random", native_tensor_random)
  tensor_ns.members["zeros"] = new_native_fn("tensor/zeros", native_tensor_zeros)
  tensor_ns.members["add"] = new_native_fn("tensor/add", native_tensor_add)
  tensor_ns.members["matmul"] = new_native_fn("tensor/matmul", native_tensor_matmul)
  tensor_ns.members["transpose"] = new_native_fn("tensor/transpose", native_tensor_transpose)
  tensor_ns.members["shape"] = new_native_fn("tensor/shape", native_tensor_shape)
  tensor_ns.members["reshape"] = new_native_fn("tensor/reshape", native_tensor_reshape)
  tensor_ns.members["slice"] = new_native_fn("tensor/slice", native_tensor_slice)
  tensor_ns.members["div"] = new_native_fn("tensor/div", native_tensor_div)
  tensor_ns.members["transform"] = new_native_fn("tensor/transform", native_tensor_transform)
  global_ns.members["tensor"] = tensor_ns.to_value()

# Helper to create native function value
proc new_native_fn(name: string, fn: NativeFn): Value =
  result = new_ref(VkNativeFn)
  result.ref.native_fn = fn