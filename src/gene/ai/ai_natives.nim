## Native function registration for AI/ML operations

import ../types
import ./ai_bindings
from ./ai_bindings import tokenizer_create, model_create, device_create,
  tensor_create, tensor_random, tensor_zeros, tensor_add, tensor_matmul,
  tensor_transpose, embedding_create, model_session_create

# Helper to create native function value
proc new_native_fn(name: string, fn: NativeFn): Value =
  let r = new_ref(VkNativeFn)
  r.native_fn = fn
  result = r.to_ref_value()
import std/tables

# Native function wrappers with correct signatures - using Gene S-expressions
proc native_tokenizer_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  let vocab_size = gene_args.children[0].to_int
  
  # Create tokenizer using C API
  let ctokenizer = tokenizer_create(vocab_size.cint)
  if ctokenizer == nil:
    return NIL
  
  # Wrap in Gene value
  let r = new_ref(VkMap)
  r.map["ptr".to_key()] = to_value(cast[int](ctokenizer))
  r.map["type".to_key()] = to_value("tokenizer")
  r.map["vocab_size".to_key()] = to_value(vocab_size)
  return r.to_ref_value()

proc native_embedding_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  let dim = gene_args.children[0].to_int
  
  # Create embedding using C API
  let cembedding = embedding_create(dim.cint)
  if cembedding == nil:
    return NIL
  
  # Wrap in Gene value as a map for now
  # A full implementation would use VkEmbedding with proper data structure
  let r = new_ref(VkMap)
  r.map["ptr".to_key()] = to_value(cast[int](cembedding))
  r.map["type".to_key()] = to_value("embedding")
  r.map["dim".to_key()] = to_value(dim)
  return r.to_ref_value()

proc native_model_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 2:
    return NIL
  let name = gene_args.children[0].str
  let model_type = gene_args.children[1].str
  
  # Create model using C API
  let cmodel = model_create(name.cstring, model_type.cstring)
  if cmodel == nil:
    return NIL
  
  # Wrap in Gene value
  let r = new_ref(VkMap)
  r.map["ptr".to_key()] = to_value(cast[int](cmodel))
  r.map["type".to_key()] = to_value("model")
  r.map["name".to_key()] = to_value(name)
  r.map["model_type".to_key()] = to_value(model_type)
  return r.to_ref_value()

proc native_device_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  let device_type = gene_args.children[0].str
  
  # Create device using C API
  let cdevice = device_create(device_type.cstring)
  if cdevice == nil:
    # Fallback to mock device
    let r = new_ref(VkMap)
    r.map["type".to_key()] = to_value("device")
    r.map["device_type".to_key()] = to_value(device_type)
    return r.to_ref_value()
  
  # Wrap in Gene value
  let r = new_ref(VkMap)
  r.map["ptr".to_key()] = to_value(cast[int](cdevice))
  r.map["type".to_key()] = to_value("device")
  r.map["device_type".to_key()] = to_value(device_type)
  return r.to_ref_value()

