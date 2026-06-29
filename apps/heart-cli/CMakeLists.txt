add_executable(
    heart-cli
    main.cpp
)

target_link_libraries(heart-cli PRIVATE heart_rate_lib)
target_include_directories(heart-cli PRIVATE ${CMAKE_SOURCE_DIR}/include)


