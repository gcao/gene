## AI/ML Bindings for Gene
## Provides FFI bindings to the C implementation

import ../types
import ../vm
import std/[dynlib, os]

{.compile: "gene_ai.c".}

type
  CGeneTensor {.importc: "GeneTensor", header: "gene_ai.c".} = object
    data: ptr cfloat
    shape: ptr cint
    ndim: cint
    size: cint
    device: cstring

  CTokenizer {.importc: "GeneTokenizer", header: "gene_ai.c".} = object
    vocab_size: cint
    vocab: ptr cstring

  CModel {.importc: "GeneModel", header: "gene_ai.c".} = object
    name: cstring
    modelType: cstring {.importc: "type".}
    weights: pointer
    num_params: cint

  CDevice {.importc: "GeneDevice", header: "gene_ai.c".} = object
    deviceType: cstring {.importc: "type".}
    id: cint

  CEmbedding {.importc: "GeneEmbedding", header: "gene_ai.c".} = object
    dim: cint
    weights: ptr CGeneTensor

  CModelSession {.importc: "GeneModelSession", header: "gene_ai.c".} = object
    model: ptr CModel
    device: ptr CDevice

# C function declarations
proc tensor_create(shape: ptr cint, ndim: cint, dtype: cstring, device: cstring): ptr CGeneTensor {.importc, cdecl.}
proc tensor_random(shape: ptr cint, ndim: cint): ptr CGeneTensor {.importc, cdecl.}
proc tensor_zeros(shape: ptr cint, ndim: cint): ptr CGeneTensor {.importc, cdecl.}
proc tensor_add(a, b: ptr CGeneTensor): ptr CGeneTensor {.importc, cdecl.}
proc tensor_matmul(a, b: ptr CGeneTensor): ptr CGeneTensor {.importc, cdecl.}
proc tensor_transpose(tensor: ptr CGeneTensor): ptr CGeneTensor {.importc, cdecl.}
proc tensor_free(tensor: ptr CGeneTensor) {.importc, cdecl.}
proc tensor_ndim(tensor: ptr CGeneTensor): cint {.importc, cdecl.}
proc tensor_shape(tensor: ptr CGeneTensor): ptr cint {.importc, cdecl.}
proc tensor_data(tensor: ptr CGeneTensor): ptr cfloat {.importc, cdecl.}
proc tensor_size(tensor: ptr CGeneTensor): cint {.importc, cdecl.}

proc tokenizer_create(vocab_size: cint): ptr CTokenizer {.importc, cdecl.}
proc tokenizer_free(tokenizer: ptr CTokenizer) {.importc, cdecl.}

proc model_create(name: cstring, modelType: cstring): ptr CModel {.importc, cdecl.}
proc model_free(model: ptr CModel) {.importc, cdecl.}

proc device_create(deviceType: cstring): ptr CDevice {.importc, cdecl.}
proc device_free(device: ptr CDevice) {.importc, cdecl.}

proc embedding_create(dim: cint): ptr CEmbedding {.importc, cdecl.}
proc embedding_free(embedding: ptr CEmbedding) {.importc, cdecl.}

proc model_session_create(model: ptr CModel, device: ptr CDevice): ptr CModelSession {.importc, cdecl.}
proc model_session_free(session: ptr CModelSession) {.importc, cdecl.}

# Helper to convert Nim seq to C array
proc toCIntArray(s: seq[int]): ptr cint =
  if s.len == 0:
    return nil
  result = cast[ptr cint](alloc(s.len * sizeof(cint)))
  for i in 0..<s.len:
    result[i] = s[i].cint

# Nim wrapper functions that return Gene Values
proc gene_tensor_create*(shape: seq[int], dtype: string = "float32", device: string = "cpu"): Value =
  let shape_ptr = toCIntArray(shape)
  let tensor_ptr = tensor_create(shape_ptr, shape.len.cint, dtype.cstring, device.cstring)
  dealloc(shape_ptr)
  
  if tensor_ptr.isNil:
    return NIL
  
  # Create Gene Tensor value
  result = new_ref(VkTensor)
  result.ref.tensor = new(Tensor)
  result.ref.tensor.shape = shape
  result.ref.tensor.dtype = dtype
  result.ref.tensor.device = device
  result.ref.tensor.data_ptr = cast[pointer](tensor_ptr)

proc gene_tensor_random*(shape: seq[int]): Value =
  let shape_ptr = toCIntArray(shape)
  let tensor_ptr = tensor_random(shape_ptr, shape.len.cint)
  dealloc(shape_ptr)
  
  if tensor_ptr.isNil:
    return NIL
  
  result = new_ref(VkTensor)
  result.ref.tensor = new(Tensor)
  result.ref.tensor.shape = shape
  result.ref.tensor.dtype = "float32"
  result.ref.tensor.device = "cpu"
  result.ref.tensor.data_ptr = cast[pointer](tensor_ptr)

proc gene_tensor_zeros*(shape: seq[int]): Value =
  let shape_ptr = toCIntArray(shape)
  let tensor_ptr = tensor_zeros(shape_ptr, shape.len.cint)
  dealloc(shape_ptr)
  
  if tensor_ptr.isNil:
    return NIL
  
  result = new_ref(VkTensor)
  result.ref.tensor = new(Tensor)
  result.ref.tensor.shape = shape
  result.ref.tensor.dtype = "float32"
  result.ref.tensor.device = "cpu"
  result.ref.tensor.data_ptr = cast[pointer](tensor_ptr)

