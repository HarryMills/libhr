#include <iostream>
#include <chrono>
#include <thread>
#include <memory>
#include <iomanip>

#include "BluetoothCpp.hpp"

int main() {
    std::cout << "=== Bluetooth Device Scanner ===" << std::endl;
    std::cout << "Creating device manager..." << std::endl;

    // Create device manager
    libhr::BluetoothDeviceManager manager;

    // Start scanning
    std::cout << "Starting scan for Bluetooth devices..." << std::endl;
    std::cout << "Device Count: 0 (scanning...)" << std::endl;

    int device_count = 0;
    auto scan_status = manager.scan_for(15, [&](std::shared_ptr<libhr::BluetoothDevice> device) {
        device_count++;
        std::cout << "\r" << std::string(50, ' ') << "\r";
        std::cout << "Device Count: " << device_count << std::flush;
    });

    if (scan_status != BLE_STATUS_OK) {
        std::cerr << "Failed to scan (status: " << scan_status << ")" << std::endl;
        return 1;
    }

    std::cout << "\n\nScan complete. Discovered " << device_count << " device(s)\n" << std::endl;

    // Display detailed information about each device
    auto devices = manager.get_devices();
    for (size_t i = 0; i < devices.size(); ++i) {
        auto device = devices[i];
        std::cout << "[" << (i + 1) << "] " << device->get_name() << std::endl;
        std::cout << "    ID: " << device->get_identifier() << std::endl;
        std::cout << "    Connected: " << (device->is_connected() ? "Yes" : "No") << std::endl;

        // List services
        auto services = device->get_services();
        if (!device->is_connected()) {
            std::cout << "    Services (advertised): " << services.size() << std::endl;
        } else {
            std::cout << "    Services: " << services.size() << std::endl;
        }
        for (size_t s = 0; s < services.size() && s < 5; ++s) {
            auto service = services[s];
            std::cout << "      - " << service.get_uuid() << std::endl;

            // List characteristics
            auto characteristics = service.get_characteristics();
            std::cout << "        Characteristics: " << characteristics.size() << std::endl;
            for (size_t c = 0; c < characteristics.size() && c < 3; ++c) {
                std::cout << "          - " << characteristics[c].get_uuid() << std::endl;
            }
            if (characteristics.size() > 3) {
                std::cout << "          ... and " << (characteristics.size() - 3) << " more"
                          << std::endl;
            }
        }
        if (services.size() > 5) {
            std::cout << "      ... and " << (services.size() - 5) << " more services" << std::endl;
        }
        std::cout << std::endl;
    }

    return 0;
}
