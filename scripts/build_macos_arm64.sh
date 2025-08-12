#!/bin/bash
# Build Gene with LLaMA.cpp support on macOS ARM64
# Usage: ./scripts/build_macos_arm64.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GENE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NIM_VERSION="2.0.16"
NIM_SOURCE_DIR="$HOME/src/nim-${NIM_VERSION}"
NIM_BIN="$NIM_SOURCE_DIR/bin/nim"

echo -e "${GREEN}🔨 Building Gene with LLaMA.cpp Support for macOS ARM64${NC}"
echo "=================================================="
echo "Gene root: $GENE_ROOT"
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    # Check for Xcode Command Line Tools
    if ! xcode-select -p &> /dev/null; then
        echo -e "${RED}❌ Xcode Command Line Tools not installed${NC}"
        echo "Run: xcode-select --install"
        exit 1
    fi
    
    # Check for CMake
    if ! command -v cmake &> /dev/null; then
        echo -e "${RED}❌ CMake not found${NC}"
        echo "Run: brew install cmake"
        exit 1
    fi
    
    # Check architecture
    if [[ $(uname -m) != "arm64" ]]; then
        echo -e "${RED}❌ This script is for ARM64 Macs only${NC}"
        echo "Detected architecture: $(uname -m)"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites satisfied${NC}"
}

# Function to build Nim for ARM64
build_nim() {
    echo ""
    echo -e "${YELLOW}📦 Setting up Nim for ARM64...${NC}"
    
    if [ -f "$NIM_BIN" ]; then
        # Check if it's ARM64
        if $NIM_BIN --version | grep -q "arm64"; then
            echo -e "${GREEN}✅ ARM64 Nim already available${NC}"
            return 0
        fi
    fi
    
    echo "Nim ARM64 not found. Please build Nim for ARM64 first:"
    echo ""
    echo "1. Download Nim source:"
    echo "   cd ~/src"
    echo "   curl -O https://nim-lang.org/download/nim-${NIM_VERSION}.tar.xz"
    echo "   tar -xf nim-${NIM_VERSION}.tar.xz"
    echo "   cd nim-${NIM_VERSION}"
    echo ""
    echo "2. Build Nim:"
    echo "   sh build.sh"
    echo ""
    echo "3. Run this script again"
    exit 1
}

# Function to build LLaMA.cpp
build_llamacpp() {
    echo ""
    echo -e "${YELLOW}🦙 Building LLaMA.cpp...${NC}"
    
    cd "$GENE_ROOT/external/llama.cpp"
    
    # Clean previous build
    rm -rf build
    
    # Configure with CMake
    cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLAMA_METAL=ON \
        -DLLAMA_ACCELERATE=ON \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        > /dev/null 2>&1
    
    # Build
    echo "Building LLaMA.cpp (this may take a few minutes)..."
    cmake --build build --config Release -j > /dev/null 2>&1
    
    # Verify
    if [ -f "build/bin/libllama.dylib" ]; then
        echo -e "${GREEN}✅ LLaMA.cpp built successfully${NC}"
        file build/bin/libllama.dylib | grep -q "arm64" || {
            echo -e "${RED}❌ LLaMA.cpp not built for ARM64${NC}"
            exit 1
        }
    else
        echo -e "${RED}❌ LLaMA.cpp build failed${NC}"
        exit 1
    fi
}

# Function to build Gene
build_gene() {
    echo ""
    echo -e "${YELLOW}🧬 Building Gene...${NC}"
    
    cd "$GENE_ROOT"
    
    # Clean cache
    echo "Cleaning build cache..."
    rm -rf ~/.cache/nim/gene_*
    rm -rf bin/gene
    
    # Build Gene
    echo "Compiling Gene for ARM64..."
    $NIM_BIN c \
        -d:release \
        --cpu:arm64 \
        --os:macosx \
        --passC:"-O3" \
        --passL:"-arch arm64" \
        -o:bin/gene \
        src/gene.nim \
        > /dev/null 2>&1
    
    # Verify
    if [ -f "bin/gene" ]; then
        if file bin/gene | grep -q "arm64"; then
            echo -e "${GREEN}✅ Gene built successfully for ARM64${NC}"
        else
            echo -e "${RED}❌ Gene not built for ARM64${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Gene build failed${NC}"
        exit 1
    fi
}

# Function to download model if needed
download_model() {
    echo ""
    echo -e "${YELLOW}📚 Checking for model...${NC}"
    
    if [ ! -d "$GENE_ROOT/models" ]; then
        mkdir -p "$GENE_ROOT/models"
    fi
    
    if [ ! -f "$GENE_ROOT/models/tinyllama.gguf" ]; then
        echo "Downloading TinyLlama model (637MB)..."
        curl -L https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
            -o "$GENE_ROOT/models/tinyllama.gguf" \
            --progress-bar
        echo -e "${GREEN}✅ Model downloaded${NC}"
    else
        echo -e "${GREEN}✅ Model already present${NC}"
    fi
}

# Function to test the build
test_build() {
    echo ""
    echo -e "${YELLOW}🧪 Testing the build...${NC}"
    
    cd "$GENE_ROOT"
    
    # Create a simple test
    cat > /tmp/test_gene_llama.gene << 'EOF'
(println "Testing Gene + LLaMA.cpp integration...")
(var info (genex/llamacpp/info))
(println "Backend: " (info ^backend))
(println "✅ Integration working!")
EOF
    
    # Run test
    if ./bin/gene run /tmp/test_gene_llama.gene 2>/dev/null | grep -q "Integration working"; then
        echo -e "${GREEN}✅ Test passed!${NC}"
    else
        echo -e "${RED}❌ Test failed${NC}"
        exit 1
    fi
    
    rm -f /tmp/test_gene_llama.gene
}

# Main execution
main() {
    check_prerequisites
    build_nim
    build_llamacpp
    build_gene
    download_model
    test_build
    
    echo ""
    echo -e "${GREEN}🎉 Build Complete!${NC}"
    echo "================================"
    echo ""
    echo "Gene is ready with LLaMA.cpp support!"
    echo ""
    echo "Try running:"
    echo "  ./bin/gene run examples/llama_simple_test.gene"
    echo "  ./bin/gene run examples/genex_llamacpp_demo.gene"
    echo ""
    echo "For more information, see docs/ai/BUILD_MACOS_ARM64.md"
}

# Run main function
main "$@"