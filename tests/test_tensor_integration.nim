import unittest
import ../src/gene/types
import ../src/gene/vm/tensor

suite "Tensor Integration Tests":
  test "Tensor display":
    let t = new_tensor(@[2, 3], DtFloat32, DevCPU)
    let str = $t
    check str == "<Tensor shape=@[2, 3] dtype=float32 device=cpu>"
  
  test "Tensor arithmetic operations":
    let a = new_tensor(@[2, 3], DtFloat32, DevCPU)
    let b = new_tensor(@[2, 3], DtFloat32, DevCPU)
    
    # Test addition
    let sum = tensor_add(a, b)
    check sum.kind == VkTensor
    check sum.ref.tensor.shape == @[2, 3]
    
    # Test subtraction
    let diff = tensor_sub(a, b)
    check diff.kind == VkTensor
    check diff.ref.tensor.shape == @[2, 3]
    
    # Test multiplication
    let prod = tensor_mul(a, b)
    check prod.kind == VkTensor
    check prod.ref.tensor.shape == @[2, 3]
    
    # Test division
    let quot = tensor_div(a, b)
    check quot.kind == VkTensor
    check quot.ref.tensor.shape == @[2, 3]
  
  test "Tensor matmul shapes":
    let a = new_tensor(@[2, 3], DtFloat32, DevCPU)
    let b = new_tensor(@[3, 4], DtFloat32, DevCPU)
    
    let result = tensor_matmul(a, b)
    check result.kind == VkTensor
    check result.ref.tensor.shape == @[2, 4]
  
  test "Tensor reshape":
    let t = new_tensor(@[2, 3], DtFloat32, DevCPU)
    
    # Reshape to 3x2
    let reshaped = tensor_reshape(t, @[3, 2])
    check reshaped.kind == VkTensor
    check reshaped.ref.tensor.shape == @[3, 2]
    
    # Reshape to 1D
    let flat = tensor_reshape(t, @[6])
    check flat.kind == VkTensor
    check flat.ref.tensor.shape == @[6]
    
    # Reshape with inferred dimension
    let inferred = tensor_reshape(t, @[-1, 2])
    check inferred.kind == VkTensor
    check inferred.ref.tensor.shape == @[3, 2]
  
  test "Tensor transpose":
    let t = new_tensor(@[2, 3], DtFloat32, DevCPU)
    let transposed = tensor_transpose(t)
    check transposed.kind == VkTensor
    check transposed.ref.tensor.shape == @[3, 2]
  
  test "Tensor special creation":
    # Zeros
    let zeros = tensor_zeros(@[3, 3], DtFloat32, DevCPU)
    check zeros.kind == VkTensor
    check zeros.ref.tensor.shape == @[3, 3]
    
    # Ones
    let ones = tensor_ones(@[2, 4], DtFloat32, DevCPU)
    check ones.kind == VkTensor
    check ones.ref.tensor.shape == @[2, 4]
    
    # Random
    let random = tensor_random(@[5, 5], DtFloat32, DevCPU)
    check random.kind == VkTensor
    check random.ref.tensor.shape == @[5, 5]
  
  test "Tensor device types":
    let cpu_tensor = new_tensor(@[2, 2], DtFloat32, DevCPU)
    check cpu_tensor.ref.tensor.device == DevCPU
    
    let cuda_tensor = new_tensor(@[2, 2], DtFloat32, DevCUDA)
    check cuda_tensor.ref.tensor.device == DevCUDA
    
    let metal_tensor = new_tensor(@[2, 2], DtFloat32, DevMetal)
    check metal_tensor.ref.tensor.device == DevMetal
  
  test "Tensor data types":
    let f32_tensor = new_tensor(@[2, 2], DtFloat32, DevCPU)
    check f32_tensor.ref.tensor.dtype == DtFloat32
    
    let i32_tensor = new_tensor(@[2, 2], DtInt32, DevCPU)
    check i32_tensor.ref.tensor.dtype == DtInt32
    
    let bool_tensor = new_tensor(@[2, 2], DtBool, DevCPU)
    check bool_tensor.ref.tensor.dtype == DtBool
  
  test "Tensor info string":
    let t = new_tensor(@[3, 4], DtFloat16, DevCUDA)
    let info = tensor_info(t)
    check info == "Tensor(shape=@[3, 4], dtype=DtFloat16, device=DevCUDA:0)"
  
  test "Model display":
    let m = new_model("test-model", "onnx")
    let str = $m
    check str == "<Model name=test-model format=onnx>"
  
  test "Device display":
    let d = new_device(DevCUDA, 1)
    let str = $d
    check str == "<Device cuda:1>"
  
  test "Tokenizer display":
    let t = new_tokenizer(50000)
    let str = $t
    check str == "<Tokenizer vocab_size=50000>"
  
  test "DataLoader display":
    let dataset = new_array_value([1.to_value, 2.to_value])
    let dl = new_dataloader(dataset, 32, true)
    let str = $dl
    check str == "<DataLoader batch_size=32>"