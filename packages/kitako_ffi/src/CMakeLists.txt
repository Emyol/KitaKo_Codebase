# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Enable C and C++ languages for hnswlib
project(kitako_ffi_library VERSION 0.0.1 LANGUAGES C CXX)

# C++14 is required for hnswlib
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Source files
set(KITAKO_FFI_SOURCES
  "kitako_ffi.c"
  "kitako_ann.cpp"
)

add_library(kitako_ffi SHARED ${KITAKO_FFI_SOURCES})

# Include directory for hnswlib headers
target_include_directories(kitako_ffi PRIVATE 
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/hnswlib
)

set_target_properties(kitako_ffi PROPERTIES
  PUBLIC_HEADER "kitako_ffi.h;kitako_ann.h"
  OUTPUT_NAME "kitako_ffi"
)

target_compile_definitions(kitako_ffi PUBLIC DART_SHARED_LIB)

# Platform-specific settings
if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(kitako_ffi PRIVATE "-Wl,-z,max-page-size=16384")
  
  # Android NDK threading support
  find_library(log-lib log)
  target_link_libraries(kitako_ffi ${log-lib})
endif()

if (APPLE)
  # macOS/iOS specific flags
  target_compile_options(kitako_ffi PRIVATE -fvisibility=default)
endif()

if (WIN32)
  # Windows specific flags
  target_compile_definitions(kitako_ffi PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

# Optimization flags for release builds
if (CMAKE_BUILD_TYPE STREQUAL "Release")
  if (NOT MSVC)
    target_compile_options(kitako_ffi PRIVATE -O3 -ffast-math)
  else()
    target_compile_options(kitako_ffi PRIVATE /O2 /fp:fast)
  endif()
endif()