proc native_model_session(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 2:
    return NIL
  
  # Extract model and device from arguments
  let model_arg = gene_args.children[0]
  let device_arg = gene_args.children[1]
  
  # For now, return a simple map representation
  # A full implementation would extract pointers and call model_session_create
  let r = new_ref(VkMap)
  r.map["type".to_key()] = to_value("model_session")
  r.map["model".to_key()] = model_arg
  r.map["device".to_key()] = device_arg
  return r.to_ref_value()

proc native_model_configure(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Configuration would set model parameters
  # For now, just acknowledge the request
  return TRUE

proc native_tensor_create(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  
  # Parse shape array
  let shape_value = gene_args.children[0]
  if shape_value.kind != VkArray:
    return NIL
  
  var shape_cint: seq[cint] = @[]
  var shape: seq[int] = @[]
  for dim in shape_value.ref.arr:
    shape_cint.add(dim.to_int.cint)
    shape.add(dim.to_int)
  
  # Parse dtype if provided
  var dtype = "float32"
  if gene_args.children.len > 1:
    if gene_args.children[1].kind == VkSymbol:
      dtype = gene_args.children[1].str
  
  # Parse device if provided  
  var device = "cpu"
  if gene_args.children.len > 2:
    device = gene_args.children[2].str
  
  # Create tensor using C API
  let ctensor = tensor_create(addr shape_cint[0], shape_cint.len.cint, dtype.cstring, device.cstring)
  if ctensor == nil:
    return NIL
  
  # Convert dtype string to enum
  let dtype_enum = case dtype:
    of "float32": DtFloat32
    of "float16": DtFloat16
    of "int8": DtInt8
    of "int32": DtInt32
    of "int64": DtInt64
    else: DtFloat32  # Default
  
  # Convert device string to enum
  let device_enum = case device:
    of "cpu": DevCPU
    of "cuda": DevCUDA
    of "metal": DevMetal
    of "tpu": DevTPU
    else: DevCPU  # Default
  
  # Wrap in Gene value
  let r = new_ref(VkTensor)
  r.tensor = TensorData(
    data_ptr: cast[pointer](ctensor),
    shape: shape,
    size: shape.len,
    dtype: dtype_enum,
    device: device_enum
  )
  return r.to_ref_value()

proc native_tensor_random(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  
  # Parse shape array
  let shape_value = gene_args.children[0]
  if shape_value.kind != VkArray:
    return NIL
  
  var shape_cint: seq[cint] = @[]
  var shape: seq[int] = @[]
  for dim in shape_value.ref.arr:
    shape_cint.add(dim.to_int.cint)
    shape.add(dim.to_int)
  
  # Create random tensor using C API
  let ctensor = tensor_random(addr shape_cint[0], shape_cint.len.cint)
  if ctensor == nil:
    return NIL
  
  # Wrap in Gene value
  let r = new_ref(VkTensor)
  r.tensor = TensorData(
    data_ptr: cast[pointer](ctensor),
    shape: shape,
    size: shape.len,
    dtype: DtFloat32,
    device: DevCPU
  )
  return r.to_ref_value()

proc native_tensor_zeros(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  
  # Parse shape array
  let shape_value = gene_args.children[0]
  if shape_value.kind != VkArray:
    return NIL
  
  var shape_cint: seq[cint] = @[]
  var shape: seq[int] = @[]
  for dim in shape_value.ref.arr:
    shape_cint.add(dim.to_int.cint)
    shape.add(dim.to_int)
  
  # Create zeros tensor using C API
  let ctensor = tensor_zeros(addr shape_cint[0], shape_cint.len.cint)
  if ctensor == nil:
    return NIL
  
  # Wrap in Gene value
  let r = new_ref(VkTensor)
  r.tensor = TensorData(
    data_ptr: cast[pointer](ctensor),
    shape: shape,
    size: shape.len,
    dtype: DtFloat32,
    device: DevCPU
  )
  return r.to_ref_value()

proc native_tensor_add(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Simplified - just return first tensor
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  return gene_args.children[0]

proc native_tensor_matmul(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Simplified - just return first tensor
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  return gene_args.children[0]

proc native_tensor_transpose(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Simplified - just return the tensor unchanged
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  return gene_args.children[0]

proc native_tensor_shape(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  
  let tensor = gene_args.children[0]
  if tensor.kind != VkTensor:
    return NIL
  
  # Return shape as array
  let arr = new_ref(VkArray)
  for dim in tensor.ref.tensor.shape:
    arr.arr.add(to_value(dim))
  result = arr.to_ref_value()

proc native_tensor_reshape(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # For now, just return the tensor unchanged
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  return gene_args.children[0]

proc native_tensor_slice(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Simplified - just return the tensor unchanged
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  return gene_args.children[0]

proc native_tensor_div(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Simplified - just return first tensor
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  return gene_args.children[0]

proc native_tensor_transform(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  # Simplified - just return the tensor unchanged
  if args.kind != VkGene:
    return NIL
  let gene_args = args.gene
  if gene_args.children.len < 1:
    return NIL
  return gene_args.children[0]

proc register_ai_natives*(vm: VirtualMachine) =
  # Get the global namespace from App
  let global_ns = App.app.global_ns.ref.ns
  
  # Tokenizer namespace
  let tokenizer_ns = new_namespace("tokenizer")
  tokenizer_ns.members["create".to_key()] = new_native_fn("tokenizer/create", native_tokenizer_create)
  global_ns.members["tokenizer".to_key()] = tokenizer_ns.to_value()
  
  # Embedding namespace
  let embedding_ns = new_namespace("embedding")
  embedding_ns.members["create".to_key()] = new_native_fn("embedding/create", native_embedding_create)
  global_ns.members["embedding".to_key()] = embedding_ns.to_value()
  
  # Model namespace
  let model_ns = new_namespace("model")
  model_ns.members["create".to_key()] = new_native_fn("model/create", native_model_create)
  model_ns.members["session".to_key()] = new_native_fn("model/session", native_model_session)
  model_ns.members["configure".to_key()] = new_native_fn("model/configure", native_model_configure)
  global_ns.members["model".to_key()] = model_ns.to_value()
  
  # Device namespace
  let device_ns = new_namespace("device")
  device_ns.members["create".to_key()] = new_native_fn("device/create", native_device_create)
  global_ns.members["device".to_key()] = device_ns.to_value()
  
  # Tensor namespace
  let tensor_ns = new_namespace("tensor")
  tensor_ns.members["create".to_key()] = new_native_fn("tensor/create", native_tensor_create)
  tensor_ns.members["random".to_key()] = new_native_fn("tensor/random", native_tensor_random)
  tensor_ns.members["zeros".to_key()] = new_native_fn("tensor/zeros", native_tensor_zeros)
  tensor_ns.members["add".to_key()] = new_native_fn("tensor/add", native_tensor_add)
  tensor_ns.members["matmul".to_key()] = new_native_fn("tensor/matmul", native_tensor_matmul)
  tensor_ns.members["transpose".to_key()] = new_native_fn("tensor/transpose", native_tensor_transpose)
  tensor_ns.members["shape".to_key()] = new_native_fn("tensor/shape", native_tensor_shape)
  tensor_ns.members["reshape".to_key()] = new_native_fn("tensor/reshape", native_tensor_reshape)
  tensor_ns.members["slice".to_key()] = new_native_fn("tensor/slice", native_tensor_slice)
  tensor_ns.members["div".to_key()] = new_native_fn("tensor/div", native_tensor_div)
  tensor_ns.members["transform".to_key()] = new_native_fn("tensor/transform", native_tensor_transform)
  global_ns.members["tensor".to_key()] = tensor_ns.to_value()