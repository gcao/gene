# Gene Tensor API User Guide

## Overview

Gene provides native support for tensor operations, making it suitable for AI/ML workloads. Tensors are first-class values in the Gene VM with dedicated instructions for efficient computation.

## Creating Tensors

### Basic Creation

```gene
# Create a tensor with shape
(var t (tensor/create [2 3]))  # 2x3 tensor, default float32 on CPU

# Specify dtype and device
(var t-gpu (tensor/create [100 100] :float16 :cuda))
(var t-int (tensor/create [5 5] :int32 :cpu))
```

### Special Tensors

```gene
# Zero tensor
(var zeros (tensor/zeros [3 3]))

# Ones tensor
(var ones (tensor/ones [3 3]))

# Random tensor
(var random (tensor/random [10 10]))
```

## Tensor Properties

```gene
# Get tensor shape
(tensor/shape my-tensor)  # Returns [2 3]

# Get tensor dtype
(tensor/dtype my-tensor)  # Returns :float32

# Get tensor device
(tensor/device my-tensor)  # Returns :cpu

# Get tensor info string
(tensor/info my-tensor)  # Returns descriptive string
```

## Arithmetic Operations

### Element-wise Operations

```gene
# Addition
(var c (tensor/add a b))
(var c (+ a b))  # When both operands are tensors

# Subtraction
(var c (tensor/sub a b))
(var c (- a b))

# Multiplication (element-wise)
(var c (tensor/mul a b))
(var c (* a b))

# Division
(var c (tensor/div a b))
(var c (/ a b))
```

### Matrix Operations

```gene
# Matrix multiplication
(var c (tensor/matmul a b))
(var c (@ a b))  # @ operator for matmul

# Transpose (2D only)
(var t-transposed (tensor/transpose t))
```

## Shape Operations

### Reshape

```gene
# Reshape to new dimensions
(var reshaped (tensor/reshape t [3 2]))

# Flatten to 1D
(var flat (tensor/reshape t [6]))

# Use -1 to infer dimension
(var auto (tensor/reshape t [-1 2]))  # Infers first dim as 3
```

### Slicing

```gene
# Slice tensor (start and stop indices)
(var slice (tensor/slice t [0 0] [1 2]))
```

## Device Management

```gene
# Create device handles
(var cpu-dev (device/create :cpu))
(var gpu-dev (device/create :cuda 0))  # CUDA device 0

# Move tensor to device
(var t-gpu (tensor/to-device t gpu-dev))
```

## Data Types

Supported tensor data types:
- `:float32` - 32-bit floating point (default)
- `:float16` - 16-bit floating point
- `:bfloat16` - Brain floating point 16
- `:int8` - 8-bit integer
- `:int16` - 16-bit integer
- `:int32` - 32-bit integer
- `:int64` - 64-bit integer
- `:uint8` - Unsigned 8-bit integer
- `:bool` - Boolean

## Model Management

```gene
# Create a model container
(var model (model/create "my-model" "onnx"))

# Create a model session
(var session (model/session model cpu-dev))
```

## Tokenization and Embeddings

```gene
# Create tokenizer
(var tokenizer (tokenizer/create 50000))  # 50k vocab size

# Create embedding layer
(var embeddings (embedding/create 768))  # 768-dim embeddings
```

## Data Loading

```gene
# Create data loader for batching
(var dataset [1 2 3 4 5 6 7 8])
(var loader (dataloader/create dataset 2 true))  # batch_size=2, shuffle=true
```

## Gradient Computation

```gene
# Create gradient tape for automatic differentiation
(var tape (gradient/tape))

# Record operations (placeholder - actual autograd not yet implemented)
(gradient/record tape operation)
```

## Neural Network Example

```gene
# Simple linear layer
(fn linear [input weight bias]
  (tensor/add (tensor/matmul input weight) bias))

# ReLU activation
(fn relu [x]
  (tensor/max x (tensor/zeros (tensor/shape x))))

# Simple feedforward network
(fn forward [x]
  (var h1 (linear x w1 b1))
  (var h1-act (relu h1))
  (var h2 (linear h1-act w2 b2))
  h2)
```

