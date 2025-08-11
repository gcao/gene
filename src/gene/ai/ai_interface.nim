## Generic AI Interface for Gene
## Provides abstract interface that can be implemented by different AI providers

import ../types
import std/tables

type
  # Generic AI model interface
  AIModel* = ref object of RootObj
    name*: string
    provider*: string
    metadata*: Table[string, Value]
  
  # Generic completion request
  CompletionRequest* = object
    prompt*: string
    max_tokens*: int
    temperature*: float
    top_p*: float
    stop_sequences*: seq[string]
    
  # Generic completion response  
  CompletionResponse* = object
    text*: string
    tokens_used*: int
    tokens_generated*: int
    finish_reason*: string
    
  # Generic embedding request
  EmbeddingRequest* = object
    text*: string
    model*: string
    
  # Generic embedding response
  EmbeddingResponse* = object
    embeddings*: seq[float]
    dimensions*: int
    tokens_used*: int

  # AI Provider interface - must be implemented by extensions
  AIProvider* = ref object of RootObj
    name*: string
    version*: string
    capabilities*: set[AICapability]
    
  AICapability* = enum
    AcTextGeneration
    AcEmbeddings
    AcTokenization
    AcFineTuning
    AcStreaming

# Virtual methods for AI providers (to be overridden)
method load_model*(provider: AIProvider, path: string, config: Table[string, Value]): AIModel {.base, gcsafe.} =
  raise newException(CatchableError, "load_model not implemented")

method generate*(provider: AIProvider, model: AIModel, request: CompletionRequest): CompletionResponse {.base, gcsafe.} =
  raise newException(CatchableError, "generate not implemented")

method get_embeddings*(provider: AIProvider, model: AIModel, request: EmbeddingRequest): EmbeddingResponse {.base, gcsafe.} =
  raise newException(CatchableError, "get_embeddings not implemented")

method tokenize*(provider: AIProvider, model: AIModel, text: string): seq[int] {.base, gcsafe.} =
  raise newException(CatchableError, "tokenize not implemented")

method free_model*(provider: AIProvider, model: AIModel) {.base, gcsafe.} =
  # Default implementation - can be overridden
  discard

# Global registry of AI providers
var ai_providers* {.global.}: Table[string, AIProvider]

proc register_ai_provider*(name: string, provider: AIProvider) {.gcsafe.} =
  ## Register an AI provider
  {.gcsafe.}:
    ai_providers[name] = provider
    provider.name = name

proc get_ai_provider*(name: string): AIProvider {.gcsafe.} =
  ## Get a registered AI provider
  {.gcsafe.}:
    if name in ai_providers:
      return ai_providers[name]
    else:
      raise newException(ValueError, "AI provider not found: " & name)

proc list_ai_providers*(): seq[string] {.gcsafe.} =
  ## List all registered AI providers
  {.gcsafe.}:
    result = @[]
    for key in ai_providers.keys:
      result.add(key)

# Helper to convert Gene values to/from generic types
proc to_completion_request*(value: Value): CompletionRequest =
  ## Convert Gene map to CompletionRequest
  if value.kind != VkMap:
    raise newException(ValueError, "Expected map for completion request")
    
  result.prompt = ""
  result.max_tokens = 100
  result.temperature = 0.7
  result.top_p = 1.0
  result.stop_sequences = @[]
  
  let map = value.ref.map
  if "prompt".to_key() in map:
    result.prompt = map["prompt".to_key()].str
  if "max_tokens".to_key() in map:
    result.max_tokens = map["max_tokens".to_key()].to_int
  if "temperature".to_key() in map:
    result.temperature = map["temperature".to_key()].to_float
  if "top_p".to_key() in map:
    result.top_p = map["top_p".to_key()].to_float
  if "stop".to_key() in map:
    let stops = map["stop".to_key()]
    if stops.kind == VkArray:
      for item in stops.ref.arr:
        result.stop_sequences.add(item.str)

proc to_value*(response: CompletionResponse): Value =
  ## Convert CompletionResponse to Gene map
  let r = new_ref(VkMap)
  r.map["text".to_key()] = response.text.to_value
  r.map["tokens_used".to_key()] = response.tokens_used.to_value
  r.map["tokens_generated".to_key()] = response.tokens_generated.to_value
  r.map["finish_reason".to_key()] = response.finish_reason.to_value
  return r.to_ref_value()

proc to_value*(response: EmbeddingResponse): Value =
  ## Convert EmbeddingResponse to Gene map
  let r = new_ref(VkMap)
  
  let embeds = new_ref(VkArray)
  for val in response.embeddings:
    embeds.arr.add(val.to_value)
  
  r.map["embeddings".to_key()] = embeds.to_ref_value()
  r.map["dimensions".to_key()] = response.dimensions.to_value
  r.map["tokens_used".to_key()] = response.tokens_used.to_value
  return r.to_ref_value()