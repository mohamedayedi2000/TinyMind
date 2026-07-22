#!/bin/sh
# Build TINYMIND. Requires NASM (https://www.nasm.us).
#   Ubuntu/Debian:  sudo apt install nasm
#   macOS:          brew install nasm
#   Windows:        download from nasm.us and put nasm.exe on your PATH
set -e
cd "$(dirname "$0")/src"
nasm -f bin main.asm -o ../tinymind.com
echo "Built tinymind.com"
