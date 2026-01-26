cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "kitako_ffi")
project(${PROJECT_NAME} LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(PLUGIN_SOURCES
  "../src/kitako_ffi.c"
  "../src/kitako_ann.cpp"
)

add_library(${PROJECT_NAME} SHARED ${PLUGIN_SOURCES})

target_include_directories(${PROJECT_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/hnswlib"
)

set_target_properties(${PROJECT_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET default
  C_VISIBILITY_PRESET default
  OUTPUT_NAME "kitako_ffi"
)

target_compile_definitions(${PROJECT_NAME} PRIVATE DART_SHARED_LIB)
target_compile_options(${PROJECT_NAME} PRIVATE -fvisibility=default)
