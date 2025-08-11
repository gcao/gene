## AI/ML Bindings for Gene
## Provides FFI bindings to the C implementation

import ../types
import std/[os, tables]

# Compile the C implementation
const gene_ai_c = currentSourcePath.parentDir() / "gene_ai.c"
{.compile: gene_ai_c.}

# Use the header for type definitions
const gene_ai_h = currentSourcePath.parentDir() / "gene_ai.h"

type
  CGeneTensor {.importc: "GeneTensor", header: gene_ai_h.} = object
    data: ptr cfloat
    shape: ptr cint
    ndim: cint
    size: cint
    device: cstring

  CTokenizer {.importc: "GeneTokenizer", header: gene_ai_h.} = object
    vocab_size: cint
    vocab: ptr cstring

  CModel {.importc: "GeneModel", header: gene_ai_h.} = object
    name: cstring
    modelType {.importc: "type".}: cstring
    weights: pointer
    num_params: cint

  CDevice {.importc: "GeneDevice", header: gene_ai_h.} = object
    deviceType {.importc: "type".}: cstring
    id: cint

  CEmbedding {.importc: "GeneEmbedding", header: gene_ai_h.} = object
    dim: cint
    weights: ptr CGeneTensor

  CModelSession {.importc: "GeneModelSession", header: gene_ai_h.} = object
    model: ptr CModel
    device: ptr CDevice

# C function declarations - these are defined in the compiled C file
proc tensor_create*(shape: ptr cint, ndim: cint, dtype: cstring, device: cstring): ptr CGeneTensor {.importc, nodecl.}
proc tensor_random*(shape: ptr cint, ndim: cint): ptr CGeneTensor {.importc, nodecl.}
proc tensor_zeros*(shape: ptr cint, ndim: cint): ptr CGeneTensor {.importc, nodecl.}
proc tensor_add*(a, b: ptr CGeneTensor): ptr CGeneTensor {.importc, nodecl.}
proc tensor_matmul*(a, b: ptr CGeneTensor): ptr CGeneTensor {.importc, nodecl.}
proc tensor_transpose*(tensor: ptr CGeneTensor): ptr CGeneTensor {.importc, nodecl.}
proc tensor_free(tensor: ptr CGeneTensor) {.importc, nodecl.}
proc tensor_ndim(tensor: ptr CGeneTensor): cint {.importc, nodecl.}
proc tensor_shape(tensor: ptr CGeneTensor): ptr cint {.importc, nodecl.}
proc tensor_data(tensor: ptr CGeneTensor): ptr cfloat {.importc, nodecl.}
proc tensor_size(tensor: ptr CGeneTensor): cint {.importc, nodecl.}

proc tokenizer_create*(vocab_size: cint): ptr CTokenizer {.importc, nodecl.}
proc tokenizer_free(tokenizer: ptr CTokenizer) {.importc, nodecl.}

proc model_create*(name: cstring, modelType: cstring): ptr CModel {.importc, nodecl.}
proc model_free(model: ptr CModel) {.importc, nodecl.}

proc device_create*(deviceType: cstring): ptr CDevice {.importc, nodecl.}
proc device_free(device: ptr CDevice) {.importc, nodecl.}

proc embedding_create*(dim: cint): ptr CEmbedding {.importc, nodecl.}
proc embedding_free(embedding: ptr CEmbedding) {.importc, nodecl.}

proc model_session_create*(model: ptr CModel, device: ptr CDevice): ptr CModelSession {.importc, nodecl.}
proc model_session_free(session: ptr CModelSession) {.importc, nodecl.}

# Helper to convert Nim seq to C array
proc toCIntArray(s: seq[int]): ptr cint =
  if s.len == 0:
    return nil
  result = cast[ptr cint](alloc(s.len * sizeof(cint)))
  let arr = cast[ptr UncheckedArray[cint]](result)
  for i in 0..<s.len:
    arr[i] = s[i].cint

# Helper to convert string to DType
proc toDType(s: string): DType =
  case s:
    of "float32", "f32": DtFloat32
    of "float16", "f16": DtFloat16
    of "bfloat16", "bf16": DtBFloat16
    of "int8", "i8": DtInt8
    of "int16", "i16": DtInt16
    of "int32", "i32": DtInt32
    else: DtFloat32  # default

# Helper to convert string to DeviceKind
proc toDeviceKind(s: string): DeviceKind =
  case s:
    of "cpu": DevCPU
    of "cuda", "gpu": DevCUDA
    of "metal": DevMetal
    of "tpu": DevTPU
    else: DevCPU  # default

