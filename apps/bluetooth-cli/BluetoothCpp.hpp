#pragma once

#include <libhr/Bluetooth.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace libhr {

class BluetoothCharacteristic;
class BluetoothService;
class BluetoothDevice;

using DeviceFoundCallback = std::function<void(std::shared_ptr<BluetoothDevice>)>;
using DeviceDisconnectCallback = std::function<void(std::shared_ptr<BluetoothDevice>)>;
using NotificationCallback = std::function<void(const std::vector<uint8_t>&)>;

class BluetoothCharacteristic {
public:
    explicit BluetoothCharacteristic(const ble_characteristic_t* c_char)
        : c_characteristic(c_char) {}

    std::string get_uuid() const {
        const char* uuid = ble_characteristic_get_uuid(c_characteristic);
        return uuid ? std::string(uuid) : "";
    }

private:
    const ble_characteristic_t* c_characteristic;

    friend class BluetoothService;
    friend class BluetoothDevice;
};

class BluetoothService {
public:
    explicit BluetoothService(const ble_service_t* c_svc)
        : c_service(c_svc) {}

    std::string get_uuid() const {
        const char* uuid = ble_service_get_uuid(c_service);
        return uuid ? std::string(uuid) : "";
    }

    std::vector<BluetoothCharacteristic> get_characteristics() const {
        std::vector<BluetoothCharacteristic> chars;
        size_t count = ble_service_get_characteristic_count(c_service);
        for (size_t i = 0; i < count; ++i) {
            const ble_characteristic_t* c_char = ble_service_get_characteristic(c_service, i);
            if (c_char) {
                chars.emplace_back(c_char);
            }
        }
        return chars;
    }

private:
    const ble_service_t* c_service;

    friend class BluetoothDevice;
};

class BluetoothDevice {
public:
    explicit BluetoothDevice(ble_device_t* c_dev)
        : c_device(c_dev) {}

    std::string get_identifier() const {
        const char* id = ble_device_get_identifier(c_device);
        return id ? std::string(id) : "";
    }

    std::string get_name() const {
        const char* name = ble_device_get_name(c_device);
        return name ? std::string(name) : "";
    }

    ble_status_t connect() {
        return ble_device_connect(c_device);
    }

    void disconnect() {
        ble_device_disconnect(c_device);
    }

    bool is_connected() const {
        return ble_device_is_connected(c_device);
    }

    void set_disconnect_callback(DeviceDisconnectCallback callback) {
        disconnect_callback = callback;
        if (callback) {
            ble_device_set_disconnect_callback(
                c_device,
                [](ble_device_t* dev, void* user_data) {
                    auto* self = static_cast<BluetoothDevice*>(user_data);
                    if (self->disconnect_callback) {
                        auto device = std::make_shared<BluetoothDevice>(dev);
                        self->disconnect_callback(device);
                    }
                },
                this
            );
        }
    }

    std::vector<BluetoothService> get_services() const {
        std::vector<BluetoothService> services;
        size_t count = ble_device_get_service_count(c_device);
        for (size_t i = 0; i < count; ++i) {
            const ble_service_t* c_svc = ble_device_get_service(c_device, i);
            if (c_svc) {
                services.emplace_back(c_svc);
            }
        }
        return services;
    }

    ble_status_t subscribe_to_characteristic(
        const BluetoothCharacteristic& characteristic,
        NotificationCallback callback
    ) {
        notification_callback = callback;
        if (callback) {
            return ble_characteristic_subscribe(
                c_device,
                characteristic.c_characteristic,
                [](ble_device_t* dev, const ble_characteristic_t* c_char,
                   const uint8_t* data, size_t data_len, void* user_data) {
                    auto* self = static_cast<BluetoothDevice*>(user_data);
                    if (self->notification_callback && data) {
                        std::vector<uint8_t> vec(data, data + data_len);
                        self->notification_callback(vec);
                    }
                },
                this
            );
        }
        return BLE_STATUS_INVALID_ARGUMENT;
    }

    ble_status_t unsubscribe_from_characteristic(const BluetoothCharacteristic& characteristic) {
        return ble_characteristic_unsubscribe(c_device, characteristic.c_characteristic);
    }

private:
    ble_device_t* c_device;
    DeviceDisconnectCallback disconnect_callback;
    NotificationCallback notification_callback;

    friend class BluetoothDeviceManager;
};

class BluetoothDeviceManager {
public:
    BluetoothDeviceManager() {
        c_manager = ble_device_manager_create();
    }

    ~BluetoothDeviceManager() {
        if (c_manager) {
            ble_device_manager_destroy(c_manager);
        }
    }

    BluetoothDeviceManager(const BluetoothDeviceManager&) = delete;
    BluetoothDeviceManager& operator=(const BluetoothDeviceManager&) = delete;

    ble_status_t start_scan(DeviceFoundCallback on_device_found) {
        device_found_callback = on_device_found;
        return ble_device_manager_start_scan(
            c_manager,
            [](ble_device_t* c_dev, void* user_data) {
                auto* self = static_cast<BluetoothDeviceManager*>(user_data);
                if (self->device_found_callback) {
                    auto device = std::make_shared<BluetoothDevice>(c_dev);
                    self->device_found_callback(device);
                }
            },
            this
        );
    }

    void stop_scan() {
        ble_device_manager_stop_scan(c_manager);
    }

    ble_status_t scan_for(int duration_seconds, DeviceFoundCallback on_device_found) {
        device_found_callback = on_device_found;
        return ble_device_manager_scan_for(
            c_manager,
            duration_seconds,
            [](ble_device_t* c_dev, void* user_data) {
                auto* self = static_cast<BluetoothDeviceManager*>(user_data);
                if (self->device_found_callback) {
                    auto device = std::make_shared<BluetoothDevice>(c_dev);
                    self->device_found_callback(device);
                }
            },
            this
        );
    }

    std::vector<std::shared_ptr<BluetoothDevice>> get_devices() {
        std::vector<std::shared_ptr<BluetoothDevice>> devices;
        size_t count = ble_device_manager_get_device_count(c_manager);
        for (size_t i = 0; i < count; ++i) {
            ble_device_t* c_dev = ble_device_manager_get_device(c_manager, i);
            if (c_dev) {
                devices.push_back(std::make_shared<BluetoothDevice>(c_dev));
            }
        }
        return devices;
    }

private:
    ble_device_manager_t* c_manager = nullptr;
    DeviceFoundCallback device_found_callback;
};

}  // namespace libhr

