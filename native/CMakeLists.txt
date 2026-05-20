cmake_minimum_required(VERSION 3.22.1)
project(murmur_whisper CXX)

# ── whisper.cpp submodule ──────────────────────────────────────────────────
# Disable everything we don't need to keep the build fast.
set(WHISPER_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER   OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS      OFF CACHE BOOL "" FORCE) # Build whisper as static

add_subdirectory(whisper_cpp)

# ── Our bridge shared library ──────────────────────────────────────────────
# Named "murmur_bridge" → produces libmurmur_bridge.so.
# Cannot reuse the name "whisper" — whisper.cpp's add_subdirectory already
# registers a static target with that name.
add_library(murmur_bridge SHARED
    ${CMAKE_CURRENT_SOURCE_DIR}/whisper_bridge.cpp
)

target_include_directories(murmur_bridge PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}          # whisper_bridge.h
    ${CMAKE_CURRENT_SOURCE_DIR}/whisper_cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/whisper_cpp/include
)

target_compile_options(murmur_bridge PRIVATE
    -O3
    -march=armv8-a+simd   # Enable NEON SIMD on arm64
    -fvisibility=hidden
)

target_link_libraries(murmur_bridge PRIVATE
    whisper                # whisper.cpp static lib from add_subdirectory above
    android
    log
)

# ── Developer build instructions ──────────────────────────────────────────
# Run from the repo root (requires Android NDK):
#
#   cmake -B build/android-arm64 \
#     -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
#     -DANDROID_ABI=arm64-v8a \
#     -DANDROID_PLATFORM=android-21 \
#     -DCMAKE_BUILD_TYPE=Release \
#     native/
#   cmake --build build/android-arm64 --target murmur_bridge -j$(nproc)
#   cp build/android-arm64/libmurmur_bridge.so android/app/src/main/jniLibs/arm64-v8a/
