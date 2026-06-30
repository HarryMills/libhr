# Heart Rate Monitor library
add_library(heart_rate_lib STATIC
    HeartRate.cpp
)

target_include_directories(heart_rate_lib PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

# Link against the libhr::bluetooth library
target_link_libraries(heart_rate_lib PUBLIC
    libhr::bluetooth
)
