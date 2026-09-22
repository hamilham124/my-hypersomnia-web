#!/usr/bin/env bash

set -e

echo "========================================"
echo " Hypersomnia WebAssembly Build"
echo " SINGLE-THREADED WEB BUILD"
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


# ============================================================
# Clone Hypersomnia
# ============================================================

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


# ============================================================
# Force a SINGLE-THREADED Web build
# ============================================================

echo ""
echo "========================================"
echo " Removing pthread configuration"
echo "========================================"


# Remove explicit USE_BIGINT setting.
sed -i \
    '/^[[:space:]]*set(USE_BIGINT ON)[[:space:]]*$/d' \
    CMakeLists.txt


# Remove any explicit USE_PTHREADS CMake configuration.
sed -i \
    '/USE_PTHREADS[[:space:]]*=/d' \
    CMakeLists.txt


# Remove the pthread linker flags from the upstream
# CMAKE_EXE_LINKER_FLAGS assignment.
#
# This removes:
#
#   -pthread
#   -s USE_PTHREADS=1
#   -sPTHREAD_POOL_SIZE=6
#
# from the Web build.
sed -i \
    's/[[:space:]]*-pthread[[:space:]]*//g' \
    CMakeLists.txt

sed -i \
    's/[[:space:]]*-s[[:space:]]*USE_PTHREADS=1[[:space:]]*//g' \
    CMakeLists.txt

sed -i \
    's/[[:space:]]*-sPTHREAD_POOL_SIZE=6[[:space:]]*//g' \
    CMakeLists.txt


# Remove any remaining Emscripten pthread settings that may
# have been added using alternate syntax.
sed -i \
    '/PTHREAD_POOL_SIZE/d' \
    CMakeLists.txt


# Remove USE_PTHREADS from any Web-specific build arguments.
sed -i \
    '/USE_PTHREADS/d' \
    CMakeLists.txt


# Remove explicit pthread compiler/linker flags from all
# CMake files in the source tree.
#
# This is intentionally done across the project because
# pthread flags can be introduced by a subdirectory rather
# than only the root CMakeLists.txt.
find . \
    -type f \
    \( \
        -name "CMakeLists.txt" \
        -o -name "*.cmake" \
    \) \
    -print0 |
while IFS= read -r -d '' file; do

    sed -i \
        's/[[:space:]]*-pthread[[:space:]]*//g' \
        "$file"

    sed -i \
        's/[[:space:]]*-s[[:space:]]*USE_PTHREADS=1[[:space:]]*//g' \
        "$file"

    sed -i \
        's/[[:space:]]*-sPTHREAD_POOL_SIZE=[^[:space:]"'\'']*[[:space:]]*//g' \
        "$file"

done


# ============================================================
# Keep the Web UI font scale appropriate for the Chromebook.
# ============================================================

sed -i \
    's/return scale \* std::min(1.333333333f, ratio);/return scale * std::min(1.0f, ratio);/' \
    src/work.cpp


# ============================================================
# Verify that pthread flags are actually gone.
# ============================================================

echo ""
echo "========================================"
echo " Verifying pthread configuration"
echo "========================================"

echo "Searching CMake files for pthread configuration..."

if grep -RniE \
    --include='CMakeLists.txt' \
    --include='*.cmake' \
    'USE_PTHREADS|-pthread|PTHREAD_POOL_SIZE' \
    .; then

    echo ""
    echo "ERROR: pthread configuration is still present."
    echo "The build has been stopped intentionally."
    exit 1

else

    echo ""
    echo "PASS: No pthread flags found in CMake configuration."

fi


# ============================================================
# Clone Emscripten SDK
# ============================================================

if [ ! -d "$EMSDK/.git" ]; then

    echo ""
    echo "Cloning Emscripten SDK..."

    git clone \
        https://github.com/emscripten-core/emsdk.git \
        "$EMSDK"

fi


cd "$EMSDK"


# ============================================================
# Install Emscripten
# ============================================================

echo ""
echo "========================================"
echo " Installing Emscripten"
echo "========================================"

./emsdk install "$EMSDK_VERSION"

./emsdk activate "$EMSDK_VERSION"

source ./emsdk_env.sh


echo ""
echo "Emscripten:"
emcc --version

echo ""
echo "CMake:"
cmake --version

echo ""
echo "Ninja:"
ninja --version


cd "$HYPERSOMNIA"


# ============================================================
# Clean previous CMake state
# ============================================================

echo ""
echo "========================================"
echo " Cleaning previous Web build"
echo "========================================"

rm -rf build/current


# ============================================================
# Build Web configuration
# ============================================================

echo ""
echo "========================================"
echo " Configuring Hypersomnia Web"
echo " SINGLE-THREADED"
echo "========================================"


unset CC
unset CXX


./cmake/build.sh \
    Release \
    Web \
    -DUSE_BIGINT=OFF


# ============================================================
# Verify generated CMake cache
# ============================================================

BUILD_DIR="$HYPERSOMNIA/build/current"

echo ""
echo "========================================"
echo " Checking generated CMake configuration"
echo "========================================"

