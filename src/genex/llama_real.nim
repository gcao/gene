## Real Llama.cpp Extension for Gene
## Uses actual llama.cpp for text generation

import std/[tables, os]
include ../gene/extension/boilerplate

# Compile the real llama wrapper
const llama_real_c = currentSourcePath.parentDir() / "llama/llama_real.c"
const llama_real_h = currentSourcePath.parentDir() / "llama/llama_real.h"
{.compile: llama_real_c.}

# Link to llama.cpp libraries
{.passL: "-Lexternal/llama.cpp/build/bin -lllama -lggml -lggml-base -lggml-cpu".}
{.passL: "-Wl,-rpath,external/llama.cpp/build/bin".}
{.passC: "-Iexternal/llama.cpp/include -Iexternal/llama.cpp/ggml/include".}

# C types
type
  RealLlamaModel {.importc, header: llama_real_h.} = object

# C functions
proc real_llama_init(): cint {.importc, nodecl.}
proc real_llama_load(path: cstring): ptr RealLlamaModel {.importc, nodecl.}
proc real_llama_generate(model: ptr RealLlamaModel, prompt: cstring, max_tokens: cint): cstring {.importc, nodecl.}
proc real_llama_tokenize(model: ptr RealLlamaModel, text: cstring, n_tokens: ptr cint): ptr cint {.importc, nodecl.}
proc real_llama_free(model: ptr RealLlamaModel) {.importc, nodecl.}
proc real_llama_cleanup() {.importc, nodecl.}
proc real_llama_info(model: ptr RealLlamaModel, buffer: cstring, size: cint) {.importc, nodecl.}

# Global state
var current_model: ptr RealLlamaModel = nil
var initialized = false

# Initialize on load
proc init_backend() =
  if not initialized:
    let res = real_llama_init()
    initialized = res == 0

# Gene native functions
proc llama_load(vm_param: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene or args.gene.children.len < 1:
    return NIL
  
  init_backend()
  
  let model_path = args.gene.children[0].str
  
  # Free previous model
  if current_model != nil:
    real_llama_free(current_model)
  
  # Load new model
  current_model = real_llama_load(model_path.cstring)
  
  if current_model == nil:
    # Return error info
    let r = new_ref(VkMap)
    r.map["status".to_key()] = "error".to_value
    r.map["path".to_key()] = model_path.to_value
    r.map["message".to_key()] = "Failed to load model (check path and format)".to_value
    return r.to_ref_value()
  
  # Get model info
  var buffer: array[512, char]
  real_llama_info(current_model, cast[cstring](addr buffer[0]), 512)
  
  # Return success info
  let r = new_ref(VkMap)
  r.map["status".to_key()] = "loaded".to_value
  r.map["path".to_key()] = model_path.to_value
  r.map["info".to_key()] = ($cast[cstring](addr buffer[0])).to_value
  return r.to_ref_value()

proc llama_generate(vm_param: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene or args.gene.children.len < 1:
    return NIL
  
  if current_model == nil:
    return "Error: No model loaded".to_value
  
  let prompt = args.gene.children[0].str
  var max_tokens = 50
  
  if args.gene.children.len > 1:
    max_tokens = args.gene.children[1].to_int
  
  let generated = real_llama_generate(current_model, prompt.cstring, max_tokens.cint)
  if generated == nil:
    return "Error: Generation failed".to_value
  
  let result = $generated
  # Note: In production, should free the C string
  return result.to_value

proc llama_tokenize(vm_param: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene or args.gene.children.len < 1:
    return NIL
  
  if current_model == nil:
    return NIL
  
  let text = args.gene.children[0].str
  var n_tokens: cint = 0
  let tokens_ptr = real_llama_tokenize(current_model, text.cstring, addr n_tokens)
  
  if tokens_ptr == nil:
    return NIL
  
  # Convert to Gene array
  let arr = new_ref(VkArray)
  let tokens_array = cast[ptr UncheckedArray[cint]](tokens_ptr)
  for i in 0..<n_tokens:
    arr.arr.add(tokens_array[i].int.to_value)
  
  # Note: In production, should free the tokens array
  return arr.to_ref_value()

proc llama_info(vm_param: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  let r = new_ref(VkMap)
  r.map["initialized".to_key()] = initialized.to_value
  r.map["model_loaded".to_key()] = (current_model != nil).to_value
  
  if current_model != nil:
    var buffer: array[512, char]
    real_llama_info(current_model, cast[cstring](addr buffer[0]), 512)
    r.map["model_info".to_key()] = ($cast[cstring](addr buffer[0])).to_value
  else:
    r.map["model_info".to_key()] = "No model loaded".to_value
  
  r.map["backend".to_key()] = "llama.cpp (real)".to_value
  r.map["version".to_key()] = "1.0".to_value
  return r.to_ref_value()

# Cleanup on unload
proc cleanup_at_exit() {.noconv.} =
  if current_model != nil:
    real_llama_free(current_model)
    current_model = nil
  if initialized:
    real_llama_cleanup()
    initialized = false

# Register cleanup
addQuitProc(cleanup_at_exit)

# Extension initialization
proc init*(vm: ptr VirtualMachine): Namespace {.dynlib, exportc.} =
  result = new_namespace("llama")
  
  # Initialize backend
  init_backend()
  
  # Register functions
  var fn = new_ref(VkNativeFn)
  fn.native_fn = llama_load
  result["load".to_key()] = fn.to_ref_value()
  
  fn = new_ref(VkNativeFn)
  fn.native_fn = llama_generate
  result["generate".to_key()] = fn.to_ref_value()
  
  fn = new_ref(VkNativeFn)
  fn.native_fn = llama_tokenize
  result["tokenize".to_key()] = fn.to_ref_value()
  
  fn = new_ref(VkNativeFn)
  fn.native_fn = llama_info
  result["info".to_key()] = fn.to_ref_value()