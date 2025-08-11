## Core AI Native Functions for Gene
## These are generic and work with any AI provider

import ../types
import ./ai_interface
import std/tables

# Native function to list available providers
proc native_ai_providers(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  let providers = list_ai_providers()
  let arr = new_ref(VkArray)
  for provider in providers:
    arr.arr.add(provider.to_value)
  return arr.to_ref_value()

# Native function to load a model
proc native_ai_load_model(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene or args.gene.children.len < 2:
    return NIL
  
  let provider_name = args.gene.children[0].str
  let model_path = args.gene.children[1].str
  
  var config = initTable[string, Value]()
  if args.gene.children.len > 2 and args.gene.children[2].kind == VkMap:
    # Copy config from Gene map
    for key, val in args.gene.children[2].ref.map:
      config[$key.int64] = val  # Convert key to string via int64
  
  try:
    let provider = get_ai_provider(provider_name)
    let model = provider.load_model(model_path, config)
    
    # Return model as Gene value
    let r = new_ref(VkMap)
    r.map["provider".to_key()] = provider_name.to_value
    r.map["name".to_key()] = model.name.to_value
    r.map["model_ptr".to_key()] = cast[int](model).to_value
    return r.to_ref_value()
  except:
    return NIL

# Native function to generate text
proc native_ai_generate(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene or args.gene.children.len < 2:
    return NIL
  
  let model_val = args.gene.children[0]
  if model_val.kind != VkMap:
    return NIL
    
  let prompt = args.gene.children[1].str
  
  # Extract model info
  let model_map = model_val.ref.map
  if "provider".to_key() notin model_map or "model_ptr".to_key() notin model_map:
    return NIL
    
  let provider_name = model_map["provider".to_key()].str
  let model_ptr = model_map["model_ptr".to_key()].to_int
  let model = cast[AIModel](model_ptr)
  
  # Build request
  var request = CompletionRequest(
    prompt: prompt,
    max_tokens: 100,
    temperature: 0.7,
    top_p: 1.0,
    stop_sequences: @[]
  )
  
  # Override with options if provided
  if args.gene.children.len > 2 and args.gene.children[2].kind == VkMap:
    let opts = args.gene.children[2].ref.map
    if "max_tokens".to_key() in opts:
      request.max_tokens = opts["max_tokens".to_key()].to_int
    if "temperature".to_key() in opts:
      request.temperature = opts["temperature".to_key()].to_float
    if "top_p".to_key() in opts:
      request.top_p = opts["top_p".to_key()].to_float
  
  try:
    let provider = get_ai_provider(provider_name)
    let response = provider.generate(model, request)
    return response.to_value()
  except:
    return NIL

# Native function to get embeddings
proc native_ai_embeddings(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene or args.gene.children.len < 2:
    return NIL
  
  let model_val = args.gene.children[0]
  let text = args.gene.children[1].str
  
  if model_val.kind != VkMap:
    return NIL
    
  let model_map = model_val.ref.map
  if "provider".to_key() notin model_map or "model_ptr".to_key() notin model_map:
    return NIL
    
  let provider_name = model_map["provider".to_key()].str
  let model_ptr = model_map["model_ptr".to_key()].to_int
  let model = cast[AIModel](model_ptr)
  
  let request = EmbeddingRequest(
    text: text,
    model: model.name
  )
  
  try:
    let provider = get_ai_provider(provider_name)
    let response = provider.get_embeddings(model, request)
    return response.to_value()
  except:
    return NIL

# Native function to tokenize text
proc native_ai_tokenize(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  if args.kind != VkGene or args.gene.children.len < 2:
    return NIL
  
  let model_val = args.gene.children[0]
  let text = args.gene.children[1].str
  
  if model_val.kind != VkMap:
    return NIL
    
  let model_map = model_val.ref.map
  if "provider".to_key() notin model_map or "model_ptr".to_key() notin model_map:
    return NIL
    
  let provider_name = model_map["provider".to_key()].str
  let model_ptr = model_map["model_ptr".to_key()].to_int
  let model = cast[AIModel](model_ptr)
  
  try:
    let provider = get_ai_provider(provider_name)
    let tokens = provider.tokenize(model, text)
    
    let arr = new_ref(VkArray)
    for token in tokens:
      arr.arr.add(token.to_value)
    return arr.to_ref_value()
  except:
    return NIL

# Register the core AI natives
proc register_ai_core_natives*(vm: VirtualMachine) =
  ## Register generic AI functions
  let global_ns = App.app.global_ns.ref.ns
  
  # Create ai namespace
  let ai_ns = new_namespace("ai")
  
  # Helper to create native function
  proc new_native_fn(name: string, fn: NativeFn): Value =
    let r = new_ref(VkNativeFn)
    r.native_fn = fn
    return r.to_ref_value()
  
  # Register generic functions
  ai_ns.members["providers".to_key()] = new_native_fn("ai/providers", native_ai_providers)
  ai_ns.members["load-model".to_key()] = new_native_fn("ai/load-model", native_ai_load_model)
  ai_ns.members["generate".to_key()] = new_native_fn("ai/generate", native_ai_generate)
  ai_ns.members["embeddings".to_key()] = new_native_fn("ai/embeddings", native_ai_embeddings)
  ai_ns.members["tokenize".to_key()] = new_native_fn("ai/tokenize", native_ai_tokenize)
  
  global_ns.members["ai".to_key()] = ai_ns.to_value()