# Nim wrapper functions that return Gene Values
proc gene_tensor_create*(shape: seq[int], dtype: string = "float32", device: string = "cpu"): Value =
  let shape_ptr = toCIntArray(shape)
  let tensor_ptr = tensor_create(shape_ptr, shape.len.cint, dtype.cstring, device.cstring)
  dealloc(shape_ptr)
  
  if tensor_ptr.isNil:
    return NIL
  
  # Create Gene Tensor value
  let r = new_ref(VkTensor)
  r.tensor = new(TensorData)
  r.tensor.shape = shape
  r.tensor.dtype = toDType(dtype)
  r.tensor.device = toDeviceKind(device)
  r.tensor.device_id = 0
  r.tensor.data_ptr = cast[pointer](tensor_ptr)
  result = r.to_ref_value()

proc gene_tensor_random*(shape: seq[int]): Value =
  let shape_ptr = toCIntArray(shape)
  let tensor_ptr = tensor_random(shape_ptr, shape.len.cint)
  dealloc(shape_ptr)
  
  if tensor_ptr.isNil:
    return NIL
  
  let r = new_ref(VkTensor)
  r.tensor = new(TensorData)
  r.tensor.shape = shape
  r.tensor.dtype = DtFloat32
  r.tensor.device = DevCPU
  r.tensor.device_id = 0
  r.tensor.data_ptr = cast[pointer](tensor_ptr)
  result = r.to_ref_value()

proc gene_tensor_zeros*(shape: seq[int]): Value =
  let shape_ptr = toCIntArray(shape)
  let tensor_ptr = tensor_zeros(shape_ptr, shape.len.cint)
  dealloc(shape_ptr)
  
  if tensor_ptr.isNil:
    return NIL
  
  let r = new_ref(VkTensor)
  r.tensor = new(TensorData)
  r.tensor.shape = shape
  r.tensor.dtype = DtFloat32
  r.tensor.device = DevCPU
  r.tensor.device_id = 0
  r.tensor.data_ptr = cast[pointer](tensor_ptr)
  result = r.to_ref_value()

proc gene_tensor_add*(a, b: Value): Value =
  if a.kind != VkTensor or b.kind != VkTensor:
    return NIL
  
  let a_ptr = cast[ptr CGeneTensor](a.ref.tensor.data_ptr)
  let b_ptr = cast[ptr CGeneTensor](b.ref.tensor.data_ptr)
  let result_ptr = tensor_add(a_ptr, b_ptr)
  
  if result_ptr.isNil:
    return NIL
  
  let r = new_ref(VkTensor)
  r.tensor = new(TensorData)
  r.tensor.shape = a.ref.tensor.shape
  r.tensor.dtype = a.ref.tensor.dtype
  r.tensor.device = a.ref.tensor.device
  r.tensor.device_id = a.ref.tensor.device_id
  r.tensor.data_ptr = cast[pointer](result_ptr)
  result = r.to_ref_value()

proc gene_tensor_matmul*(a, b: Value): Value =
  if a.kind != VkTensor or b.kind != VkTensor:
    return NIL
  
  let a_ptr = cast[ptr CGeneTensor](a.ref.tensor.data_ptr)
  let b_ptr = cast[ptr CGeneTensor](b.ref.tensor.data_ptr)
  let result_ptr = tensor_matmul(a_ptr, b_ptr)
  
  if result_ptr.isNil:
    return NIL
  
  # Calculate result shape
  var result_shape: seq[int]
  if a.ref.tensor.shape.len == 2 and b.ref.tensor.shape.len == 2:
    result_shape = @[a.ref.tensor.shape[0], b.ref.tensor.shape[1]]
  else:
    result_shape = a.ref.tensor.shape  # Fallback
  
  let r = new_ref(VkTensor)
  r.tensor = new(TensorData)
  r.tensor.shape = result_shape
  r.tensor.dtype = a.ref.tensor.dtype
  r.tensor.device = a.ref.tensor.device
  r.tensor.device_id = a.ref.tensor.device_id
  r.tensor.data_ptr = cast[pointer](result_ptr)
  result = r.to_ref_value()

proc gene_tensor_transpose*(tensor: Value): Value =
  if tensor.kind != VkTensor:
    return NIL
  
  let tensor_ptr = cast[ptr CGeneTensor](tensor.ref.tensor.data_ptr)
  let result_ptr = tensor_transpose(tensor_ptr)
  
  if result_ptr.isNil:
    return NIL
  
  # Calculate transposed shape
  var result_shape = tensor.ref.tensor.shape
  if result_shape.len == 2:
    swap(result_shape[0], result_shape[1])
  
  let r = new_ref(VkTensor)
  r.tensor = new(TensorData)
  r.tensor.shape = result_shape
  r.tensor.dtype = tensor.ref.tensor.dtype
  r.tensor.device = tensor.ref.tensor.device
  r.tensor.device_id = tensor.ref.tensor.device_id
  r.tensor.data_ptr = cast[pointer](result_ptr)
  result = r.to_ref_value()

