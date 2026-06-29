#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#include "HeartRateMonitor.h"
#include <iostream>
#include <chrono>
#include <thread>
#include <vector>

// Standard BLE Heart Rate Service UUIDs
static NSString* const HEART_RATE_SERVICE_UUID = @"180D";
static NSString* const HEART_RATE_MEASUREMENT_UUID = @"2A37";

// Objective-C delegate for CoreBluetooth
@interface BLEDelegate : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) CBPeripheral *heartRatePeripheral;
@property (nonatomic, strong) NSMutableArray<CBPeripheral*> *discoveredPeripherals;
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, copy) void (^heartRateCallback)(int bpm, NSString* timestamp);
@property (nonatomic, strong) NSString *lastError;

- (void)startScanning:(int)duration;
- (BOOL)connectToHeartRateMonitor;
- (void)disconnect;
- (NSString *)binaryStringFromByte:(uint8_t)byte;
@end

@implementation BLEDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _discoveredPeripherals = [NSMutableArray array];
        _isScanning = NO;
        _isConnected = NO;
        _lastError = @"";

        // Initialize central manager on the main queue
        dispatch_queue_t queue = dispatch_get_main_queue();
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:queue];
    }
    return self;
}

- (void)startScanning:(int)duration {
    _isScanning = YES;
    [_discoveredPeripherals removeAllObjects];

    NSLog(@"Starting BLE scan for %d seconds...", duration);

    // Scan only for heart rate service
    NSArray *serviceUUIDs = @[[CBUUID UUIDWithString:HEART_RATE_SERVICE_UUID]];
    [_centralManager scanForPeripheralsWithServices:serviceUUIDs options:nil];

    // Stop scanning after duration
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self stopScanning];
    });
}

- (void)stopScanning {
    if (_isScanning) {
        [_centralManager stopScan];
        _isScanning = NO;
        NSLog(@"Stopped scanning. Found %lu device(s)", (unsigned long)[_discoveredPeripherals count]);
    }
}

- (BOOL)connectToHeartRateMonitor {
    if ([_discoveredPeripherals count] == 0) {
        _lastError = @"No heart rate monitors found";
        return NO;
    }

    // Connect to the first discovered heart rate monitor
    _heartRatePeripheral = [_discoveredPeripherals firstObject];
    NSLog(@"Connecting to: %@", _heartRatePeripheral.name ?: @"Unknown Device");

    [_centralManager connectPeripheral:_heartRatePeripheral options:nil];

    // Wait for connection (with timeout)
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (!_isConnected && [timeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    return _isConnected;
}

- (void)disconnect {
    if (_heartRatePeripheral) {
        [_centralManager cancelPeripheralConnection:_heartRatePeripheral];
        _isConnected = NO;
    }
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    switch (central.state) {
        case CBManagerStatePoweredOn:
            NSLog(@"Bluetooth is powered on and ready");
            break;
        case CBManagerStatePoweredOff:
            NSLog(@"Bluetooth is powered off");
            _lastError = @"Bluetooth is powered off";
            break;
        case CBManagerStateUnauthorized:
            NSLog(@"Bluetooth is unauthorized");
            _lastError = @"Bluetooth is unauthorized";
            break;
        case CBManagerStateUnsupported:
            NSLog(@"Bluetooth is not supported on this device");
            _lastError = @"Bluetooth is not supported";
            break;
        default:
            NSLog(@"Bluetooth state: %ld", (long)central.state);
            break;
    }
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *,id> *)advertisementData
                  RSSI:(NSNumber *)RSSI {

    NSLog(@"Discovered: %@ (RSSI: %@)", peripheral.name ?: @"Unknown", RSSI);

    // Add to list if not already present
    if (![_discoveredPeripherals containsObject:peripheral]) {
        [_discoveredPeripherals addObject:peripheral];
    }
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"Connected to: %@", peripheral.name ?: @"Unknown Device");

    _isConnected = YES;
    peripheral.delegate = self;

    // Discover services
    NSLog(@"Discovering services...");
    [peripheral discoverServices:@[[CBUUID UUIDWithString:HEART_RATE_SERVICE_UUID]]];
}

- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    NSLog(@"Failed to connect: %@", error.localizedDescription);
    _lastError = error.localizedDescription;
    _isConnected = NO;
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    NSLog(@"Disconnected from: %@", peripheral.name ?: @"Unknown Device");
    _isConnected = NO;

    if (error) {
        NSLog(@"Disconnect error: %@", error.localizedDescription);
    }
}

