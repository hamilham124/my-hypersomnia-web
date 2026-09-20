#!/usr/bin/env bash

set -e

echo "========================================"
echo " Hypersomnia WebAssembly Build"
echo "========================================"

EMSDK_VERSION="latest"

ROOT="$(pwd)"
BUILD_ROOT="$ROOT/build"
HYPERSOMNIA="$BUILD_ROOT/Hypersomnia"
EMSDK="$BUILD_ROOT/emsdk"
DIST="$ROOT/dist"

rm -rf "$DIST"
mkdir -p "$BUILD_ROOT"
mkdir -p "$DIST"

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

# The upstream Web configuration currently unconditionally enables
# the obsolete -sWASM_BIGINT linker flag. Remove that setting because
# current Emscripten rejects it as a fatal deprecation warning.
sed -i '/^[[:space:]]*set(USE_BIGINT ON)[[:space:]]*$/d' CMakeLists.txt

if [ ! -d "$EMSDK/.git" ]; then
    echo "Cloning Emscripten SDK..."
    git clone https://github.com/emscripten-core/emsdk.git "$EMSDK"
fi

cd "$EMSDK"

./emsdk install "$EMSDK_VERSION"
./emsdk activate "$EMSDK_VERSION"
source ./emsdk_env.sh

echo "Emscripten:"
emcc --version
echo "CMake:"
cmake --version
echo "Ninja:"
ninja --version

cd "$HYPERSOMNIA"

echo "Building Hypersomnia for Web..."

unset CC
unset CXX

./cmake/build.sh Release Web -DUSE_BIGINT=OFF

BUILD_DIR="$HYPERSOMNIA/build/current"
REAL_BUILD_DIR="$(readlink -f "$BUILD_DIR")"

echo "Compiling Hypersomnia Web target..."
cmake --build "$BUILD_DIR" --target Hypersomnia --parallel 2

echo "Resolved build directory:"
echo "$REAL_BUILD_DIR"

echo "Copying complete Web build to dist..."

cp -R "$REAL_BUILD_DIR"/. "$DIST/"

if [ -f "$DIST/Hypersomnia.html" ]; then
    mv "$DIST/Hypersomnia.html" "$DIST/index.html"
fi

echo "Dist contents:"
find "$DIST" -type f -print

if ! find "$DIST" -type f \( -name "*.html" -o -name "*.wasm" \) | grep -q .; then
    echo "ERROR: No WebAssembly game files were generated."
    exit 1
fi

echo ""
echo "========================================"
echo " Generated files"
echo "========================================"

find "$DIST" -type f -print

echo ""
echo "Hypersomnia WebAssembly Build complete."
