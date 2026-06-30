#include <iostream>
#include <chrono>
#include <thread>
#include <memory>
#include <iomanip>
#include <algorithm>
#include <atomic>
#include <csignal>
#include <cctype>
#include <ctime>
#include <mutex>
#include <optional>

#include "BluetoothCpp.hpp"

namespace {

constexpr const char* kHeartRateServiceUuid = "180D";
constexpr const char* kHeartRateMeasurementCharacteristicUuid = "2A37";

std::atomic<bool> g_keep_running = true;
std::mutex g_print_mutex;

void handle_signal(int) {
    g_keep_running = false;
}

std::string normalize_uuid(const std::string& uuid) {
    std::string normalized;
    normalized.reserve(uuid.size());
    for (const unsigned char ch : uuid) {
        if (ch == '-') {
            continue;
        }
        normalized.push_back(static_cast<char>(std::toupper(ch)));
    }
    return normalized;
}

bool uuid_matches_short(const std::string& uuid, const std::string& short_uuid) {
    const std::string normalized = normalize_uuid(uuid);
    const std::string short_normalized = normalize_uuid(short_uuid);

    if (normalized == short_normalized) {
        return true;
    }

    static const std::string bluetooth_base_suffix = "00001000800000805F9B34FB";
    const std::string expanded_prefix = "0000" + short_normalized;
    return normalized.size() == 32 && normalized.rfind(expanded_prefix, 0) == 0 &&
           normalized.substr(8) == bluetooth_base_suffix;
}

int parse_heart_rate_bpm(const std::vector<uint8_t>& data) {
    if (data.size() < 2) {
        return -1;
    }

    const bool is_16_bit = (data[0] & 0x01) != 0;
    if (is_16_bit) {
        if (data.size() < 3) {
            return -1;
        }
        return static_cast<int>(data[1]) | (static_cast<int>(data[2]) << 8);
    }

    return static_cast<int>(data[1]);
}

std::string now_time_string() {
    const std::time_t now = std::time(nullptr);
    std::tm local_time = *std::localtime(&now);
    char buffer[32] = {};
    std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &local_time);
    return buffer;
}

}  // namespace

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

    // Display discovered devices and any advertised services.
    auto devices = manager.get_devices();
    for (size_t i = 0; i < devices.size(); ++i) {
        const auto& device = devices[i];
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

    if (devices.empty()) {
        std::cerr << "No devices discovered." << std::endl;
        return 1;
    }

    std::cout << "Searching for a device with Heart Rate Measurement (2A37)..." << std::endl;

    std::vector<std::shared_ptr<libhr::BluetoothDevice>> ordered_devices = devices;
    std::stable_sort(
        ordered_devices.begin(),
        ordered_devices.end(),
        [](const std::shared_ptr<libhr::BluetoothDevice>& lhs,
           const std::shared_ptr<libhr::BluetoothDevice>& rhs) {
            auto lhs_services = lhs->get_services();
            auto rhs_services = rhs->get_services();

            const bool lhs_advertises_hr = std::any_of(
                lhs_services.begin(), lhs_services.end(),
                [](const libhr::BluetoothService& service) {
                    return uuid_matches_short(service.get_uuid(), kHeartRateServiceUuid);
                }
            );
            const bool rhs_advertises_hr = std::any_of(
                rhs_services.begin(), rhs_services.end(),
                [](const libhr::BluetoothService& service) {
                    return uuid_matches_short(service.get_uuid(), kHeartRateServiceUuid);
                }
            );

            return lhs_advertises_hr && !rhs_advertises_hr;
        }
    );

    std::shared_ptr<libhr::BluetoothDevice> selected_device;
    std::optional<libhr::BluetoothCharacteristic> heart_rate_characteristic;

    for (const auto& device : ordered_devices) {
        std::cout << "Trying device: " << device->get_name() << " (" << device->get_identifier() << ")" << std::endl;
        auto connect_status = device->connect();
        if (connect_status != BLE_STATUS_OK) {
            std::cout << "  - Connect failed (status: " << connect_status << ")" << std::endl;
            continue;
        }

        auto services = device->get_services();
        bool found = false;
        for (const auto& service : services) {
            if (!uuid_matches_short(service.get_uuid(), kHeartRateServiceUuid)) {
                continue;
            }

            auto characteristics = service.get_characteristics();
            for (const auto& characteristic : characteristics) {
                if (uuid_matches_short(characteristic.get_uuid(), kHeartRateMeasurementCharacteristicUuid)) {
                    selected_device = device;
                    heart_rate_characteristic = characteristic;
                    found = true;
                    break;
                }
            }
            if (found) {
                break;
            }
        }

        if (found) {
            break;
        }

        std::cout << "  - No heart rate measurement characteristic found." << std::endl;
        device->disconnect();
    }

    if (!selected_device || !heart_rate_characteristic.has_value()) {
        std::cerr << "No connectable device exposed Heart Rate Measurement (2A37)." << std::endl;
        return 1;
    }

    std::cout << "\nConnected to: " << selected_device->get_name() << " ("
              << selected_device->get_identifier() << ")" << std::endl;

    auto subscribe_status = selected_device->subscribe_to_characteristic(
        *heart_rate_characteristic,
        [](const std::vector<uint8_t>& data) {
            const int bpm = parse_heart_rate_bpm(data);
            if (bpm <= 0) {
                return;
            }

            std::lock_guard<std::mutex> lock(g_print_mutex);
            std::cout << "[" << now_time_string() << "] Heart Rate: " << bpm << " BPM" << std::endl;
        }
    );

    if (subscribe_status != BLE_STATUS_OK) {
        std::cerr << "Failed to subscribe to heart rate characteristic (status: "
                  << subscribe_status << ")" << std::endl;
        selected_device->disconnect();
        return 1;
    }

    std::cout << "Subscribed to Heart Rate Measurement (2A37). Press Ctrl+C to stop." << std::endl;
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    while (g_keep_running && selected_device->is_connected()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    selected_device->unsubscribe_from_characteristic(*heart_rate_characteristic);
    selected_device->disconnect();

    return 0;
}
