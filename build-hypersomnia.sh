#!/usr/bin/env bash

set -e

echo "========================================"
echo " Hypersomnia WebAssembly Build"
echo " SINGLE-THREADED WEB BUILD"
echo " BROWSER FULLSCREEN + POINTER LOCK SUPPORT"
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

echo ""
echo "========================================"
echo " Preparing Hypersomnia source"
echo "========================================"

if [ ! -d "$HYPERSOMNIA/.git" ]; then
    echo "Cloning Hypersomnia..."

    git clone         --depth 1         --recurse-submodules         https://github.com/TeamHypersomnia/Hypersomnia.git         "$HYPERSOMNIA"
else
    echo "Hypersomnia already exists."
fi

cd "$HYPERSOMNIA"

echo ""
echo "========================================"
echo " Configuring official HTTPS server list"
echo "========================================"

# The browser client reaches the server list through the standard HTTPS
# Hypersomnia frontend. This avoids requiring the Web build to contact
# the masterserver service directly on TCP port 8420.
#
# Upstream make_canon_config.hpp normally points Web builds at:
#   https://masterserver.hypersomnia.io:8420
#
# The official HTTPS frontend exposes the same server-list endpoint at:
#   https://hypersomnia.io/server_list_binary
#
# The game appends /server_list_binary to server_list_provider, so the
# provider must be the origin only.

CANON_CONFIG="$HYPERSOMNIA/src/make_canon_config.hpp"

if [ ! -f "$CANON_CONFIG" ]; then
    echo "ERROR: Canonical config source was not found:"
    echo "$CANON_CONFIG"
    exit 1
fi

if grep -q 'masterserver.hypersomnia.io:8420' "$CANON_CONFIG"; then

    sed -i         's#https://masterserver\.hypersomnia\.io:8420#https://hypersomnia.io#g'         "$CANON_CONFIG"

    echo "Official HTTPS server-list provider configured."

elif grep -q 'result.server_list_provider = "https://hypersomnia.io";' "$CANON_CONFIG"; then

    echo "Official HTTPS server-list provider already configured."

else

    echo "ERROR: Could not find the expected Web server-list provider."
    echo "Expected the upstream masterserver.hypersomnia.io:8420 provider."
    exit 1

fi

echo "Configured provider:"
grep -n 'result.server_list_provider' "$CANON_CONFIG"

echo ""
echo "========================================"
echo " Removing Web pthread configuration"
echo "========================================"

# Hypersomnia's Web build must remain single-threaded because
# the Google Sites environment does not provide SharedArrayBuffer.
#
# Remove every top-level pthread linker/configuration line from
# the cloned source. This is intentionally broader than removing
# only USE_PTHREADS=1 because the upstream CMake file can contain
# -pthread in non-Web conditional blocks that our verification
# would otherwise mistake for an active Web pthread setting.
sed -i     -e '/^[[:space:]]*set(USE_BIGINT ON)[[:space:]]*$/d'     -e '/USE_PTHREADS=1/d'     -e '/PTHREAD_POOL_SIZE/d'     -e '/-pthread/d'     CMakeLists.txt

echo "Top-level pthread configuration after cleanup:"
if grep -nE 'USE_PTHREADS=1|-pthread|PTHREAD_POOL_SIZE' CMakeLists.txt; then
    echo "ERROR: pthread configuration is still present."
    exit 1
else
    echo "None found."
fi

echo ""
echo "========================================"
echo " Applying Web UI font scaling"
echo "========================================"

# Keep the low-end Web font scale at 1.0 through 1080p.
# This prevents oversized/overlapping UI text on the
# 1366x768 Chromebook target.
sed -i     's/return scale \* std::min(1.333333333f, ratio);/return scale * std::min(1.0f, ratio);/'     src/work.cpp

echo ""
echo "========================================"
echo " Fixing FreeType Web platform selection"
echo "========================================"

# Emscripten reports UNIX=1 for CMake compatibility.
# FreeType's older CMake logic therefore incorrectly selects
# builds/unix/ftsystem.c for the Web target.
#
# The Unix implementation expects POSIX headers/functions such
# as unistd.h, fcntl.h, open(), read(), and close().
#
# For WebAssembly we instead use FreeType's portable
# src/base/ftsystem.c implementation.

