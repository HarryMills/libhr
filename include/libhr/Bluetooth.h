#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ble_device_manager ble_device_manager_t;
typedef struct ble_device ble_device_t;
typedef struct ble_service ble_service_t;
typedef struct ble_characteristic ble_characteristic_t;

typedef enum ble_status {
    BLE_STATUS_OK = 0,
    BLE_STATUS_INVALID_ARGUMENT = 1,
    BLE_STATUS_NOT_FOUND = 2,
    BLE_STATUS_NOT_CONNECTED = 3,
    BLE_STATUS_ALREADY_SUBSCRIBED = 4,
    BLE_STATUS_ERROR = 255
} ble_status_t;

typedef void (*ble_on_device_found_cb)(ble_device_t* device, void* user_data);
typedef void (*ble_on_device_disconnect_cb)(ble_device_t* device, void* user_data);
typedef void (*ble_on_characteristic_notification_cb)(
    ble_device_t* device,
    const ble_characteristic_t* characteristic,
    const uint8_t* data,
    size_t data_len,
    void* user_data
);

// Device manager lifecycle and scanning.
ble_device_manager_t* ble_device_manager_create(void);
void ble_device_manager_destroy(ble_device_manager_t* manager);

ble_status_t ble_device_manager_start_scan(
    ble_device_manager_t* manager,
    ble_on_device_found_cb on_device_found,
    void* user_data
);
void ble_device_manager_stop_scan(ble_device_manager_t* manager);

// Convenience function: scan for a specific duration (in seconds)
// This handles run loop pumping internally on platforms that need it
ble_status_t ble_device_manager_scan_for(
    ble_device_manager_t* manager,
    int duration_seconds,
    ble_on_device_found_cb on_device_found,
    void* user_data
);

size_t ble_device_manager_get_device_count(const ble_device_manager_t* manager);
ble_device_t* ble_device_manager_get_device(const ble_device_manager_t* manager, size_t index);

// Device connection and metadata.
const char* ble_device_get_identifier(const ble_device_t* device);
const char* ble_device_get_name(const ble_device_t* device);

ble_status_t ble_device_connect(ble_device_t* device);
void ble_device_disconnect(ble_device_t* device);
bool ble_device_is_connected(const ble_device_t* device);

void ble_device_set_disconnect_callback(
    ble_device_t* device,
    ble_on_device_disconnect_cb on_disconnect,
    void* user_data
);

// Services and characteristics discovery.
size_t ble_device_get_service_count(const ble_device_t* device);
const ble_service_t* ble_device_get_service(const ble_device_t* device, size_t index);
const char* ble_service_get_uuid(const ble_service_t* service);

size_t ble_service_get_characteristic_count(const ble_service_t* service);
const ble_characteristic_t* ble_service_get_characteristic(
    const ble_service_t* service,
    size_t index
);
const char* ble_characteristic_get_uuid(const ble_characteristic_t* characteristic);

// Notifications (subscribe/unsubscribe).
ble_status_t ble_characteristic_subscribe(
    ble_device_t* device,
    const ble_characteristic_t* characteristic,
    ble_on_characteristic_notification_cb on_notification,
    void* user_data
);

ble_status_t ble_characteristic_unsubscribe(
    ble_device_t* device,
    const ble_characteristic_t* characteristic
);

#ifdef __cplusplus
}
#endif