#pragma mark - CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverServices:(NSError *)error {
    if (error) {
        NSLog(@"Error discovering services: %@", error.localizedDescription);
        return;
    }

    NSLog(@"Discovered %lu service(s)", (unsigned long)peripheral.services.count);

    for (CBService *service in peripheral.services) {
        NSLog(@"Service UUID: %@", service.UUID.UUIDString);

        if ([service.UUID.UUIDString isEqualToString:HEART_RATE_SERVICE_UUID]) {
            NSLog(@"Found Heart Rate Service - discovering characteristics...");
            [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:HEART_RATE_MEASUREMENT_UUID]]
                                     forService:service];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
             error:(NSError *)error {
    if (error) {
        NSLog(@"Error discovering characteristics: %@", error.localizedDescription);
        return;
    }

    NSLog(@"Discovered %lu characteristic(s) for service %@",
          (unsigned long)service.characteristics.count,
          service.UUID.UUIDString);

    for (CBCharacteristic *characteristic in service.characteristics) {
        NSLog(@"Characteristic UUID: %@", characteristic.UUID.UUIDString);

        if ([characteristic.UUID.UUIDString isEqualToString:HEART_RATE_MEASUREMENT_UUID]) {
            NSLog(@"Found Heart Rate Measurement characteristic");
            NSLog(@"Properties: %lu", (unsigned long)characteristic.properties);

            if (characteristic.properties & CBCharacteristicPropertyNotify) {
                NSLog(@"Subscribing to notifications...");
                [peripheral setNotifyValue:YES forCharacteristic:characteristic];
            } else {
                NSLog(@"Characteristic does not support notifications!");
            }
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral
didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error {
    if (error) {
        NSLog(@"Error changing notification state: %@", error.localizedDescription);
        _lastError = error.localizedDescription;
        return;
    }

    if (characteristic.isNotifying) {
        NSLog(@"✓ Successfully subscribed to heart rate notifications");
    } else {
        NSLog(@"Stopped receiving notifications");
    }
}

- (void)peripheral:(CBPeripheral *)peripheral
didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error {
    if (error) {
        NSLog(@"Error reading characteristic: %@", error.localizedDescription);
        return;
    }

    if ([characteristic.UUID.UUIDString isEqualToString:HEART_RATE_MEASUREMENT_UUID]) {
        NSData *data = characteristic.value;

        // Log that we received data
        NSLog(@"📥 Received data from heart rate characteristic");
        NSLog(@"   Data length: %lu bytes", (unsigned long)data.length);

        if (data.length > 0) {
            const uint8_t *bytes = (const uint8_t *)data.bytes;

            // Log raw hex data
            NSMutableString *hexString = [NSMutableString string];
            for (NSUInteger i = 0; i < data.length; i++) {
                [hexString appendFormat:@"%02X ", bytes[i]];
            }
            NSLog(@"   Raw hex data: %@", hexString);

            uint8_t flags = bytes[0];
            NSLog(@"   Flags byte: 0x%02X (binary: %@)", flags,
                  [self binaryStringFromByte:flags]);

            int bpm = 0;
            BOOL is16bit = (flags & 0x01) != 0;
            NSLog(@"   Heart rate format: %@", is16bit ? @"16-bit" : @"8-bit");

            if (is16bit && data.length >= 3) {
                bpm = bytes[1] | (bytes[2] << 8);
                NSLog(@"   Parsed BPM (16-bit): %d (from bytes[1]=0x%02X, bytes[2]=0x%02X)",
                      bpm, bytes[1], bytes[2]);
            } else if (!is16bit && data.length >= 2) {
                bpm = bytes[1];
                NSLog(@"   Parsed BPM (8-bit): %d (from byte[1]=0x%02X)", bpm, bytes[1]);
            } else {
                NSLog(@"   ⚠️ ERROR: Data length insufficient for parsing (need at least %d bytes, got %lu)",
                      is16bit ? 3 : 2, (unsigned long)data.length);
            }

            if (bpm > 0) {
                NSLog(@"   ✓ Valid BPM detected: %d", bpm);
                if (_heartRateCallback) {
                    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    NSString *timestamp = [formatter stringFromDate:[NSDate date]];

                    _heartRateCallback(bpm, timestamp);
                } else {
                    NSLog(@"   ⚠️ WARNING: No callback registered!");
                }
            } else {
                NSLog(@"   ⚠️ WARNING: BPM is 0 or negative");
            }
        } else {
            NSLog(@"   ⚠️ WARNING: Received empty data");
        }
    } else {
        NSLog(@"📥 Received data from other characteristic: %@", characteristic.UUID.UUIDString);
    }
}

// Helper method to convert byte to binary string representation
- (NSString *)binaryStringFromByte:(uint8_t)byte {
    NSMutableString *binary = [NSMutableString string];
    for (int i = 7; i >= 0; i--) {
        [binary appendFormat:@"%d", (byte >> i) & 1];
    }
    return binary;
}

@end

// C++ Implementation using PImpl pattern
class HeartRateMonitor::Impl {
public:
    BLEDelegate *delegate;
    HeartRateCallback callback;

    Impl() {
        delegate = [[BLEDelegate alloc] init];

        // Wait for Bluetooth to be ready
        NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while (delegate.centralManager.state != CBManagerStatePoweredOn &&
               [timeout timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    }

    ~Impl() {
        if (delegate) {
            [delegate disconnect];
        }
    }
};

// HeartRateMonitor implementation
HeartRateMonitor::HeartRateMonitor() : pImpl(std::make_unique<Impl>()) {}

HeartRateMonitor::~HeartRateMonitor() = default;

bool HeartRateMonitor::startScanning(int durationSeconds) {
    if (pImpl->delegate.centralManager.state != CBManagerStatePoweredOn) {
        std::cerr << "Bluetooth is not powered on\n";
        return false;
    }

    [pImpl->delegate startScanning:durationSeconds];

    // Run the run loop while scanning
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:durationSeconds + 1.0];
    while (pImpl->delegate.isScanning && [timeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    return [pImpl->delegate.discoveredPeripherals count] > 0;
}

bool HeartRateMonitor::connect() {
    return [pImpl->delegate connectToHeartRateMonitor];
}

void HeartRateMonitor::setHeartRateCallback(HeartRateCallback callback) {
    pImpl->callback = callback;

    // Bridge C++ callback to Objective-C block
    pImpl->delegate.heartRateCallback = ^(int bpm, NSString* timestamp) {
        if (pImpl->callback) {
            std::string ts = [timestamp UTF8String];
            pImpl->callback(bpm, ts);
        }
    };
}

bool HeartRateMonitor::isConnected() const {
    return pImpl->delegate.isConnected;
}

void HeartRateMonitor::disconnect() {
    [pImpl->delegate disconnect];
}

std::string HeartRateMonitor::getLastError() const {
    return [pImpl->delegate.lastError UTF8String];
}

void HeartRateMonitor::processEvents() {
    // Pump the run loop to process BLE events
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
