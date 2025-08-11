import ../types

# Helper for runtime errors
proc runtime_error(msg: string) =
  raise new_exception(types.Exception, msg)

# Basic tensor operations

proc tensor_sub*(a, b: Value): Value =
  if a.kind != VkTensor or b.kind != VkTensor:
    runtime_error("tensor_sub expects two tensors")
  
  let ta = a.ref.tensor
  let tb = b.ref.tensor
  
  # Check shapes match
  if ta.shape != tb.shape:
    runtime_error("tensor shapes must match for subtraction")
  
  # Check dtypes match
  if ta.dtype != tb.dtype:
    runtime_error("tensor dtypes must match for subtraction")
  
  # Create result tensor
  result = new_tensor(ta.shape, ta.dtype, ta.device)

proc tensor_div*(a, b: Value): Value =
  if a.kind != VkTensor or b.kind != VkTensor:
    runtime_error("tensor_div expects two tensors")
  
  let ta = a.ref.tensor
  let tb = b.ref.tensor
  
  # Check shapes match
  if ta.shape != tb.shape:
    runtime_error("tensor shapes must match for division")
  
  # Check dtypes match
  if ta.dtype != tb.dtype:
    runtime_error("tensor dtypes must match for division")
  
  # Create result tensor
  result = new_tensor(ta.shape, ta.dtype, ta.device)

proc tensor_add*(a, b: Value): Value =
  if a.kind != VkTensor or b.kind != VkTensor:
    runtime_error("tensor_add expects two tensors")
  
  let ta = a.ref.tensor
  let tb = b.ref.tensor
  
  # Check shapes match
  if ta.shape != tb.shape:
    runtime_error("tensor shapes must match for addition")
  
  # Check dtypes match
  if ta.dtype != tb.dtype:
    runtime_error("tensor dtypes must match for addition")
  
  # Create result tensor
  result = new_tensor(ta.shape, ta.dtype, ta.device)
  # Note: Actual data operations would require FFI to numerical libraries
  
proc tensor_mul*(a, b: Value): Value =
  if a.kind != VkTensor or b.kind != VkTensor:
    runtime_error("tensor_mul expects two tensors")
  
  let ta = a.ref.tensor
  let tb = b.ref.tensor
  
  # Element-wise multiplication
  if ta.shape != tb.shape:
    runtime_error("tensor shapes must match for element-wise multiplication")
  
  if ta.dtype != tb.dtype:
    runtime_error("tensor dtypes must match for multiplication")
  
  result = new_tensor(ta.shape, ta.dtype, ta.device)

proc tensor_matmul*(a, b: Value): Value =
  if a.kind != VkTensor or b.kind != VkTensor:
    runtime_error("tensor_matmul expects two tensors")
  
  let ta = a.ref.tensor
  let tb = b.ref.tensor
  
  # Check for 2D tensors
  if ta.shape.len != 2 or tb.shape.len != 2:
    runtime_error("matrix multiplication requires 2D tensors")
  
  # Check dimensions match
  if ta.shape[1] != tb.shape[0]:
    runtime_error("incompatible dimensions for matrix multiplication")
  
  # Result shape
  let result_shape = @[ta.shape[0], tb.shape[1]]
  result = new_tensor(result_shape, ta.dtype, ta.device)

proc tensor_reshape*(t: Value, new_shape: seq[int]): Value =
  if t.kind != VkTensor:
    runtime_error("tensor_reshape expects a tensor")
  
  let tensor = t.ref.tensor
  
  # Calculate total elements
  var old_size = 1
  for dim in tensor.shape:
    old_size *= dim
  
  var new_size = 1
  var infer_dim = -1
  for i, dim in new_shape:
    if dim == -1:
      if infer_dim >= 0:
        runtime_error("can only infer one dimension")
      infer_dim = i
    else:
      new_size *= dim
  
  # Infer dimension if needed
  var final_shape = new_shape
  if infer_dim >= 0:
    if old_size mod new_size != 0:
      runtime_error("cannot reshape tensor of size " & $old_size & " into shape with partial size " & $new_size)
    final_shape[infer_dim] = old_size div new_size
  else:
    if old_size != new_size:
      runtime_error("cannot reshape tensor of size " & $old_size & " into size " & $new_size)
  
  result = new_tensor(final_shape, tensor.dtype, tensor.device)
  result.ref.tensor.data_ptr = tensor.data_ptr  # Share data

proc tensor_transpose*(t: Value): Value =
  if t.kind != VkTensor:
    runtime_error("tensor_transpose expects a tensor")
  
  let tensor = t.ref.tensor
  
  if tensor.shape.len != 2:
    runtime_error("transpose only supports 2D tensors")
  
  let new_shape = @[tensor.shape[1], tensor.shape[0]]
  result = new_tensor(new_shape, tensor.dtype, tensor.device)

proc tensor_slice*(t: Value, start: seq[int], stop: seq[int]): Value =
  if t.kind != VkTensor:
    runtime_error("tensor_slice expects a tensor")
  
  let tensor = t.ref.tensor
  
  if start.len != tensor.shape.len or stop.len != tensor.shape.len:
    runtime_error("slice dimensions must match tensor dimensions")
  
  var new_shape: seq[int] = @[]
  for i in 0..<tensor.shape.len:
    if start[i] < 0 or start[i] >= tensor.shape[i]:
      runtime_error("slice start index out of bounds")
    if stop[i] < start[i] or stop[i] > tensor.shape[i]:
      runtime_error("slice stop index out of bounds")
    new_shape.add(stop[i] - start[i])
  
  result = new_tensor(new_shape, tensor.dtype, tensor.device)

proc tensor_zeros*(shape: seq[int], dtype: DType = DtFloat32, device: DeviceKind = DevCPU): Value =
  result = new_tensor(shape, dtype, device)
  # Initialize with zeros (would be done via FFI in real implementation)

proc tensor_ones*(shape: seq[int], dtype: DType = DtFloat32, device: DeviceKind = DevCPU): Value =
  result = new_tensor(shape, dtype, device)
  # Initialize with ones (would be done via FFI in real implementation)

proc tensor_random*(shape: seq[int], dtype: DType = DtFloat32, device: DeviceKind = DevCPU): Value =
  result = new_tensor(shape, dtype, device)
  # Initialize with random values (would be done via FFI in real implementation)

# Helper to get tensor info
proc tensor_info*(t: Value): string =
  if t.kind != VkTensor:
    return "Not a tensor"
  
  let tensor = t.ref.tensor
  result = "Tensor(shape=" & $tensor.shape & 
           ", dtype=" & $tensor.dtype & 
           ", device=" & $tensor.device & ":" & $tensor.device_id & ")"

# Register tensor operations with VM
proc register_tensor_ops*(vm: VirtualMachine) =
  # These would be registered as native functions
  discard