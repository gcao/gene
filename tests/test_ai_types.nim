import unittest
import ../src/gene/types

suite "AI/ML Types":
  test "Create tensor":
    let t = new_tensor(@[2, 3], DtFloat32, DevCPU)
    check t.kind == VkTensor
    check t.ref.tensor.shape == @[2, 3]
    check t.ref.tensor.dtype == DtFloat32
    check t.ref.tensor.device == DevCPU
    check t.ref.tensor.size == 6
    check t.ref.tensor.strides == @[3, 1]
  
  test "Create model":
    let m = new_model("test-model", "onnx")
    check m.kind == VkModel
    check m.ref.model.name == "test-model"
    check m.ref.model.format == "onnx"
  
  test "Create device":
    let d = new_device(DevCUDA, 0)
    check d.kind == VkDevice
    check d.ref.device.kind == DevCUDA
    check d.ref.device.id == 0
    check d.ref.device.name == "DevCUDA:0"
  
  test "Create gradient tape":
    let g = new_gradient_tape()
    check g.kind == VkGradient
    check g.ref.gradient.tensors.len == 0
    check g.ref.gradient.operations.len == 0
  
  test "Create tokenizer":
    let t = new_tokenizer(10000)
    check t.kind == VkTokenizer
    check t.ref.tokenizer.vocab_size == 10000
  
  test "Create embedding":
    let e = new_embedding(512)
    check e.kind == VkEmbedding
    check e.ref.embedding.dim == 512
  
  test "Create dataloader":
    let dataset = new_array_value([1.to_value, 2.to_value, 3.to_value])
    let dl = new_dataloader(dataset, 2, true)
    check dl.kind == VkDataLoader
    check dl.ref.dataloader.batch_size == 2
    check dl.ref.dataloader.shuffle == true
    check dl.ref.dataloader.current_batch == 0