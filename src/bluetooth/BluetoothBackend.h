#pragma once

#include <libhr/Bluetooth.h>

#ifdef __cplusplus
extern "C" {
#endif

ble_device_manager_t* ble_backend_device_manager_create(void);
void ble_backend_device_manager_destroy(ble_device_manager_t* manager);

ble_status_t ble_backend_device_manager_start_scan(
    ble_device_manager_t* manager,
    ble_on_device_found_cb on_device_found,
    void* user_data
);
void ble_backend_device_manager_stop_scan(ble_device_manager_t* manager);

ble_status_t ble_backend_device_manager_scan_for(
    ble_device_manager_t* manager,
    int duration_seconds,
    ble_on_device_found_cb on_device_found,
    void* user_data
);

size_t ble_backend_device_manager_get_device_count(const ble_device_manager_t* manager);
ble_device_t* ble_backend_device_manager_get_device(const ble_device_manager_t* manager, size_t index);

const char* ble_backend_device_get_identifier(const ble_device_t* device);
const char* ble_backend_device_get_name(const ble_device_t* device);

ble_status_t ble_backend_device_connect(ble_device_t* device);
void ble_backend_device_disconnect(ble_device_t* device);
bool ble_backend_device_is_connected(const ble_device_t* device);

void ble_backend_device_set_disconnect_callback(
    ble_device_t* device,
    ble_on_device_disconnect_cb on_disconnect,
    void* user_data
);

size_t ble_backend_device_get_service_count(const ble_device_t* device);
const ble_service_t* ble_backend_device_get_service(const ble_device_t* device, size_t index);
const char* ble_backend_service_get_uuid(const ble_service_t* service);

size_t ble_backend_service_get_characteristic_count(const ble_service_t* service);
const ble_characteristic_t* ble_backend_service_get_characteristic(
    const ble_service_t* service,
    size_t index
);
const char* ble_backend_characteristic_get_uuid(const ble_characteristic_t* characteristic);

ble_status_t ble_backend_characteristic_subscribe(
    ble_device_t* device,
    const ble_characteristic_t* characteristic,
    ble_on_characteristic_notification_cb on_notification,
    void* user_data
);

ble_status_t ble_backend_characteristic_unsubscribe(
    ble_device_t* device,
    const ble_characteristic_t* characteristic
);

#ifdef __cplusplus
}
#endif
