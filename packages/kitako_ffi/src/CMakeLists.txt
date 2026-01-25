# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(kitako_ffi_library VERSION 0.0.1 LANGUAGES C)

add_library(kitako_ffi SHARED
  "kitako_ffi.c"
)

set_target_properties(kitako_ffi PROPERTIES
  PUBLIC_HEADER kitako_ffi.h
  OUTPUT_NAME "kitako_ffi"
)

target_compile_definitions(kitako_ffi PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(kitako_ffi PRIVATE "-Wl,-z,max-page-size=16384")
endif()
