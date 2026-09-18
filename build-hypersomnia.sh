#!/usr/bin/env bash

set -e

echo "========================================"
echo " Hypersomnia WebAssembly Build"
echo "========================================"

# --------------------------------------------------
# Versions
# --------------------------------------------------

EMSDK_VERSION="latest"

# --------------------------------------------------
# Directories
# --------------------------------------------------

ROOT="$(pwd)"

BUILD_ROOT="$ROOT/build"

HYPERSOMNIA="$BUILD_ROOT/Hypersomnia"

EMSDK="$BUILD_ROOT/emsdk"

DIST="$ROOT/dist"

# --------------------------------------------------
# Clean output
# --------------------------------------------------

rm -rf "$DIST"

mkdir -p "$BUILD_ROOT"
mkdir -p "$DIST"

# --------------------------------------------------
# Clone Hypersomnia
# --------------------------------------------------

if [ ! -d "$HYPERSOMNIA/.git" ]; then

    echo "Cloning Hypersomnia..."

    git clone \
        --depth 1 \
        --recurse-submodules \
        https://github.com/TeamHypersomnia/Hypersomnia.git \
        "$HYPERSOMNIA"

else

    echo "Hypersomnia already exists."

fi

cd "$HYPERSOMNIA"

# --------------------------------------------------
# Clone Emscripten
# --------------------------------------------------

if [ ! -d "$EMSDK/.git" ]; then

    echo "Cloning Emscripten SDK..."

    git clone \
        https://github.com/emscripten-core/emsdk.git \
        "$EMSDK"

fi

cd "$EMSDK"

# --------------------------------------------------
# Install Emscripten
# --------------------------------------------------

./emsdk install "$EMSDK_VERSION"

./emsdk activate "$EMSDK_VERSION"

source ./emsdk_env.sh

echo "Emscripten:"
emcc --version

echo "CMake:"
cmake --version

echo "Ninja:"
ninja --version

# --------------------------------------------------
# Return to Hypersomnia
# --------------------------------------------------

cd "$HYPERSOMNIA"

# --------------------------------------------------
# Build Hypersomnia Web version
# --------------------------------------------------

echo "Building Hypersomnia for Web..."

unset CC
unset CXX

./cmake/build.sh Release Web

# --------------------------------------------------
# Locate generated build
# --------------------------------------------------

BUILD_DIR="$HYPERSOMNIA/build/current"

echo "Build directory:"
echo "$BUILD_DIR"

find "$BUILD_DIR" \
    -maxdepth 2 \
    -type f \
    \( \
        -name "*.html" \
        -o -name "*.js" \
        -o -name "*.wasm" \
        -o -name "*.data" \
    \) \
    -print

# --------------------------------------------------
# Copy Web build
# --------------------------------------------------

echo "Copying Web build to dist..."

find "$BUILD_DIR" \
    -type f \
    \( \
        -name "*.html" \
        -o -name "*.js" \
        -o -name "*.wasm" \
        -o -name "*.data" \
    \) \
    -exec cp {} "$DIST/" \;

# Copy Hypersomnia's game resources.
if [ -d "$HYPERSOMNIA/hypersomnia" ]; then
    cp -R "$HYPERSOMNIA/hypersomnia" "$DIST/"
fi

# --------------------------------------------------
# Fail if no WebAssembly build was produced
# --------------------------------------------------

if ! find "$DIST" -type f \( -name "*.html" -o -name "*.wasm" \) | grep -q .; then
    echo "ERROR: No WebAssembly game files were generated."
    exit 1
fi

# --------------------------------------------------
# Verify
# --------------------------------------------------

echo ""
echo "========================================"
echo " Generated files"
echo "========================================"

find "$DIST" -type f -print

echo ""
echo "echo "Hypersomnia WebAssembly Build - Cloudflare"
