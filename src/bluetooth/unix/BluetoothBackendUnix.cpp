#include "../BluetoothBackend.h"
#include "../BluetoothInternal.h"

#include <cstdlib>

static ble_status_t ble_not_implemented_status() {
    return BLE_STATUS_ERROR;
}


ble_device_manager_t* ble_backend_device_manager_create() {
    return static_cast<ble_device_manager_t*>(std::calloc(1, sizeof(ble_device_manager_t)));
}

void ble_backend_device_manager_destroy(ble_device_manager_t* manager) {
    std::free(manager);
}

ble_status_t ble_backend_device_manager_start_scan(
    ble_device_manager_t* manager,
    ble_on_device_found_cb on_device_found,
    void* user_data
) {
    (void)manager;
    (void)on_device_found;
    (void)user_data;
    return ble_not_implemented_status();
}

void ble_backend_device_manager_stop_scan(ble_device_manager_t* manager) {
    (void)manager;
}

ble_status_t ble_backend_device_manager_scan_for(
    ble_device_manager_t* manager,
    int duration_seconds,
    ble_on_device_found_cb on_device_found,
    void* user_data
) {
    (void)manager;
    (void)duration_seconds;
    (void)on_device_found;
    (void)user_data;
    return ble_not_implemented_status();
}

size_t ble_backend_device_manager_get_device_count(const ble_device_manager_t* manager) {
    (void)manager;
    return 0;
}

ble_device_t* ble_backend_device_manager_get_device(const ble_device_manager_t* manager, size_t index) {
    (void)manager;
    (void)index;
    return nullptr;
}

const char* ble_backend_device_get_identifier(const ble_device_t* device) {
    return device != nullptr ? device->identifier : nullptr;
}

const char* ble_backend_device_get_name(const ble_device_t* device) {
    return device != nullptr ? device->name : nullptr;
}

ble_status_t ble_backend_device_connect(ble_device_t* device) {
    (void)device;
    return ble_not_implemented_status();
}

void ble_backend_device_disconnect(ble_device_t* device) {
    (void)device;
}

bool ble_backend_device_is_connected(const ble_device_t* device) {
    return device != nullptr && device->is_connected;
}

void ble_backend_device_set_disconnect_callback(
    ble_device_t* device,
    ble_on_device_disconnect_cb on_disconnect,
    void* user_data
) {
    if (device == nullptr) {
        return;
    }

    device->on_disconnect = on_disconnect;
    device->disconnect_user_data = user_data;
}

size_t ble_backend_device_get_service_count(const ble_device_t* device) {
    (void)device;
    return 0;
}

const ble_service_t* ble_backend_device_get_service(const ble_device_t* device, size_t index) {
    (void)device;
    (void)index;
    return nullptr;
}

const char* ble_backend_service_get_uuid(const ble_service_t* service) {
    return service != nullptr ? service->uuid : nullptr;
}

size_t ble_backend_service_get_characteristic_count(const ble_service_t* service) {
    (void)service;
    return 0;
}

const ble_characteristic_t* ble_backend_service_get_characteristic(
    const ble_service_t* service,
    size_t index
) {
    (void)service;
    (void)index;
    return nullptr;
}

const char* ble_backend_characteristic_get_uuid(const ble_characteristic_t* characteristic) {
    return characteristic != nullptr ? characteristic->uuid : nullptr;
}

ble_status_t ble_backend_characteristic_subscribe(
    ble_device_t* device,
    const ble_characteristic_t* characteristic,
    ble_on_characteristic_notification_cb on_notification,
    void* user_data
) {
    (void)device;
    (void)characteristic;
    (void)on_notification;
    (void)user_data;
    return ble_not_implemented_status();
}

ble_status_t ble_backend_characteristic_unsubscribe(
    ble_device_t* device,
    const ble_characteristic_t* characteristic
) {
    (void)device;
    (void)characteristic;
    return ble_not_implemented_status();
}


