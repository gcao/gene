#!/bin/bash

# Ensure XQuartz allows connections from network clients
xhost +localhost > /dev/null 2>&1

# Get vagrant SSH config
SSH_CONFIG=$(vagrant ssh-config)

# Extract port and key file
PORT=$(echo "$SSH_CONFIG" | grep "Port" | awk '{print $2}')
KEY=$(echo "$SSH_CONFIG" | grep "IdentityFile" | awk '{print $2}')

# Connect with proper X11 forwarding
echo "Connecting to vagrant with X11 forwarding..."
ssh -Y -o ForwardX11=yes -o ForwardX11Trusted=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -p $PORT \
    -i "$KEY" \
    vagrant@127.0.0.1 \
    "$@"