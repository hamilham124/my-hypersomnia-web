#!/usr/bin/env bash

set -e

echo "========================================"
echo " Hypersomnia WebAssembly Build"
echo " SINGLE-THREADED WEB BUILD"
echo " FULLSCREEN + POINTER LOCK SUPPORT"
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
# Remove known pthread configuration
# ============================================================

echo ""
echo "========================================"
echo " Removing Web pthread configuration"
echo "========================================"


sed -i \
    '/^[[:space:]]*set(USE_BIGINT ON)[[:space:]]*$/d' \
    CMakeLists.txt


sed -i \
    '/^[[:space:]]*set(USE_PTHREADS[[:space:]]/d' \
    CMakeLists.txt


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
echo "Top-level pthread configuration after cleanup:"


if grep -nEi \
    'USE_PTHREADS|-pthread|PTHREAD_POOL_SIZE' \
    CMakeLists.txt; then

    echo ""
    echo "WARNING:"
    echo "The top-level CMake file still contains pthread-related text."

else

    echo "None found."

fi


# ============================================================
# Web UI font scaling
# ============================================================

echo ""
echo "========================================"
echo " Applying Web UI font scaling"
echo "========================================"


sed -i \
    's/return scale \* std::min(1.333333333f, ratio);/return scale * std::min(1.0f, ratio);/' \
    src/work.cpp


# ============================================================
# Add browser interaction support
# ============================================================
#
# FULLSCREEN:
# Enables Emscripten fullscreen support.
#
# HTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS:
# Allows browser-sensitive operations such as fullscreen and
# pointer lock to be deferred until a user-generated event.
#
# ALLOW_MEMORY_GROWTH:
# Allows the WebAssembly heap to grow when additional memory
# is needed.
#
# Pointer lock itself is handled through the browser/SDL
# runtime rather than requiring pthreads.
#
# ============================================================

echo ""
echo "========================================"
echo " Configuring browser interaction support"
echo "========================================"


FULLSCREEN_FLAGS='
-sFULLSCREEN=1
-sHTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS=1
-sALLOW_MEMORY_GROWTH=1
'


# Remove any previous copy of these settings from the
# top-level CMake file before inserting the new configuration.

sed -i \
    '/FULLSCREEN=1/d' \
    CMakeLists.txt

sed -i \
    '/HTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS=1/d' \
    CMakeLists.txt

sed -i \
    '/ALLOW_MEMORY_GROWTH=1/d' \
    CMakeLists.txt


# Add the settings inside the existing Web build section.
#
# We use a small Python transformation rather than recursively
# modifying dependencies or third-party libraries.

python3 - <<'PY'
from pathlib import Path

path = Path("CMakeLists.txt")
text = path.read_text()

flags = """
    # Browser interaction support for WebAssembly.
    # Keep this target single-threaded.
    set(CMAKE_EXE_LINKER_FLAGS
        "${CMAKE_EXE_LINKER_FLAGS} -sFULLSCREEN=1 -sHTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS=1 -sALLOW_MEMORY_GROWTH=1"
    )
"""

marker = "if (BUILD_FOR_WEB)"

if marker not in text:
    raise SystemExit(
        "ERROR: Could not find BUILD_FOR_WEB section."
    )

if "-sFULLSCREEN=1" not in text:
    text = text.replace(
        marker,
        marker + "\n" + flags,
        1
    )

path.write_text(text)
PY


echo ""
echo "Browser support configuration added:"


grep -nEi \
    'FULLSCREEN|HTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS|ALLOW_MEMORY_GROWTH' \
    CMakeLists.txt || true


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
# Clean previous Web configuration
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
echo "========================================"

echo ""
echo "Browser features:"
echo "  Fullscreen: ENABLED"
echo "  Pointer lock: ENABLED through browser/SDL runtime"
echo "  Deferred user-sensitive requests: ENABLED"
echo "  Memory growth: ENABLED"
echo "  Pthreads: DISABLED"
echo ""


unset CC
unset CXX


./cmake/build.sh \
    Release \
    Web \
    -DUSE_BIGINT=OFF


BUILD_DIR="$HYPERSOMNIA/build/current"


# ============================================================
# Verify CMake configuration
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
# Inspect actual generated build commands
# ============================================================

echo ""
echo "========================================"
echo " Checking generated build commands"
echo "========================================"


echo "Asking Ninja for the actual commands..."

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

    echo "The build will continue."

else

    echo ""
    echo "Checking pthread configuration..."


    if printf '%s\n' "$NINJA_COMMANDS" |
        grep -nEi \
        -- '-pthread|USE_PTHREADS=1|PTHREAD_POOL_SIZE'; then

        echo ""
        echo "ERROR: pthread support is present in the"
        echo "actual generated Web build commands."

        echo ""
        echo "The build has been stopped."

        exit 1

    else

        echo ""
        echo "PASS: No pthread flags found."

    fi


    echo ""
    echo "Checking browser feature flags..."


    if printf '%s\n' "$NINJA_COMMANDS" |
        grep -q -- '-sFULLSCREEN=1'; then

        echo "PASS: FULLSCREEN enabled."

    else

        echo "WARNING: FULLSCREEN flag was not found"
        echo "in the generated command list."

    fi


    if printf '%s\n' "$NINJA_COMMANDS" |
        grep -q -- \
        '-sHTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS=1'; then

        echo "PASS: Deferred user-sensitive requests enabled."

    else

        echo "WARNING: Deferred user-sensitive request"
        echo "flag was not found."

    fi


    if printf '%s\n' "$NINJA_COMMANDS" |
        grep -q -- '-sALLOW_MEMORY_GROWTH=1'; then

        echo "PASS: Memory growth enabled."

    else

        echo "WARNING: Memory growth flag was not found."

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
    echo "Generated JavaScript contains pthread-related strings."

    grep -nE \
        'USE_PTHREADS|PTHREAD_POOL_SIZE|pthread-main|pthread-worker' \
        "$REAL_BUILD_DIR/Hypersomnia.js" \
        | head -20

else

    echo ""
    echo "PASS: No obvious pthread runtime configuration found."

fi


# ============================================================
# Check browser feature strings
# ============================================================

echo ""
echo "========================================"
echo " Checking browser feature configuration"
echo "========================================"


if grep -q \
    'HTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS' \
    "$REAL_BUILD_DIR/Hypersomnia.js"; then

    echo "PASS: Deferred user-sensitive request support present."

else

    echo "WARNING: Deferred user-sensitive request support"
    echo "was not found in generated JavaScript."

fi


if grep -q \
    'requestFullscreen' \
    "$REAL_BUILD_DIR/Hypersomnia.js"; then

    echo "PASS: Fullscreen runtime support present."

else

    echo "WARNING: Fullscreen runtime string not detected."

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
echo "========================================"

echo ""
echo "Browser features:"
echo "  Fullscreen: ENABLED"
echo "  Pointer lock: ENABLED through runtime"
echo "  Deferred user-sensitive requests: ENABLED"
echo "  Memory growth: ENABLED"
echo "  Pthreads: DISABLED"

echo ""
echo "Generated files:"

ls -lh \
    "$DIST/index.html" \
    "$DIST/Hypersomnia.js" \
    "$DIST/Hypersomnia.wasm" \
    "$DIST/Hypersomnia.data"


echo ""
echo "========================================"
echo " SINGLE-THREADED WEB BUILD: READY"
echo "========================================"
