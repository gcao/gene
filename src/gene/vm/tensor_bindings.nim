import ../types
import ./tensor
import std/[strformat, sequtils]

# Native function wrappers for tensor operations

proc tensor_create_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/create [2 3]) or (tensor/create [2 3] :float32 :cpu)
  if args.gene.children.len < 1:
    raise new_exception(Exception, "tensor/create requires at least shape argument")
  
  let shape_val = args.gene.children[0]
  if shape_val.kind != VkArray and shape_val.kind != VkVector:
    raise new_exception(Exception, "tensor shape must be an array")
  
  var shape: seq[int] = @[]
  for v in shape_val.ref.arr:
    if v.kind != VkInt:
      raise new_exception(Exception, "tensor shape elements must be integers")
    shape.add(v.int64.int)
  
  # Optional dtype and device arguments
  var dtype = DtFloat32
  var device = DevCPU
  
  if args.gene.children.len > 1:
    let dtype_val = args.gene.children[1]
    if dtype_val.kind == VkSymbol:
      case dtype_val.str:
      of "float32", ":float32": dtype = DtFloat32
      of "float16", ":float16": dtype = DtFloat16
      of "int32", ":int32": dtype = DtInt32
      of "int64", ":int64": dtype = DtInt64
      of "int8", ":int8": dtype = DtInt8
      of "bool", ":bool": dtype = DtBool
      else:
        raise new_exception(Exception, &"Unknown dtype: {dtype_val.str}")
  
  if args.gene.children.len > 2:
    let device_val = args.gene.children[2]
    if device_val.kind == VkSymbol:
      case device_val.str:
      of "cpu", ":cpu": device = DevCPU
      of "cuda", ":cuda": device = DevCUDA
      of "metal", ":metal": device = DevMetal
      else:
        raise new_exception(Exception, &"Unknown device: {device_val.str}")
  
  self.frame.push(new_tensor(shape, dtype, device))

proc tensor_zeros_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/zeros [3 3])
  if args.gene.children.len < 1:
    raise new_exception(Exception, "tensor/zeros requires shape argument")
  
  let shape_val = args.gene.children[0]
  if shape_val.kind != VkArray and shape_val.kind != VkVector:
    raise new_exception(Exception, "tensor shape must be an array")
  
  var shape: seq[int] = @[]
  for v in shape_val.ref.arr:
    if v.kind != VkInt:
      raise new_exception(Exception, "tensor shape elements must be integers")
    shape.add(v.int64.int)
  
  self.frame.push(tensor_zeros(shape))

proc tensor_ones_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/ones [3 3])
  if args.gene.children.len < 1:
    raise new_exception(Exception, "tensor/ones requires shape argument")
  
  let shape_val = args.gene.children[0]
  if shape_val.kind != VkArray and shape_val.kind != VkVector:
    raise new_exception(Exception, "tensor shape must be an array")
  
  var shape: seq[int] = @[]
  for v in shape_val.ref.arr:
    if v.kind != VkInt:
      raise new_exception(Exception, "tensor shape elements must be integers")
    shape.add(v.int64.int)
  
  self.frame.push(tensor_ones(shape))

proc tensor_random_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/random [3 3])
  if args.gene.children.len < 1:
    raise new_exception(Exception, "tensor/random requires shape argument")
  
  let shape_val = args.gene.children[0]
  if shape_val.kind != VkArray and shape_val.kind != VkVector:
    raise new_exception(Exception, "tensor shape must be an array")
  
  var shape: seq[int] = @[]
  for v in shape_val.ref.arr:
    if v.kind != VkInt:
      raise new_exception(Exception, "tensor shape elements must be integers")
    shape.add(v.int64.int)
  
  self.frame.push(tensor_random(shape))

proc tensor_add_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/add a b) or (+ a b) for tensors
  if args.gene.children.len != 2:
    raise new_exception(Exception, "tensor/add requires exactly 2 arguments")
  
  let a = args.gene.children[0]
  let b = args.gene.children[1]
  self.frame.push(tensor_add(a, b))

proc tensor_sub_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/sub a b) or (- a b) for tensors
  if args.gene.children.len != 2:
    raise new_exception(Exception, "tensor/sub requires exactly 2 arguments")
  
  let a = args.gene.children[0]
  let b = args.gene.children[1]
  self.frame.push(tensor_sub(a, b))