proc gene_tensor_add*(a, b: Value): Value =
  if a.kind != VkTensor or b.kind != VkTensor:
    return NIL
  
  let a_ptr = cast[ptr CGeneTensor](a.ref.tensor.data_ptr)
  let b_ptr = cast[ptr CGeneTensor](b.ref.tensor.data_ptr)
  let result_ptr = tensor_add(a_ptr, b_ptr)
  
  if result_ptr.isNil:
    return NIL
  
  result = new_ref(VkTensor)
  result.ref.tensor = new(Tensor)
  result.ref.tensor.shape = a.ref.tensor.shape
  result.ref.tensor.dtype = a.ref.tensor.dtype
  result.ref.tensor.device = a.ref.tensor.device
  result.ref.tensor.data_ptr = cast[pointer](result_ptr)

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
  
  result = new_ref(VkTensor)
  result.ref.tensor = new(Tensor)
  result.ref.tensor.shape = result_shape
  result.ref.tensor.dtype = a.ref.tensor.dtype
  result.ref.tensor.device = a.ref.tensor.device
  result.ref.tensor.data_ptr = cast[pointer](result_ptr)

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
  
  result = new_ref(VkTensor)
  result.ref.tensor = new(Tensor)
  result.ref.tensor.shape = result_shape
  result.ref.tensor.dtype = tensor.ref.tensor.dtype
  result.ref.tensor.device = tensor.ref.tensor.device
  result.ref.tensor.data_ptr = cast[pointer](result_ptr)

proc gene_tokenizer_create*(vocab_size: int): Value =
  let tokenizer_ptr = tokenizer_create(vocab_size.cint)
  
  if tokenizer_ptr.isNil:
    return NIL
  
  result = new_ref(VkTokenizer)
  result.ref.tokenizer = new(Tokenizer)
  result.ref.tokenizer.vocab_size = vocab_size
  result.ref.tokenizer.data_ptr = cast[pointer](tokenizer_ptr)

proc gene_model_create*(name: string, modelType: string): Value =
  let model_ptr = model_create(name.cstring, modelType.cstring)
  
  if model_ptr.isNil:
    return NIL
  
  result = new_ref(VkModel)
  result.ref.model = new(Model)
  result.ref.model.name = name
  result.ref.model.model_type = modelType
  result.ref.model.data_ptr = cast[pointer](model_ptr)

proc gene_device_create*(deviceType: string): Value =
  let device_ptr = device_create(deviceType.cstring)
  
  if device_ptr.isNil:
    return NIL
  
  result = new_ref(VkDevice)
  result.ref.device = new(Device)
  result.ref.device.device_type = deviceType
  result.ref.device.data_ptr = cast[pointer](device_ptr)

proc gene_embedding_create*(dim: int): Value =
  let embedding_ptr = embedding_create(dim.cint)
  
  if embedding_ptr.isNil:
    return NIL
  
  result = new_ref(VkEmbedding)
  result.ref.embedding = new(Embedding)
  result.ref.embedding.dim = dim
  result.ref.embedding.data_ptr = cast[pointer](embedding_ptr)

proc gene_model_session_create*(model: Value, device: Value): Value =
  if model.kind != VkModel or device.kind != VkDevice:
    return NIL
  
  let model_ptr = cast[ptr CModel](model.ref.model.data_ptr)
  let device_ptr = cast[ptr CDevice](device.ref.device.data_ptr)
  let session_ptr = model_session_create(model_ptr, device_ptr)
  
  if session_ptr.isNil:
    return NIL
  
  result = new_ref(VkModelSession)
  result.ref.model_session = new(ModelSession)
  result.ref.model_session.data_ptr = cast[pointer](session_ptr)

# Cleanup functions
proc gene_tensor_free*(tensor: Value) =
  if tensor.kind == VkTensor and not tensor.ref.tensor.data_ptr.isNil:
    tensor_free(cast[ptr CGeneTensor](tensor.ref.tensor.data_ptr))
    tensor.ref.tensor.data_ptr = nil

proc gene_tokenizer_free*(tokenizer: Value) =
  if tokenizer.kind == VkTokenizer and not tokenizer.ref.tokenizer.data_ptr.isNil:
    tokenizer_free(cast[ptr CTokenizer](tokenizer.ref.tokenizer.data_ptr))
    tokenizer.ref.tokenizer.data_ptr = nil

proc gene_model_free*(model: Value) =
  if model.kind == VkModel and not model.ref.model.data_ptr.isNil:
    model_free(cast[ptr CModel](model.ref.model.data_ptr))
    model.ref.model.data_ptr = nil

proc gene_device_free*(device: Value) =
  if device.kind == VkDevice and not device.ref.device.data_ptr.isNil:
    device_free(cast[ptr CDevice](device.ref.device.data_ptr))
    device.ref.device.data_ptr = nil

proc gene_embedding_free*(embedding: Value) =
  if embedding.kind == VkEmbedding and not embedding.ref.embedding.data_ptr.isNil:
    embedding_free(cast[ptr CEmbedding](embedding.ref.embedding.data_ptr))
    embedding.ref.embedding.data_ptr = nil

proc gene_model_session_free*(session: Value) =
  if session.kind == VkModelSession and not session.ref.model_session.data_ptr.isNil:
    model_session_free(cast[ptr CModelSession](session.ref.model_session.data_ptr))
    session.ref.model_session.data_ptr = nil