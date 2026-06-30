#pragma once

#include <libhr/Bluetooth.h>

struct ble_device_manager {
    void* backend_state;
};

struct ble_device {
    const char* identifier;
    const char* name;
    bool is_connected;
    ble_on_device_disconnect_cb on_disconnect;
    void* disconnect_user_data;
    void* backend_state;
};

struct ble_service {
    const char* uuid;
    void* backend_state;
};

struct ble_characteristic {
    const char* uuid;
    void* backend_state;
};

