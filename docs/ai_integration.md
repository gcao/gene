# Gene AI/ML Integration

This document describes the AI/ML capabilities integrated into the Gene programming language.

## Overview

Gene now includes native support for AI/ML operations through integrated namespaces that provide tensor operations, model management, and tokenization capabilities. These features enable Gene to be used for machine learning tasks, neural network implementation, and LLM inference.

## Namespaces

### `tokenizer` Namespace
Provides text tokenization for NLP tasks.

- `tokenizer/create vocab_size` - Creates a tokenizer with specified vocabulary size
  ```gene
  (var tok (tokenizer/create 50000))
  ```

### `tensor` Namespace  
Core tensor operations for numerical computing.

- `tensor/create shape dtype` - Create a tensor with specified shape and data type
- `tensor/zeros shape` - Create a zero-initialized tensor
- `tensor/random shape` - Create a tensor with random values
- `tensor/add a b` - Element-wise addition
- `tensor/matmul a b` - Matrix multiplication
- `tensor/transpose t` - Transpose a tensor
- `tensor/shape t` - Get tensor dimensions
- `tensor/reshape t new_shape` - Reshape tensor

Example:
```gene
(var weights (tensor/random [784 128]))
(var bias (tensor/zeros [128]))
(var output (tensor/add (tensor/matmul input weights) bias))
```

### `model` Namespace
Model creation and management.

- `model/create name type` - Create a model instance
- `model/session model device` - Create inference session

Example:
```gene
(var mdl (model/create "gene_bert" "transformer"))
```

### `device` Namespace
Device management for computation.

- `device/create type` - Create a device (cpu, cuda, etc.)

Example:
```gene
(var dev (device/create "cpu"))
```

### `embedding` Namespace
Embedding layer creation for NLP models.

- `embedding/create dim` - Create embedding layer with specified dimensions

Example:
```gene
(var emb (embedding/create 768))
```

## Implementation

The AI integration consists of:

1. **Native C Implementation** (`src/gene/ai/gene_ai.c`)
   - Provides core tensor operations and model management
   - Implements efficient numerical computing primitives

2. **FFI Bindings** (`src/gene/ai/ai_bindings.nim`)
   - Bridges Gene VM with C implementation
   - Handles data type conversions

3. **Native Function Registration** (`src/gene/ai/ai_natives.nim`)
   - Registers AI functions as Gene native functions
   - Provides Gene-friendly interfaces to AI operations

## Examples

Several examples demonstrate the AI capabilities:

- `examples/ai_demo.gene` - Comprehensive AI/ML capabilities showcase
- `examples/ai_model.gene` - Neural network layer implementation
- `examples/tensor_basic.gene` - Tensor operations tutorial
- `examples/llm_inference.gene` - LLM inference simulation
- `examples/ai_test_simple.gene` - Integration test suite

## Usage

```gene
#!/usr/bin/env gene

# Create AI components
(var tokenizer (tokenizer/create 50000))
(var embeddings (embedding/create 768))
(var model (model/create "my_model" "transformer"))
(var device (device/create "cpu"))

# Tensor operations
(var input (tensor/create [32 768] :float32))
(var weights (tensor/random [768 256]))
(var output (tensor/matmul input weights))

# Process through layers
(fn forward_pass [x]
  (var h1 (tensor/matmul x W1))
  (var h2 (relu h1))
  (tensor/matmul h2 W2))
```

## Technical Details

- **Value Types**: Extended Gene's type system with `VkTensor`, `VkEmbedding`, etc.
- **Memory Management**: Tensors are reference-counted with automatic cleanup
- **Performance**: Native C implementation ensures efficient computation
- **Compatibility**: Works on CPU with planned GPU support

## Future Enhancements

- GPU acceleration via CUDA/Metal
- Integration with popular ML frameworks (PyTorch, TensorFlow)
- Pre-trained model loading
- Automatic differentiation for training
- More tensor operations (convolution, pooling, etc.)

## Status

The AI integration is functional and tested. All core features work correctly:
- ✅ Tensor creation and operations
- ✅ Model and device management  
- ✅ Tokenization support
- ✅ Namespace integration
- ✅ Example demonstrations