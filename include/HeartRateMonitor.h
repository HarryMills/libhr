#ifndef HEART_RATE_MONITOR_H
#define HEART_RATE_MONITOR_H

#include <string>
#include <functional>
#include <memory>

// Cross-platform heart rate monitor interface
class HeartRateMonitor {
public:
    // Callback type for heart rate updates
    using HeartRateCallback = std::function<void(int bpm, const std::string& timestamp)>;

    HeartRateMonitor();
    ~HeartRateMonitor();

    // Start scanning for heart rate monitors
    bool startScanning(int durationSeconds = 10);

    // Connect to a discovered heart rate monitor
    bool connect();

    // Set callback for heart rate updates
    void setHeartRateCallback(HeartRateCallback callback);

    // Check if connected
    bool isConnected() const;

    // Disconnect
    void disconnect();

    // Get last error message
    std::string getLastError() const;

    // Process events - must be called regularly to receive notifications
    void processEvents();

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;
};

#endif // HEART_RATE_MONITOR_H

