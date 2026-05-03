cmake_minimum_required(VERSION 3.10)

project(xelishashv3 C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_EXTENSIONS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

add_subdirectory(BLAKE3/c)

set(SOURCES
  ChaCha20-SIMD/chacha20.c
  ChaCha20-SIMD/chacha20_sse2.c
  ChaCha20-SIMD/chacha20_avx2.c
  ChaCha20-SIMD/chacha20_dispatch.c
  ChaCha20-SIMD/cpu_features.c
  xelis_hash_v3.c
  xelishashv3_wrapper.c
)

if(NOT MSVC)
  set_source_files_properties(ChaCha20-SIMD/chacha20_sse2.c PROPERTIES COMPILE_FLAGS "-msse2")
  set_source_files_properties(ChaCha20-SIMD/chacha20_avx2.c PROPERTIES COMPILE_FLAGS "-mavx2")
endif()

add_library(xelishashv3 SHARED ${SOURCES})

target_include_directories(xelishashv3 PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/ChaCha20-SIMD
  ${CMAKE_CURRENT_SOURCE_DIR}/BLAKE3/c
)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(xelishashv3 PRIVATE -O3 -fPIC)

  if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|i[3-6]86")
    target_compile_options(xelishashv3 PRIVATE -maes -mpclmul)
  endif()
elseif(MSVC)
  target_compile_options(xelishashv3 PRIVATE /O2)
endif()

if(UNIX AND NOT APPLE)
  target_link_libraries(xelishashv3 PRIVATE blake3 pthread m)
else()
  target_link_libraries(xelishashv3 PRIVATE blake3)
endif()

set_target_properties(xelishashv3 PROPERTIES
  OUTPUT_NAME "xelishashv3"
)
