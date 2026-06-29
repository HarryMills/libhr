#include <iostream>
#include <thread>
#include <chrono>
#include "HeartRateMonitor.h"

int main() {
    std::cout << "Heart Rate Monitor - CoreBluetooth Edition\n";
    std::cout << "==========================================\n\n";

    // Create heart rate monitor instance
    HeartRateMonitor monitor;

    // Check for errors during initialization
    std::string error = monitor.getLastError();
    if (!error.empty()) {
        std::cerr << "Initialization error: " << error << "\n";
        return 1;
    }

    // Set up callback for heart rate updates
    monitor.setHeartRateCallback([](int bpm, const std::string& timestamp) {
        std::cout << "[" << timestamp << "] ❤️  Heart Rate: " << bpm << " BPM\n";
        std::cout.flush();
    });

    // Scan for heart rate monitors
    std::cout << "Scanning for heart rate monitors (10 seconds)...\n";
    bool found = monitor.startScanning(10);

    if (!found) {
        std::cerr << "\nNo heart rate monitors found.\n";
        std::cerr << "Make sure your heart rate monitor is:\n";
        std::cerr << "  1. Powered on\n";
        std::cerr << "  2. In pairing/advertising mode\n";
        std::cerr << "  3. Within range\n";
        std::cerr << "  4. Broadcasting the Heart Rate Service (UUID: 180D)\n";
        return 1;
    }

    std::cout << "\n✓ Found heart rate monitor(s)\n";

    // Connect to the monitor
    std::cout << "Connecting to heart rate monitor...\n";
    if (!monitor.connect()) {
        std::cerr << "Failed to connect: " << monitor.getLastError() << "\n";
        return 1;
    }

    std::cout << "✓ Connected successfully!\n";
    std::cout << "\nMonitoring heart rate (press Ctrl+C to exit)...\n";
    std::cout << "================================================\n\n";

    // Keep running and receiving heart rate updates
    while (monitor.isConnected()) {
        // Process events - this pumps the run loop to receive notifications
        monitor.processEvents();
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    std::cout << "\nDisconnected from heart rate monitor\n";
    return 0;
}
