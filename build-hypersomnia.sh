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

echo ""
echo "========================================"
echo " Preparing Hypersomnia source"
echo "========================================"

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
# Remove only known top-level pthread configuration
# ============================================================

echo ""
echo "========================================"
echo " Checking top-level pthread configuration"
echo "========================================"


# Remove explicit USE_BIGINT setting if present.
sed -i \
    '/^[[:space:]]*set(USE_BIGINT ON)[[:space:]]*$/d' \
    CMakeLists.txt


# Remove an explicit USE_PTHREADS assignment if the upstream
# project contains one.
sed -i \
    '/^[[:space:]]*set(USE_PTHREADS[[:space:]]/d' \
    CMakeLists.txt


# Remove known Emscripten pthread linker settings from the
# TOP-LEVEL Hypersomnia CMake file only.
#
# We intentionally do NOT recursively edit third-party
# libraries or submodules.

sed -i \
    's/[[:space:]]*-pthread[[:space:]]*//g' \
    CMakeLists.txt

sed -i \
    's/[[:space:]]*-s[[:space:]]*USE_PTHREADS=1[[:space:]]*//g' \
    CMakeLists.txt

sed -i \
    's/[[:space:]]*-sPTHREAD_POOL_SIZE=6[[:space:]]*//g' \
    CMakeLists.txt

sed -i \
    's/[[:space:]]*-s[[:space:]]*PTHREAD_POOL_SIZE=[^[:space:]"'\'']*[[:space:]]*//g' \
    CMakeLists.txt


echo ""
echo "Top-level CMake pthread settings after cleanup:"

if grep -nEi \
    'USE_PTHREADS|-pthread|PTHREAD_POOL_SIZE' \
    CMakeLists.txt; then

    echo ""
    echo "WARNING:"
    echo "The top-level CMake file still contains pthread-related text."
    echo "This will be checked against the actual generated build commands."

else

    echo "None found."

fi


# ============================================================
# Keep Web UI font scale appropriate for Chromebook
# ============================================================

echo ""
echo "========================================"
echo " Applying Web UI font scaling"
echo "========================================"


sed -i \
    's/return scale \* std::min(1.333333333f, ratio);/return scale * std::min(1.0f, ratio);/' \
    src/work.cpp


# ============================================================
# Prepare Emscripten
# ============================================================

echo ""
echo "========================================"
echo " Preparing Emscripten"
echo "========================================"


if [ ! -d "$EMSDK/.git" ]; then

    echo "Cloning Emscripten SDK..."

    git clone \
        https://github.com/emscripten-core/emsdk.git \
        "$EMSDK"

fi


cd "$EMSDK"


echo ""
echo "Installing Emscripten..."

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
# Clean previous CMake configuration
# ============================================================

echo ""
echo "========================================"
echo " Cleaning previous Web configuration"
echo "========================================"


rm -rf build/current


# ============================================================
# Configure Web build
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


BUILD_DIR="$HYPERSOMNIA/build/current"


# ============================================================
# Verify CMake configuration exists
# ============================================================

echo ""
echo "========================================"
echo " Verifying CMake configuration"
echo "========================================"


if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then

    echo "ERROR: CMakeCache.txt was not generated."

    exit 1

fi


if [ ! -f "$BUILD_DIR/build.ninja" ]; then

    echo "ERROR: build.ninja was not generated."

    exit 1

fi


echo "CMake configuration exists."


# ============================================================
# Inspect ACTUAL generated build commands
# ============================================================

echo ""
echo "========================================"
echo " Checking actual generated build commands"
echo "========================================"


echo "Asking Ninja for the commands required to build Hypersomnia..."

NINJA_COMMANDS="$(
    ninja \
        -C "$BUILD_DIR" \
        -t commands \
        Hypersomnia \
        2>/dev/null || true
)"


if [ -z "$NINJA_COMMANDS" ]; then

    echo ""
    echo "WARNING: Ninja did not return build commands."

    echo "The build will continue and the final generated"
    echo "JavaScript will be checked after compilation."

else

    echo ""
    echo "Checking generated commands for pthread flags..."

    if printf '%s\n' "$NINJA_COMMANDS" |
        grep -nEi \
        -- '-pthread|USE_PTHREADS=1|PTHREAD_POOL_SIZE'; then

        echo ""
        echo "ERROR: pthread support is present in the actual"
        echo "generated Web build commands."

        echo ""
        echo "This is different from merely finding pthread"
        echo "text inside a third-party CMake file."

        echo ""
        echo "The build has been stopped because this Web target"
        echo "would not be reliably single-threaded."

        exit 1

    else

        echo ""
        echo "PASS: No pthread flags found in generated"
        echo "Hypersomnia build commands."

    fi

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
# Resolve actual build directory
# ============================================================

REAL_BUILD_DIR="$BUILD_DIR"

if [ -L "$BUILD_DIR" ]; then

    REAL_BUILD_DIR="$(readlink -f "$BUILD_DIR")"

fi


echo ""
echo "Resolved build directory:"
echo "$REAL_BUILD_DIR"


# ============================================================
# Verify generated Web files
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
# Check generated JavaScript
# ============================================================

echo ""
echo "========================================"
echo " Checking generated JavaScript"
echo "========================================"


if grep -qE \
    'USE_PTHREADS|PTHREAD_POOL_SIZE|pthread-main|pthread-worker' \
    "$REAL_BUILD_DIR/Hypersomnia.js"; then

    echo ""
    echo "WARNING:"
    echo "The generated JavaScript contains pthread-related strings."

    echo ""
    echo "Matching lines:"

    grep -nE \
        'USE_PTHREADS|PTHREAD_POOL_SIZE|pthread-main|pthread-worker' \
        "$REAL_BUILD_DIR/Hypersomnia.js" \
        | head -20

    echo ""
    echo "This is reported as a warning rather than an immediate"
    echo "failure because third-party libraries can contain"
    echo "pthread-related runtime strings without the main"
    echo "Hypersomnia target actually being pthread-enabled."

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
# Show generated files
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

    echo ""
    echo "ERROR: WebAssembly game files were not generated."

    exit 1

fi


if [ ! -s "$DIST/Hypersomnia.wasm" ]; then

    echo ""
    echo "ERROR: Hypersomnia.wasm is empty."

    exit 1

fi


if [ ! -s "$DIST/Hypersomnia.js" ]; then

    echo ""
    echo "ERROR: Hypersomnia.js is empty."

    exit 1

fi


if [ ! -s "$DIST/Hypersomnia.data" ]; then

    echo ""
    echo "ERROR: Hypersomnia.data is empty."

    exit 1

fi


# ============================================================
# Final success
# ============================================================

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
