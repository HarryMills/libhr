cmake_minimum_required(VERSION 3.24)

project(libhr
    DESCRIPTION "Heart Rate Library"
    LANGUAGES CXX C
)

if(PROJECT_SOURCE_DIR STREQUAL PROJECT_BINARY_DIR)
    message(FATAL_ERROR "In-source builds are not allowed")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Fetch SimpleBLE library
include(FetchContent)
FetchContent_Declare(
    simpleble
    GIT_REPOSITORY https://github.com/OpenBluetoothToolbox/SimpleBLE.git
    GIT_TAG v0.7.0
)
FetchContent_MakeAvailable(simpleble)

# Add the simpleble subdirectory from the fetched content
FetchContent_GetProperties(simpleble)
if(NOT simpleble_POPULATED)
    FetchContent_Populate(simpleble)
endif()

# Add simpleble subdirectory if it exists
if(EXISTS "${simpleble_SOURCE_DIR}/simpleble/CMakeLists.txt")
    add_subdirectory(${simpleble_SOURCE_DIR}/simpleble ${simpleble_BINARY_DIR}/simpleble)
endif()

add_subdirectory(src)
add_subdirectory(apps)