if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then

    echo "ERROR: CMakeCache.txt was not generated."

    exit 1

fi


echo "Checking CMake cache for pthreads..."

if grep -niE \
    'USE_PTHREADS|PTHREAD_POOL_SIZE|-pthread' \
    "$BUILD_DIR/CMakeCache.txt"; then

    echo ""
    echo "ERROR: pthread configuration remains in CMake cache."

    exit 1

else

    echo ""
    echo "PASS: CMake cache contains no pthread configuration."

fi


# ============================================================
# Build Hypersomnia
# ============================================================

echo ""
echo "========================================"
echo " Compiling Hypersomnia"
echo "========================================"


cmake \
    --build "$BUILD_DIR" \
    --target Hypersomnia \
    --parallel 2


# ============================================================
# Resolve build directory
# ============================================================

REAL_BUILD_DIR="$HYPERSOMNIA/build/current"

if [ -L "$BUILD_DIR" ]; then

    REAL_BUILD_DIR="$(readlink -f "$BUILD_DIR")"

fi


echo ""
echo "Resolved build directory:"
echo "$REAL_BUILD_DIR"


# ============================================================
# Verify generated files
# ============================================================

echo ""
echo "========================================"
echo " Checking generated Web files"
echo "========================================"


if [ ! -f "$REAL_BUILD_DIR/Hypersomnia.html" ]; then

    echo "ERROR: Hypersomnia.html was not generated."

    exit 1

fi


if [ ! -f "$REAL_BUILD_DIR/Hypersomnia.js" ]; then

    echo "ERROR: Hypersomnia.js was not generated."

    exit 1

fi


if [ ! -f "$REAL_BUILD_DIR/Hypersomnia.wasm" ]; then

    echo "ERROR: Hypersomnia.wasm was not generated."

    exit 1

fi


if [ ! -f "$REAL_BUILD_DIR/Hypersomnia.data" ]; then

    echo "ERROR: Hypersomnia.data was not generated."

    exit 1

fi


# ============================================================
# Check generated JavaScript for pthread runtime code
# ============================================================

echo ""
echo "========================================"
echo " Checking generated JavaScript"
echo "========================================"


if grep -qE \
    'USE_PTHREADS|PTHREAD_POOL_SIZE|pthread-main|pthread-worker' \
    "$REAL_BUILD_DIR/Hypersomnia.js"; then

    echo ""
    echo "WARNING: pthread-related strings were found in Hypersomnia.js."
    echo "Showing matching lines:"

    grep -nE \
        'USE_PTHREADS|PTHREAD_POOL_SIZE|pthread-main|pthread-worker' \
        "$REAL_BUILD_DIR/Hypersomnia.js" \
        | head -20

else

    echo ""
    echo "PASS: No obvious pthread runtime configuration found."

fi


# ============================================================
# Copy Web runtime to dist
# ============================================================

echo ""
echo "========================================"
echo " Copying Web runtime to dist"
echo "========================================"


rm -rf "$DIST"

mkdir -p "$DIST"


cp \
    "$REAL_BUILD_DIR/Hypersomnia.html" \
    "$DIST/index.html"


cp \
    "$REAL_BUILD_DIR/Hypersomnia.js" \
    "$DIST/"


cp \
    "$REAL_BUILD_DIR/Hypersomnia.wasm" \
    "$DIST/"


cp \
    "$REAL_BUILD_DIR/Hypersomnia.data" \
    "$DIST/"


cp -R \
    "$REAL_BUILD_DIR/assets" \
    "$DIST/"


# ============================================================
# Final file listing
# ============================================================

echo ""
echo "========================================"
echo " Dist contents"
echo "========================================"


find "$DIST" \
    -type f \
    -print


# ============================================================
# Final validation
# ============================================================

echo ""
echo "========================================"
echo " Final validation"
echo "========================================"


if ! find "$DIST" \
    -type f \
    \( \
        -name "*.html" \
        -o -name "*.js" \
        -o -name "*.wasm" \
        -o -name "*.data" \
    \) |
    grep -q .; then

    echo "ERROR: WebAssembly game files were not generated."

    exit 1

fi


if [ ! -s "$DIST/Hypersomnia.wasm" ]; then

    echo "ERROR: Hypersomnia.wasm is empty."

    exit 1

fi


if [ ! -s "$DIST/Hypersomnia.js" ]; then

    echo "ERROR: Hypersomnia.js is empty."

    exit 1

fi


if [ ! -s "$DIST/Hypersomnia.data" ]; then

    echo "ERROR: Hypersomnia.data is empty."

    exit 1

fi


echo ""
echo "========================================"
echo " WebAssembly Build complete"
echo " SINGLE-THREADED BUILD: READY"
echo "========================================"

echo ""
echo "Generated files:"

ls -lh \
    "$DIST/index.html" \
    "$DIST/Hypersomnia.js" \
    "$DIST/Hypersomnia.wasm" \
    "$DIST/Hypersomnia.data"

echo ""
echo "The build is ready for packaging."