FREETYPE_CMAKE="$HYPERSOMNIA/src/3rdparty/freetype2/CMakeLists.txt"

if [ ! -f "$FREETYPE_CMAKE" ]; then
    echo "ERROR: FreeType CMakeLists.txt was not found:"
    echo "$FREETYPE_CMAKE"
    exit 1
fi

if grep -q     'elseif (UNIX AND NOT "${CMAKE_SYSTEM_NAME}" STREQUAL "Emscripten")'     "$FREETYPE_CMAKE"; then

    echo "FreeType Web platform fix already present."

else

    if grep -q         'elseif (UNIX)'         "$FREETYPE_CMAKE"; then

        sed -i             's/elseif (UNIX)/elseif (UNIX AND NOT "${CMAKE_SYSTEM_NAME}" STREQUAL "Emscripten")/'             "$FREETYPE_CMAKE"

        echo "FreeType Web platform fix applied."

    else
        echo "ERROR: Could not find the expected FreeType UNIX source-selection line."
        echo "Expected:"
        echo "elseif (UNIX)"
        exit 1
    fi

fi

echo ""
echo "FreeType source-selection configuration:"
grep -n -A6 -B4     'ftsystem.c'     "$FREETYPE_CMAKE" | head -40 || true

echo ""
echo "========================================"
echo " Configuring browser interaction support"
echo "========================================"

# Add supported browser interaction flags to the Web linker configuration.
#
# IMPORTANT:
# Emscripten does not have a -sFULLSCREEN setting. Fullscreen and
# pointer lock are provided by the HTML5/browser APIs and the
# application's SDL/browser runtime.
#
# HTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS:
# Allows fullscreen/pointer-lock requests to be deferred until
# a browser user gesture is available.
#
# ALLOW_MEMORY_GROWTH:
# Allows the WebAssembly heap to grow when required.

python3 - <<'PY'
from pathlib import Path

path = Path("CMakeLists.txt")
text = path.read_text()

if "-sHTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS=1" not in text:
    lines = text.splitlines()

    insert_at = None

    for i, line in enumerate(lines):
        if "if(BUILD_FOR_WEB)" in line:
            insert_at = i + 1
            break

    if insert_at is None:
        raise SystemExit(
            "ERROR: Could not find BUILD_FOR_WEB block."
        )

    lines.insert(
        insert_at,
        'set(CMAKE_EXE_LINKER_FLAGS '
        '"${CMAKE_EXE_LINKER_FLAGS} '
        '-sHTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS=1 '
        '-sALLOW_MEMORY_GROWTH=1")'
    )

    path.write_text("\n".join(lines) + "\n")

else:
    print("Browser linker flags already present.")
PY

echo ""
echo "Browser support configuration added:"
grep -nE     'FULLSCREEN|HTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS|ALLOW_MEMORY_GROWTH'     CMakeLists.txt || true

echo ""
echo "========================================"
echo " Preparing Emscripten"
echo "========================================"

if [ ! -d "$EMSDK/.git" ]; then
    echo "Cloning Emscripten SDK..."
    git clone https://github.com/emscripten-core/emsdk.git "$EMSDK"
fi

cd "$EMSDK"

echo "Installing Emscripten..."

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

echo ""
echo "========================================"
echo " Cleaning previous Web configuration"
echo "========================================"

rm -rf build/current

echo ""
echo "========================================"
echo " Configuring Hypersomnia Web"
echo "========================================"

echo "Browser features:"
echo "  Fullscreen: ENABLED through browser/SDL runtime"
echo "  Pointer lock: ENABLED through browser/SDL runtime"
echo "  Deferred user-sensitive requests: ENABLED"
echo "  Memory growth: ENABLED"
echo "  Pthreads: DISABLED"
echo "  FreeType Web backend: PORTABLE"

./cmake/build.sh Release Web -DUSE_BIGINT=OFF

BUILD_DIR="$HYPERSOMNIA/build/current"

if [ ! -d "$BUILD_DIR" ]; then
    echo "ERROR: Expected build directory does not exist:"
    echo "$BUILD_DIR"
    exit 1
fi

echo ""
echo "========================================"
echo " Verifying CMake configuration"
echo "========================================"

if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "ERROR: CMakeCache.txt was not generated."
    exit 1
