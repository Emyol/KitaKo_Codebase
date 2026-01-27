# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "kitako_ffi")
project(${PROJECT_NAME} LANGUAGES C CXX)

# C++14 is required for hnswlib
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Source files
set(PLUGIN_SOURCES
  "../src/kitako_ffi.c"
  "../src/kitako_ann.cpp"
)

# Define the plugin library target
add_library(${PROJECT_NAME} SHARED ${PLUGIN_SOURCES})

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/hnswlib"
)

# Apply standard settings for Windows plugins
set_target_properties(${PROJECT_NAME} PROPERTIES
  OUTPUT_NAME "kitako_ffi"
)

# Windows-specific definitions
target_compile_definitions(${PROJECT_NAME} PRIVATE
  DART_SHARED_LIB
  _CRT_SECURE_NO_WARNINGS
)

# List of absolute paths to libraries that should be bundled with the plugin.
# This is used by the Flutter tooling to know what to copy to the app bundle.
set(kitako_ffi_bundled_libraries
  "$<TARGET_FILE:${PROJECT_NAME}>"
  PARENT_SCOPE
)