proc tensor_mul_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/mul a b) or (* a b) for tensors
  if args.gene.children.len != 2:
    raise new_exception(Exception, "tensor/mul requires exactly 2 arguments")
  
  let a = args.gene.children[0]
  let b = args.gene.children[1]
  self.frame.push(tensor_mul(a, b))

proc tensor_div_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/div a b) or (/ a b) for tensors
  if args.gene.children.len != 2:
    raise new_exception(Exception, "tensor/div requires exactly 2 arguments")
  
  let a = args.gene.children[0]
  let b = args.gene.children[1]
  self.frame.push(tensor_div(a, b))

proc tensor_matmul_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/matmul a b) or (@ a b)
  if args.gene.children.len != 2:
    raise new_exception(Exception, "tensor/matmul requires exactly 2 arguments")
  
  let a = args.gene.children[0]
  let b = args.gene.children[1]
  self.frame.push(tensor_matmul(a, b))

proc tensor_reshape_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/reshape tensor [new shape])
  if args.gene.children.len != 2:
    raise new_exception(Exception, "tensor/reshape requires tensor and new shape")
  
  let tensor = args.gene.children[0]
  let shape_val = args.gene.children[1]
  
  if shape_val.kind != VkArray and shape_val.kind != VkVector:
    raise new_exception(Exception, "new shape must be an array")
  
  var shape: seq[int] = @[]
  for v in shape_val.ref.arr:
    if v.kind != VkInt:
      raise new_exception(Exception, "shape elements must be integers")
    shape.add(v.int64.int)
  
  self.frame.push(tensor_reshape(tensor, shape))

proc tensor_transpose_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/transpose tensor)
  if args.gene.children.len != 1:
    raise new_exception(Exception, "tensor/transpose requires exactly 1 argument")
  
  let tensor = args.gene.children[0]
  self.frame.push(tensor_transpose(tensor))

proc tensor_shape_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/shape tensor) - returns shape as array
  if args.gene.children.len != 1:
    raise new_exception(Exception, "tensor/shape requires exactly 1 argument")
  
  let tensor = args.gene.children[0]
  if tensor.kind != VkTensor:
    raise new_exception(Exception, "tensor/shape expects a tensor")
  
  var shape_array: seq[Value] = @[]
  for dim in tensor.ref.tensor.shape:
    shape_array.add(dim.to_value())
  
  self.frame.push(new_array_value(shape_array))

proc tensor_dtype_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/dtype tensor) - returns dtype as symbol
  if args.gene.children.len != 1:
    raise new_exception(Exception, "tensor/dtype requires exactly 1 argument")
  
  let tensor = args.gene.children[0]
  if tensor.kind != VkTensor:
    raise new_exception(Exception, "tensor/dtype expects a tensor")
  
  let dtype_str = case tensor.ref.tensor.dtype:
    of DtFloat32: "float32"
    of DtFloat16: "float16"
    of DtBFloat16: "bfloat16"
    of DtInt8: "int8"
    of DtInt16: "int16"
    of DtInt32: "int32"
    of DtInt64: "int64"
    of DtUInt8: "uint8"
    of DtBool: "bool"
  
  self.frame.push(dtype_str.to_symbol_value())

proc tensor_device_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/device tensor) - returns device as symbol
  if args.gene.children.len != 1:
    raise new_exception(Exception, "tensor/device requires exactly 1 argument")
  
  let tensor = args.gene.children[0]
  if tensor.kind != VkTensor:
    raise new_exception(Exception, "tensor/device expects a tensor")
  
  let device_str = case tensor.ref.tensor.device:
    of DevCPU: "cpu"
    of DevCUDA: "cuda"
    of DevMetal: "metal"
    of DevTPU: "tpu"
  
  self.frame.push(device_str.to_symbol_value())

proc tensor_info_native*(self: VirtualMachine, args: Value): Value =
  # (tensor/info tensor) - returns string description
  if args.gene.children.len != 1:
    raise new_exception(Exception, "tensor/info requires exactly 1 argument")
  
  let tensor = args.gene.children[0]
  if tensor.kind != VkTensor:
    raise new_exception(Exception, "tensor/info expects a tensor")
  
  let info = tensor_info(tensor)
  self.frame.push(info.to_value())

# Register all tensor native functions
proc register_tensor_natives*(vm: VirtualMachine) =
  # These would be registered in the global namespace
  # For now, we'll use a placeholder registration mechanism
  discard