## AI/ML initialization module

import ./types
import ./vm

var ai_initialized = false

proc ensure_ai_initialized*() =
  if ai_initialized:
    return
  
  ai_initialized = true
  
  # Get the global namespace from App
  let global_ns = App.app.global_ns.ref.ns
  
  # Add stub namespaces - actual implementations will be loaded dynamically
  let tokenizer_ns = new_namespace("tokenizer")
  global_ns.members["tokenizer"] = tokenizer_ns.to_value()
  
  let embedding_ns = new_namespace("embedding")
  global_ns.members["embedding"] = embedding_ns.to_value()
  
  let model_ns = new_namespace("model")
  global_ns.members["model"] = model_ns.to_value()
  
  let device_ns = new_namespace("device")
  global_ns.members["device"] = device_ns.to_value()
  
  let tensor_ns = new_namespace("tensor")
  global_ns.members["tensor"] = tensor_ns.to_value()

# Register this to be called after VM creation
VmCreatedCallbacks.add(ensure_ai_initialized)