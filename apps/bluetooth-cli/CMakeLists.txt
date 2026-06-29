add_executable(
    bluetooth-cli
    main.cpp
    BluetoothCpp.hpp
)

target_link_libraries(bluetooth-cli PRIVATE libhr::bluetooth)

