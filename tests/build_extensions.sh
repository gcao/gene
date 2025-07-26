#!/bin/bash

# Build test extensions as dynamic libraries

# Detect OS and use appropriate extension
if [[ "$OSTYPE" == "darwin"* ]]; then
    EXT="dylib"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    EXT="dll"
else
    EXT="so"
fi

echo "Building extension.$EXT..."
nim c --app:lib --out:extension.$EXT extension.nim

echo "Building extension2.$EXT..."
nim c --app:lib --out:extension2.$EXT extension2.nim

echo "Done!"