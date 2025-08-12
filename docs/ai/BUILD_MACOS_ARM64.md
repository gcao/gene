# Building Gene with LLaMA.cpp on macOS (Apple Silicon)

This guide provides step-by-step instructions for building Gene with full LLaMA.cpp integration on Apple Silicon Macs (M1/M2/M3).

## Prerequisites

### System Requirements
- macOS on Apple Silicon (M1/M2/M3)
- Xcode Command Line Tools
- At least 8GB RAM (16GB+ recommended for larger models)
- ~2GB disk space for build artifacts

### Install Dependencies
```bash
# Install Xcode Command Line Tools (if not already installed)
xcode-select --install

# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install build dependencies
brew install cmake git
```

## Step 1: Build Nim for ARM64

Gene requires Nim compiled for ARM64 architecture to properly link with native libraries.

### 1.1 Download Nim Source
```bash
cd ~/src  # or your preferred source directory
curl -O https://nim-lang.org/download/nim-2.0.16.tar.xz
tar -xf nim-2.0.16.tar.xz
cd nim-2.0.16
```

### 1.2 Compile Nim for ARM64
```bash
# Build Nim
sh build.sh

# Verify it's built for ARM64
./bin/nim --version
# Should show: Nim Compiler Version 2.0.16 [MacOSX: arm64]
```

### 1.3 Add Nim to PATH
```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc)
export PATH="$HOME/src/nim-2.0.16/bin:$PATH"

# Reload shell configuration
source ~/.zshrc  # or source ~/.bashrc
```

## Step 2: Build LLaMA.cpp

### 2.1 Clone and Build LLaMA.cpp
```bash
cd /path/to/gene
cd external/llama.cpp

# Configure with CMake
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_METAL=ON \
  -DLLAMA_ACCELERATE=ON \
  -DCMAKE_OSX_ARCHITECTURES=arm64

# Build (using all cores)
cmake --build build --config Release -j

# Verify libraries are built for ARM64
file build/bin/libllama.dylib
# Should show: Mach-O 64-bit dynamically linked shared library arm64
```

### 2.2 Download a Model
```bash
# Create models directory in Gene root
cd /path/to/gene
mkdir -p models

# Download TinyLlama (good for testing, ~637MB)
curl -L https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
  -o models/tinyllama.gguf
```

## Step 3: Build Gene

### 3.1 Configure Build Settings

Edit `gene.nimble` to remove architecture-specific flags that cause issues on ARM64:

```nim
# In gene.nimble, change this:
task speedy, "Optimized build for maximum performance":
  exec "nim c -d:release --mm:orc --opt:speed --passC:\"-march=native -O3\" -o:gene src/gene.nim"

# To this:
task speedy, "Optimized build for maximum performance":
  exec "nim c -d:release --mm:orc --opt:speed --passC:\"-O3\" -o:gene src/gene.nim"
```

### 3.2 Build Gene with ARM64 Nim
```bash
cd /path/to/gene

# Clean previous builds
rm -rf ~/.cache/nim/gene_*
rm -rf bin/gene

# Build with explicit ARM64 target
$HOME/src/nim-2.0.16/bin/nim c \
  -d:release \
  --cpu:arm64 \
  --os:macosx \
  --passC:"-O3" \
  --passL:"-arch arm64" \
  -o:bin/gene \
  src/gene.nim

# Verify the binary is ARM64
file bin/gene
# Should show: Mach-O 64-bit executable arm64
```

### Alternative: Use the Build Script
```bash
# Create and use the build script
cat > build_arm64.sh << 'EOF'
#!/bin/bash
set -e

echo "🔨 Building Gene for ARM64 with LLaMA.cpp support"

# Use ARM64 Nim
NIM_ARM64="$HOME/src/nim-2.0.16/bin/nim"

# Clean
rm -rf ~/.cache/nim/gene_*

# Build
$NIM_ARM64 c \
  -d:release \
  --cpu:arm64 \
  --os:macosx \
  --passC:"-O3" \
  --passL:"-arch arm64" \
  -o:bin/gene \
  src/gene.nim

echo "✅ Build complete!"
file bin/gene
EOF

chmod +x build_arm64.sh
./build_arm64.sh
```

