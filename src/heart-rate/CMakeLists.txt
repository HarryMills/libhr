# Heart Rate Monitor library
add_library(heart_rate_lib STATIC
    HeartRateMonitor.mm
)

target_include_directories(heart_rate_lib PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

# Link against the libhr::bluetooth library
target_link_libraries(heart_rate_lib PUBLIC
    libhr::bluetooth
)

# Enable Objective-C++ compilation for .mm files
set_source_files_properties(HeartRateMonitor.mm PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
)

# Link CoreBluetooth framework on macOS
if(APPLE)
    target_link_libraries(heart_rate_lib PUBLIC
        "-framework Foundation"
        "-framework CoreBluetooth"
    )
endif()