## FFI Integration

Gene's tensor system is designed to integrate with external libraries:

```gene
# Load external ML library (future)
(ffi/load "torch" "/path/to/libtorch.so")

# Call external tensor operations
(ffi/call "torch" "conv2d" tensor kernel)
```

## Python Interoperability

```gene
# Import Python ML libraries (future)
(python/import numpy :as np)
(python/import torch)

# Convert between Gene and Python tensors
(var py-tensor (python/call np.array gene-tensor))
(var gene-tensor (tensor/from-python py-tensor))
```

## Performance Considerations

1. **Memory Layout**: Tensors use row-major ordering by default
2. **Device Placement**: Keep tensors on the same device to avoid transfers
3. **Batch Operations**: Use batched operations when possible
4. **Shape Compatibility**: Ensure shapes match for element-wise operations

## Limitations (Current Implementation)

- Tensor data is not actually stored (metadata only)
- No actual computation performed (placeholder operations)
- FFI and Python bridges need library linking
- GPU operations are not implemented
- Autograd/backpropagation not implemented

## Future Enhancements

- SIMD vectorization for CPU operations
- CUDA kernel generation
- Automatic differentiation
- Distributed tensor operations
- Model serialization (ONNX, SavedModel)
- Quantization support
- Custom operators

## Complete Example

```gene
#!/usr/bin/env gene

# Simple neural network for MNIST-like classification
(ns mnist-classifier)

# Model parameters
(var input-size 784)   # 28x28 images
(var hidden-size 128)
(var output-size 10)   # 10 classes

# Initialize weights and biases
(var w1 (tensor/random [input-size hidden-size]))
(var b1 (tensor/zeros [hidden-size]))
(var w2 (tensor/random [hidden-size output-size]))
(var b2 (tensor/zeros [output-size]))

# Activation functions
(fn relu [x]
  x)  # Placeholder

(fn softmax [x]
  x)  # Placeholder

# Forward pass
(fn forward [input]
  (var h1 (tensor/add (tensor/matmul input w1) b1))
  (var h1-activated (relu h1))
  (var output (tensor/add (tensor/matmul h1-activated w2) b2))
  (softmax output))

# Training loop (conceptual)
(fn train [data labels epochs lr]
  (loop [epoch 0 .. epochs]
    (println "Epoch" epoch)
    (for [batch data]
      (var predictions (forward batch))
      ; Compute loss and gradients (not implemented)
      ; Update weights (not implemented)
      )))

# Inference
(fn predict [image]
  (var input (tensor/reshape image [1 784]))
  (forward input))

(println "MNIST Classifier initialized")
(println "Model has" (+ (* input-size hidden-size) 
                       (* hidden-size output-size) 
                       hidden-size output-size) 
         "parameters")
```

## API Reference

### Tensor Creation
- `(tensor/create shape [dtype] [device])` - Create tensor
- `(tensor/zeros shape [dtype] [device])` - Zero tensor
- `(tensor/ones shape [dtype] [device])` - Ones tensor
- `(tensor/random shape [dtype] [device])` - Random tensor

### Tensor Operations
- `(tensor/add a b)` - Element-wise addition
- `(tensor/sub a b)` - Element-wise subtraction
- `(tensor/mul a b)` - Element-wise multiplication
- `(tensor/div a b)` - Element-wise division
- `(tensor/matmul a b)` - Matrix multiplication
- `(tensor/transpose t)` - Transpose 2D tensor

### Shape Operations
- `(tensor/reshape t new-shape)` - Reshape tensor
- `(tensor/slice t start stop)` - Slice tensor

### Tensor Properties
- `(tensor/shape t)` - Get shape
- `(tensor/dtype t)` - Get data type
- `(tensor/device t)` - Get device
- `(tensor/info t)` - Get info string

### Model Operations
- `(model/create name format)` - Create model
- `(model/session model device)` - Create inference session

### Data Operations
- `(dataloader/create dataset batch-size shuffle)` - Create data loader
- `(tokenizer/create vocab-size)` - Create tokenizer
- `(embedding/create dim)` - Create embedding layer