## Step 4: Test the Integration

### 4.1 Test Native AI Operations
```bash
./bin/gene run examples/ai_complete.gene
```

### 4.2 Test LLaMA.cpp Integration
```bash
# Run the simple test
./bin/gene run examples/llama_simple_test.gene
```

### 4.3 Create Your Own Test
Create a file `test_llama.gene`:
```gene
# Test LLaMA.cpp integration
(println "Testing LLaMA.cpp...")

# Load model
(var result (genex/llamacpp/load "models/tinyllama.gguf"))
(println "Load result: " result)

# Generate text
(var text (genex/llamacpp/generate "Hello world" 20))
(println "Generated: " text)

# Cleanup
(genex/llamacpp/unload)
(println "Done!")
```

Run it:
```bash
./bin/gene run test_llama.gene
```

## Troubleshooting

### Issue: Architecture Mismatch Errors

**Symptom:** 
```
ld: warning: ignoring file ... found architecture 'x86_64', required architecture 'arm64'
```

**Solution:**
1. Ensure you're using ARM64 Nim (not the x86_64 version from choosenim)
2. Clear Nim cache: `rm -rf ~/.cache/nim/gene_*`
3. Rebuild with explicit architecture: `--cpu:arm64`

### Issue: `-march=native` Not Supported

**Symptom:**
```
clang: error: unsupported argument 'native' to option '-march='
```

**Solution:**
Remove `-march=native` from build flags. ARM64 macOS doesn't support this flag.

### Issue: Library Not Found

**Symptom:**
```
dyld: Library not loaded: @rpath/libllama.dylib
```

**Solution:**
Ensure rpath is set correctly in linking:
```nim
{.passL: "-Wl,-rpath,@loader_path/../external/llama.cpp/build/bin".}
```

### Issue: Model Loading Fails

**Symptom:**
```
Failed to load model
```

**Solution:**
1. Check model file exists and path is correct
2. Ensure model is in GGUF format
3. Verify sufficient memory available

## Project Structure

After successful build, your project should have:

```
gene/
├── bin/
│   └── gene                    # ARM64 executable
├── external/
│   └── llama.cpp/
│       └── build/
│           └── bin/
│               ├── libllama.dylib      # ARM64 library
│               ├── libggml.dylib       # ARM64 library
│               └── ...
├── models/
│   └── tinyllama.gguf          # Model file
├── src/
│   └── gene/
│       └── ai/
│           ├── llama_natives.nim      # LLaMA.cpp bindings
│           └── llama_wrapper.c        # C wrapper
└── examples/
    ├── llama_simple_test.gene  # Basic test
    └── genex_llamacpp_demo.gene # Full demo
```

## Performance Tips

1. **Metal Acceleration**: Enabled by default for GPU acceleration
2. **Memory Mapping**: Models are memory-mapped for efficiency
3. **Context Size**: Adjust in `llama_wrapper.c` if needed (default: 512 tokens)
4. **Thread Count**: Adjust in `llama_wrapper.c` based on CPU cores

## Next Steps

- For Linux + CUDA support, see `BUILD_LINUX_CUDA.md` (coming soon)
- For Windows support, see `BUILD_WINDOWS.md` (coming soon)
- For model recommendations, see `MODELS.md` (coming soon)

## Summary

Key requirements for successful build on Apple Silicon:
1. ✅ Use ARM64 Nim (not x86_64)
2. ✅ Build LLaMA.cpp for ARM64
3. ✅ Remove `-march=native` flag
4. ✅ Set proper rpath for dynamic libraries
5. ✅ Use GGUF format models

With these steps, Gene will have full LLaMA.cpp integration with Metal acceleration on Apple Silicon Macs.