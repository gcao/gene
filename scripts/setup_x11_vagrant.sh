#!/bin/bash

# Install X11 dependencies in vagrant box
vagrant ssh -c "sudo apt-get update && sudo apt-get install -y xauth x11-apps x11-utils"

# Test X11 forwarding
echo "Testing X11 forwarding..."
vagrant ssh -- -Y -o ForwardX11=yes -o ForwardX11Trusted=yes -c "echo 'DISPLAY=$DISPLAY' && xeyes &"

echo ""
echo "Setup complete! To use kcachegrind with X11 forwarding:"
echo "1. Run: vagrant ssh -- -Y"
echo "2. In the vagrant box, run: kcachegrind <your-cachegrind-file>"