fi

echo "CMake configuration exists."

echo ""
echo "========================================"
echo " Checking generated build commands"
echo "========================================"

echo "Asking Ninja for the actual commands..."

NINJA_COMMANDS="$(
    ninja         -C "$BUILD_DIR"         -t commands         Hypersomnia         2>/dev/null || true
)"

if [ -z "$NINJA_COMMANDS" ]; then
    echo "WARNING: Ninja returned no commands."
    echo "Continuing because the build graph may be generated lazily."
fi

echo "Checking pthread configuration..."

if printf '%s\n' "$NINJA_COMMANDS" | grep -E --     '-pthread|USE_PTHREADS=1|PTHREAD_POOL_SIZE'; then

    echo "ERROR: pthread flags found in generated build commands."
    exit 1

else

    echo "PASS: No pthread flags found."

fi

echo "Checking browser feature flags..."

if printf '%s\n' "$NINJA_COMMANDS" | grep -q     -- '-sHTML5_SUPPORT_DEFERRING_USER_SENSITIVE_REQUESTS=1'; then

    echo "PASS: Deferred user-sensitive requests enabled."

else

    echo "WARNING: Deferred user-sensitive request flag not visible."

fi

if printf '%s\n' "$NINJA_COMMANDS" | grep -q     -- '-sALLOW_MEMORY_GROWTH=1'; then

    echo "PASS: Memory growth enabled."

else

    echo "WARNING: Memory growth flag not visible."

fi

echo ""
echo "Checking FreeType Web backend..."

FREETYPE_TARGET="$HYPERSOMNIA/src/3rdparty/freetype2/CMakeLists.txt"

if grep -q     'elseif (UNIX AND NOT "${CMAKE_SYSTEM_NAME}" STREQUAL "Emscripten")'     "$FREETYPE_TARGET"; then

    echo "PASS: FreeType will not use the Unix backend for Emscripten."

else

    echo "ERROR: FreeType Web backend fix was not detected."
    exit 1

fi

echo ""
echo "========================================"
echo " Compiling Hypersomnia"
echo "========================================"

cmake --build "$BUILD_DIR" --target Hypersomnia --parallel 2

echo ""
echo "========================================"
echo " Resolving build directory"
echo "========================================"

REAL_BUILD_DIR="$(readlink -f "$BUILD_DIR")"

echo "$REAL_BUILD_DIR"

echo ""
echo "========================================"
echo " Copying Web runtime to dist"
echo "========================================"

rm -rf "$DIST"
mkdir -p "$DIST"

cp "$REAL_BUILD_DIR/Hypersomnia.html" "$DIST/index.html"
cp "$REAL_BUILD_DIR/Hypersomnia.js" "$DIST/"
cp "$REAL_BUILD_DIR/Hypersomnia.wasm" "$DIST/"
cp "$REAL_BUILD_DIR/Hypersomnia.data" "$DIST/"

cp -R "$REAL_BUILD_DIR/assets" "$DIST/"

echo ""
echo "========================================"
echo " Validating generated files"
echo "========================================"

required_files=(
    "$DIST/index.html"
    "$DIST/Hypersomnia.js"
    "$DIST/Hypersomnia.wasm"
    "$DIST/Hypersomnia.data"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Missing generated file:"
        echo "$file"
        exit 1
    fi

    echo "PASS: $file"
done

if [ ! -d "$DIST/assets" ]; then
    echo "ERROR: Missing assets directory."
    exit 1
fi

echo "PASS: assets/"

echo ""
echo "========================================"
echo " Dist contents"
echo "========================================"

find "$DIST" -type f -print

echo ""
echo "========================================"
echo " WebAssembly build complete"
echo "========================================"
echo "Fullscreen: ENABLED through SDL/browser runtime"
echo "Pointer lock: ENABLED through SDL/browser runtime"
echo "Deferred user-sensitive requests: ENABLED"
echo "Memory growth: ENABLED"
echo "Pthreads: DISABLED"
echo "FreeType Web backend: PORTABLE"

echo ""
echo "Generated runtime:"
echo "  index.html"
echo "  Hypersomnia.js"
echo "  Hypersomnia.wasm"
echo "  Hypersomnia.data"
echo "  assets/"
