# Bluetooth Low Energy device management library (part of libhr)
add_library(libhr_bluetooth SHARED)

target_sources(libhr_bluetooth PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/Bluetooth.cpp
)

target_include_directories(libhr_bluetooth PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

target_include_directories(libhr_bluetooth PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

if(APPLE)
    target_sources(libhr_bluetooth PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/apple/BluetoothBackendApple.mm
    )
    target_compile_definitions(libhr_bluetooth PRIVATE LIBHR_BLE_BACKEND_APPLE=1)

    # Enable Objective-C++ compilation for .mm files
    set_source_files_properties(
            ${CMAKE_CURRENT_SOURCE_DIR}/apple/BluetoothBackendApple.mm
        PROPERTIES
        COMPILE_FLAGS "-x objective-c++"
    )

    # Link CoreBluetooth framework
    target_link_libraries(libhr_bluetooth PRIVATE
        "-framework Foundation"
        "-framework CoreBluetooth"
    )
elseif(WIN32)
    target_sources(libhr_bluetooth PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/windows/BluetoothBackendWindows.cpp
    )
    target_compile_definitions(libhr_bluetooth PRIVATE LIBHR_BLE_BACKEND_WINDOWS=1)
elseif(UNIX)
    target_sources(libhr_bluetooth PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/unix/BluetoothBackendUnix.cpp
    )
    target_compile_definitions(libhr_bluetooth PRIVATE LIBHR_BLE_BACKEND_UNIX=1)
else()
    message(FATAL_ERROR "No BLE backend configured for this platform")
endif()

# Public target alias as libhr::bluetooth
add_library(libhr::bluetooth ALIAS libhr_bluetooth)
