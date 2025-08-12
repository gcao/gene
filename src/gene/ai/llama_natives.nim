## Native LLaMA.cpp integration for Gene
## Provides direct access to llama.cpp from Gene code

import ../types
import ../vm
import std/[tables, os]

# Compile the C wrapper
const llama_wrapper_c = currentSourcePath.parentDir() / "llama_wrapper.c"
const llama_wrapper_h = currentSourcePath.parentDir() / "llama_wrapper.h"
{.compile: llama_wrapper_c.}

# Link to complete llama.cpp static library
{.passL: "external/llama.cpp/libllama_complete.a".}
{.passL: "-lc++ -framework Accelerate -framework Foundation -framework Metal -framework MetalKit".}
{.passC: "-Iexternal/llama.cpp/include -Iexternal/llama.cpp/ggml/include".}

# C functions - import from header
proc llama_wrapper_init(): cint {.importc, header: llama_wrapper_h.}
proc llama_wrapper_load_model(path: cstring): pointer {.importc, header: llama_wrapper_h.}
proc llama_wrapper_create_context(model: pointer): pointer {.importc, header: llama_wrapper_h.}
proc llama_wrapper_generate(ctx: pointer, prompt: cstring, max_tokens: cint): cstring {.importc, header: llama_wrapper_h.}
proc llama_wrapper_free_context(ctx: pointer) {.importc, header: llama_wrapper_h.}
proc llama_wrapper_free_model(model: pointer) {.importc, header: llama_wrapper_h.}
proc llama_wrapper_cleanup() {.importc, header: llama_wrapper_h.}

# Global state
var 
  initialized = false
  current_model: pointer = nil
  current_context: pointer = nil

# Initialize on first use
proc ensure_initialized() =
  if not initialized:
    let res = llama_wrapper_init()
    initialized = res == 0
    if not initialized:
      raise new_exception(types.Exception, "Failed to initialize llama.cpp")

# Native function: Load model
proc native_llama_load*(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene or args.gene.children.len < 1:
    return NIL
  
  ensure_initialized()
  
  let model_path = args.gene.children[0].str
  
  # Check if file exists
  if not fileExists(model_path):
    let r = new_ref(VkMap)
    r.map["status".to_key()] = "error".to_value
    r.map["message".to_key()] = ("Model file not found: " & model_path).to_value
    return r.to_ref_value()
  
  # Free previous model if exists
  if current_context != nil:
    llama_wrapper_free_context(current_context)
    current_context = nil
  
  if current_model != nil:
    llama_wrapper_free_model(current_model)
    current_model = nil
  
  # Load new model
  current_model = llama_wrapper_load_model(model_path.cstring)
  if current_model == nil:
    let r = new_ref(VkMap)
    r.map["status".to_key()] = "error".to_value
    r.map["message".to_key()] = ("Failed to load model: " & model_path).to_value
    return r.to_ref_value()
  
  # Create context
  current_context = llama_wrapper_create_context(current_model)
  if current_context == nil:
    llama_wrapper_free_model(current_model)
    current_model = nil
    let r = new_ref(VkMap)
    r.map["status".to_key()] = "error".to_value
    r.map["message".to_key()] = "Failed to create context for model".to_value
    return r.to_ref_value()
  
  # Return success
  let r = new_ref(VkMap)
  r.map["status".to_key()] = "loaded".to_value
  r.map["path".to_key()] = model_path.to_value
  r.map["ready".to_key()] = TRUE
  return r.to_ref_value()

# Native function: Generate text
proc native_llama_generate*(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene or args.gene.children.len < 1:
    return NIL
  
  if current_context == nil:
    let r = new_ref(VkMap)
    r.map["status".to_key()] = "error".to_value
    r.map["message".to_key()] = "No model loaded. Call llama/load first.".to_value
    return r.to_ref_value()
  
  let prompt = args.gene.children[0].str
  var max_tokens = 50
  
  if args.gene.children.len > 1:
    max_tokens = args.gene.children[1].to_int
  
  # Generate text
  let generated = llama_wrapper_generate(current_context, prompt.cstring, max_tokens.cint)
  if generated == nil:
    let r = new_ref(VkMap)
    r.map["status".to_key()] = "error".to_value
    r.map["message".to_key()] = "Generation failed".to_value
    return r.to_ref_value()
  
  let result = $generated
  # Note: In production, should free the C string if needed
  return result.to_value

# Native function: Get info
proc native_llama_info*(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  let r = new_ref(VkMap)
  r.map["initialized".to_key()] = initialized.to_value
  r.map["model_loaded".to_key()] = (current_model != nil).to_value
  r.map["context_ready".to_key()] = (current_context != nil).to_value
  r.map["backend".to_key()] = "llama.cpp".to_value
  return r.to_ref_value()

# Native function: Unload model
proc native_llama_unload*(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if current_context != nil:
    llama_wrapper_free_context(current_context)
    current_context = nil
  
  if current_model != nil:
    llama_wrapper_free_model(current_model)
    current_model = nil
  
  return TRUE

# Helper to create native function value
proc new_native_fn(name: string, fn: NativeFn): Value =
  let r = new_ref(VkNativeFn)
  r.native_fn = fn
  result = r.to_ref_value()

# Register llama natives
proc register_llama_natives*(vm: VirtualMachine) =
  # Get the global namespace
  let global_ns = App.app.global_ns.ref.ns
  
  # Create or get genex namespace
  var genex_ns: Namespace
  let genex_key = "genex".to_key()
  if global_ns.members.has_key(genex_key):
    genex_ns = global_ns.members[genex_key].ref.ns
  else:
    genex_ns = new_namespace("genex")
    global_ns.members[genex_key] = genex_ns.to_value()
  
  # Create llamacpp namespace
  let llamacpp_ns = new_namespace("llamacpp")
  
  # Register functions
  llamacpp_ns.members["load".to_key()] = new_native_fn("genex/llamacpp/load", native_llama_load)
  llamacpp_ns.members["generate".to_key()] = new_native_fn("genex/llamacpp/generate", native_llama_generate)
  llamacpp_ns.members["info".to_key()] = new_native_fn("genex/llamacpp/info", native_llama_info)
  llamacpp_ns.members["unload".to_key()] = new_native_fn("genex/llamacpp/unload", native_llama_unload)
  
  # Add to genex namespace
  genex_ns.members["llamacpp".to_key()] = llamacpp_ns.to_value()

# Cleanup on exit
proc cleanup_llama_at_exit() {.noconv.} =
  if current_context != nil:
    llama_wrapper_free_context(current_context)
    current_context = nil
  
  if current_model != nil:
    llama_wrapper_free_model(current_model)
    current_model = nil
  
  if initialized:
    llama_wrapper_cleanup()
    initialized = false

# Register cleanup
import std/exitprocs
addExitProc(cleanup_llama_at_exit)