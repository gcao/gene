#!/bin/bash

# Script to run kcachegrind in vagrant with X11 forwarding

# Ensure XQuartz is running
if ! pgrep -x "Xquartz" > /dev/null; then
    echo "Starting XQuartz..."
    open -a XQuartz
    sleep 2
fi

# Allow localhost connections
DISPLAY=:0 xhost +localhost > /dev/null 2>&1

# Get the cachegrind file argument
CACHEGRIND_FILE="${1}"

if [ -z "$CACHEGRIND_FILE" ]; then
    echo "Usage: $0 <cachegrind-output-file>"
    echo "Example: $0 cachegrind.out.12345"
    exit 1
fi

# Run kcachegrind in vagrant
echo "Running kcachegrind with file: $CACHEGRIND_FILE"
DISPLAY=:0 ./vagrant_x11.sh "cd /vagrant && kcachegrind $CACHEGRIND_FILE"