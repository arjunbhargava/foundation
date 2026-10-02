# The C and C++ build. CMakePresets.json configures it for each check; the
# shared `mise run` commands (lint:cpp, test:cpp) run those presets.
cmake_minimum_required(VERSION 3.25...4.4)
project(foundation LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# The presets make these warnings errors, for development builds only.
add_compile_options(-Wall -Wextra -Wpedantic -Wconversion -Wshadow)

# Point clang-tidy at the compiler's C++ standard library. Left alone, on
# Linux it reads the newest GCC's, which may differ from the compiler's or lack
# its headers. On macOS it finds no SDK, because CMake 4 passes none and Apple
# Clang finds its own.
if(CMAKE_CXX_CLANG_TIDY AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  execute_process(
    COMMAND ${CMAKE_CXX_COMPILER} -print-libgcc-file-name
    OUTPUT_VARIABLE libgcc_path OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY)
  cmake_path(GET libgcc_path PARENT_PATH gcc_install_dir)
  list(APPEND CMAKE_CXX_CLANG_TIDY
       "--extra-arg=--gcc-install-dir=${gcc_install_dir}")
elseif(CMAKE_CXX_CLANG_TIDY AND APPLE)
  execute_process(
    COMMAND xcrun --show-sdk-path
    OUTPUT_VARIABLE sdk_path OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY)
  list(APPEND CMAKE_CXX_CLANG_TIDY "--extra-arg=-isysroot${sdk_path}")
endif()

add_library(interpolation cpp/src/interpolation.cpp)
target_include_directories(interpolation PUBLIC cpp/include PRIVATE cpp/src/private)

enable_testing()
add_executable(interpolation_test cpp/tests/interpolation_test.cpp)
target_link_libraries(interpolation_test PRIVATE interpolation)
add_test(NAME interpolant_is_the_chord_between_neighbouring_samples
         COMMAND interpolation_test)