proc gene_tokenizer_create*(vocab_size: int): Value =
  let tokenizer_ptr = tokenizer_create(vocab_size.cint)
  
  if tokenizer_ptr.isNil:
    return NIL
  
  let r = new_ref(VkTokenizer)
  r.tokenizer = new(TokenizerData)
  r.tokenizer.vocab_size = vocab_size
  r.tokenizer.vocab = initTable[string, int]()
  r.tokenizer.special_tokens = initTable[string, int]()
  result = r.to_ref_value()

proc gene_model_create*(name: string, modelType: string): Value =
  let model_ptr = model_create(name.cstring, modelType.cstring)
  
  if model_ptr.isNil:
    return NIL
  
  let r = new_ref(VkModel)
  r.model = new(ModelData)
  r.model.name = name
  r.model.format = modelType
  r.model.weights = cast[pointer](model_ptr)
  r.model.size = 0
  r.model.metadata = initTable[string, Value]()
  result = r.to_ref_value()

proc gene_device_create*(deviceType: string): Value =
  let device_ptr = device_create(deviceType.cstring)
  
  if device_ptr.isNil:
    # For now, create a mock device
    let r = new_ref(VkDevice)
    r.device = new(DeviceInfo)
    r.device.kind = toDeviceKind(deviceType)
    r.device.id = 0
    r.device.name = deviceType & ":0"
    r.device.memory_total = 0
    r.device.memory_available = 0
    return r.to_ref_value()
  
  let r = new_ref(VkDevice)
  r.device = new(DeviceInfo)
  r.device.kind = toDeviceKind(deviceType)
  r.device.id = 0
  r.device.name = deviceType & ":0"
  r.device.memory_total = 0
  r.device.memory_available = 0
  result = r.to_ref_value()

proc gene_embedding_create*(dim: int): Value =
  let embedding_ptr = embedding_create(dim.cint)
  
  if embedding_ptr.isNil:
    return NIL
  
  let r = new_ref(VkEmbedding)
  r.embedding = new(EmbeddingData)
  r.embedding.dim = dim
  # Create empty tensor for vectors
  r.embedding.vectors = new(TensorData)
  r.embedding.vectors.shape = @[0, dim]
  r.embedding.vectors.dtype = DtFloat32
  r.embedding.vectors.device = DevCPU
  r.embedding.vectors.device_id = 0
  r.embedding.vectors.data_ptr = cast[pointer](embedding_ptr)
  result = r.to_ref_value()

proc gene_model_session_create*(model: Value, device: Value): Value =
  if model.kind != VkModel or device.kind != VkDevice:
    return NIL
  
  let model_ptr = cast[ptr CModel](model.ref.model.weights)
  let device_ptr = cast[ptr CDevice](device.ref.device)  # DeviceInfo is already a ref object
  let session_ptr = model_session_create(model_ptr, device_ptr)
  
  if session_ptr.isNil:
    return NIL
  
  let r = new_ref(VkModelSession)
  r.session = new(ModelSession)
  r.session.model = model
  r.session.state = initTable[string, Value]()
  r.session.device = device.ref.device
  result = r.to_ref_value()

# Cleanup functions
proc gene_tensor_free*(tensor: Value) =
  if tensor.kind == VkTensor and not tensor.ref.tensor.data_ptr.isNil:
    tensor_free(cast[ptr CGeneTensor](tensor.ref.tensor.data_ptr))
    tensor.ref.tensor.data_ptr = nil

proc gene_tokenizer_free*(tokenizer: Value) =
  if tokenizer.kind == VkTokenizer:
    # TokenizerData doesn't have data_ptr, just clear the vocab
    tokenizer.ref.tokenizer.vocab.clear()
    tokenizer.ref.tokenizer.special_tokens.clear()

proc gene_model_free*(model: Value) =
  if model.kind == VkModel and not model.ref.model.weights.isNil:
    model_free(cast[ptr CModel](model.ref.model.weights))
    model.ref.model.weights = nil

proc gene_device_free*(device: Value) =
  if device.kind == VkDevice:
    # DeviceInfo doesn't have data_ptr, it's a simple ref object
    discard

proc gene_embedding_free*(embedding: Value) =
  if embedding.kind == VkEmbedding and not embedding.ref.embedding.vectors.data_ptr.isNil:
    embedding_free(cast[ptr CEmbedding](embedding.ref.embedding.vectors.data_ptr))
    embedding.ref.embedding.vectors.data_ptr = nil

proc gene_model_session_free*(session: Value) =
  if session.kind == VkModelSession:
    # ModelSession doesn't have data_ptr, just clear state
    session.ref.session.state.clear()