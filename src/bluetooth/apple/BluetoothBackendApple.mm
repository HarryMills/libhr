#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

#include "../BluetoothBackend.h"
#include "../BluetoothInternal.h"
#include <vector>
#include <map>
#include <memory>
#include <cstring>
#include <string>

// Wrapper for CoreBluetooth device
struct CBLEDevice {
    CBPeripheral* peripheral;
    ble_device_t c_device;
    std::vector<ble_service_t> services;
    std::vector<std::vector<ble_characteristic_t>> characteristics;
    std::vector<std::string> advertised_service_uuids;
    std::vector<std::string> cached_service_uuids;
    ble_on_characteristic_notification_cb on_notification_cb = nullptr;
    void* notification_user_data = nullptr;
    ble_characteristic_t notification_characteristic_cache {};
    std::string notification_characteristic_uuid;
    ble_on_device_disconnect_cb on_disconnect_cb = nullptr;
    void* disconnect_user_data = nullptr;
};

static CBLEDevice* findDeviceForPeripheral(CBPeripheral* peripheral);

// Global central manager delegate
@interface BLECentralDelegate : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) NSMutableArray<CBPeripheral*> *discoveredPeripherals;
@property (nonatomic, copy) void (^onDeviceFound)(CBPeripheral* peripheral);
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, strong) NSMutableDictionary<NSUUID*, NSNumber*> *connectedPeripherals;
@property (nonatomic, strong) NSMutableDictionary<NSUUID*, NSNumber*> *servicesDiscovered;
@property (nonatomic, strong) NSMutableDictionary<NSUUID*, NSArray<CBUUID*>*> *advertisedServiceUUIDs;

- (void)startScan:(void (^)(CBPeripheral*))callback;
- (void)stopScan;
- (BOOL)waitForConnection:(CBPeripheral*)peripheral timeout:(NSTimeInterval)timeout;
- (BOOL)waitForServices:(CBPeripheral*)peripheral timeout:(NSTimeInterval)timeout;
@end

@implementation BLECentralDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _discoveredPeripherals = [NSMutableArray array];
        _connectedPeripherals = [NSMutableDictionary dictionary];
        _servicesDiscovered = [NSMutableDictionary dictionary];
        _advertisedServiceUUIDs = [NSMutableDictionary dictionary];
        _isScanning = NO;

        // Create a dedicated dispatch queue for CoreBluetooth instead of main queue
        dispatch_queue_t bleQueue = dispatch_queue_create("com.libhr.bluetooth", DISPATCH_QUEUE_SERIAL);
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:bleQueue];
    }
    return self;
}

- (void)startScan:(void (^)(CBPeripheral*))callback {
    self.onDeviceFound = callback;
    [self.discoveredPeripherals removeAllObjects];
    [self.advertisedServiceUUIDs removeAllObjects];

    // Wait for Bluetooth to be ready (with timeout)
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while ([timeout timeIntervalSinceNow] > 0 &&
           self.centralManager.state != CBManagerStatePoweredOn &&
           self.centralManager.state != CBManagerStatePoweredOff &&
           self.centralManager.state != CBManagerStateUnsupported &&
           self.centralManager.state != CBManagerStateUnauthorized) {
        [NSThread sleepForTimeInterval:0.1];
    }

    // Check if Bluetooth is ready
    if (self.centralManager.state == CBManagerStatePoweredOn) {
        // Start scanning
        self.isScanning = YES;
        [self.centralManager scanForPeripheralsWithServices:nil options:nil];
        NSLog(@"Started BLE scan");
    } else {
        NSLog(@"Bluetooth not available (state: %ld)", (long)self.centralManager.state);
    }
}

- (void)stopScan {
    if (self.isScanning) {
        [self.centralManager stopScan];
        self.isScanning = NO;
        NSLog(@"Stopped scanning. Found %lu device(s)", (unsigned long)[self.discoveredPeripherals count]);
    }
}

- (BOOL)waitForConnection:(CBPeripheral*)peripheral timeout:(NSTimeInterval)timeout {
    NSDate* endTime = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([endTime timeIntervalSinceNow] > 0) {
        BOOL isConnected = NO;
        @synchronized(self) {
            isConnected = (self.connectedPeripherals[peripheral.identifier] != nil);
        }
        if (isConnected) {
            return YES;
        }
        [NSThread sleepForTimeInterval:0.05];
    }
    return NO;
}

- (BOOL)waitForServices:(CBPeripheral*)peripheral timeout:(NSTimeInterval)timeout {
    NSDate* endTime = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([endTime timeIntervalSinceNow] > 0) {
        BOOL servicesReady = NO;
        @synchronized(self) {
            servicesReady = (self.servicesDiscovered[peripheral.identifier] != nil);
        }
        if (servicesReady && peripheral.services.count > 0) {
            NSLog(@"Services ready: %lu services found", (unsigned long)peripheral.services.count);
            return YES;
        }
        [NSThread sleepForTimeInterval:0.05];
    }
    NSLog(@"Service discovery timed out. Peripheral services count: %lu", (unsigned long)peripheral.services.count);
    return NO;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    switch (central.state) {
        case CBManagerStatePoweredOn:
            NSLog(@"Bluetooth is powered on");
            break;
        case CBManagerStatePoweredOff:
            NSLog(@"Bluetooth is powered off");
            [self stopScan];
            break;
        case CBManagerStateResetting:
            NSLog(@"Bluetooth is resetting");
            break;
        case CBManagerStateUnauthorized:
            NSLog(@"Bluetooth is unauthorized");
            break;
        case CBManagerStateUnknown:
            NSLog(@"Bluetooth state is unknown");
            break;
        case CBManagerStateUnsupported:
            NSLog(@"Bluetooth is not supported on this device");
            break;
    }
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheralWithUUID:(NSUUID *)UUID
                 advertisementData:(NSDictionary *)advertisementData
                          RSSI:(NSNumber *)RSSI {
    // This method is called for each discovered peripheral
}

- (void)centralManager:(CBCentralManager *)central
    didDiscoverPeripheral:(CBPeripheral *)peripheral
        advertisementData:(NSDictionary<NSString *,id> *)advertisementData
                     RSSI:(NSNumber *)RSSI {
    // Avoid duplicates
    BOOL alreadyDiscovered = NO;
    for (CBPeripheral *p in self.discoveredPeripherals) {
        if ([p.identifier isEqual:peripheral.identifier]) {
            alreadyDiscovered = YES;
            break;
        }
    }

    if (!alreadyDiscovered) {
        NSArray<CBUUID*>* serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey];
        if (!serviceUUIDs) {
            serviceUUIDs = @[];
        }

        NSArray<CBUUID*>* overflowUUIDs = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey];
        if (overflowUUIDs.count > 0) {
            NSMutableArray<CBUUID*>* merged = [NSMutableArray arrayWithArray:serviceUUIDs];
            [merged addObjectsFromArray:overflowUUIDs];
            serviceUUIDs = merged;
        }

        @synchronized(self) {
            self.advertisedServiceUUIDs[peripheral.identifier] = serviceUUIDs;
        }

        NSLog(@"Discovered device: %@ (ID: %@, RSSI: %@)",
              peripheral.name ?: @"Unknown",
              peripheral.identifier.UUIDString,
              RSSI);
        [self.discoveredPeripherals addObject:peripheral];
        if (self.onDeviceFound) {
            self.onDeviceFound(peripheral);
        }
    }
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"Connected to peripheral: %@", peripheral.identifier.UUIDString);
    @synchronized(self) {
        self.connectedPeripherals[peripheral.identifier] = @YES;
    }
    peripheral.delegate = self;
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(nullable NSError *)error {
    NSLog(@"Disconnected from peripheral: %@", peripheral.identifier.UUIDString);
    @synchronized(self) {
        [self.connectedPeripherals removeObjectForKey:peripheral.identifier];
        [self.servicesDiscovered removeObjectForKey:peripheral.identifier];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverServices:(nullable NSError *)error {
    if (error) {
        NSLog(@"Error discovering services: %@", error);
        return;
    }

    NSLog(@"Discovered %lu service(s) for peripheral: %@",
          (unsigned long)[peripheral.services count],
          peripheral.identifier.UUIDString);

    @synchronized(self) {
        self.servicesDiscovered[peripheral.identifier] = @YES;
    }

    for (CBService *service in peripheral.services) {
        [peripheral discoverCharacteristics:nil forService:service];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
              error:(nullable NSError *)error {
    if (error) return;
    // Characteristics are now available
}

- (void)peripheral:(CBPeripheral *)peripheral
didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
              error:(nullable NSError *)error {
    if (error || !characteristic.value) {
        return;
    }

    CBLEDevice* ble_device = findDeviceForPeripheral(peripheral);
    if (!ble_device || !ble_device->on_notification_cb) {
        return;
    }

    NSData* value = characteristic.value;
    const uint8_t* bytes = static_cast<const uint8_t*>([value bytes]);
    size_t data_len = [value length];
    if (!bytes || data_len == 0) {
        return;
    }

    ble_device->notification_characteristic_uuid = [[characteristic.UUID UUIDString] UTF8String];
    ble_device->notification_characteristic_cache.uuid = ble_device->notification_characteristic_uuid.c_str();
    ble_device->notification_characteristic_cache.backend_state = (void*)characteristic;

    ble_device->on_notification_cb(
        &ble_device->c_device,
        &ble_device->notification_characteristic_cache,
        bytes,
        data_len,
        ble_device->notification_user_data
    );
}

@end

// Global state
static BLECentralDelegate* g_central_delegate = nullptr;
static std::map<ble_device_manager_t*, std::vector<std::shared_ptr<CBLEDevice>>> g_devices_map;
static std::map<ble_device_manager_t*, ble_on_device_found_cb> g_found_callbacks;
static std::map<ble_device_manager_t*, void*> g_found_user_data;

static CBLEDevice* findDeviceForPeripheral(CBPeripheral* peripheral) {
    if (!peripheral) {
        return nullptr;
    }

    for (auto& entry : g_devices_map) {
        for (auto& device : entry.second) {
            if (device && device->peripheral && [device->peripheral.identifier isEqual:peripheral.identifier]) {
                return device.get();
            }
        }
    }

    return nullptr;
}

// Helper to convert NSString to C string
static const char* nsstringToCString(NSString* str) {
    if (!str) return "";
    return [str UTF8String];
}

// Helper to get UUID string
static std::string getUUIDString(CBUUID* uuid) {
    return std::string([[uuid UUIDString] UTF8String]);
}

// Backend implementation
ble_device_manager_t* ble_backend_device_manager_create() {
    if (!g_central_delegate) {
        g_central_delegate = [[BLECentralDelegate alloc] init];
    }

    auto manager = static_cast<ble_device_manager_t*>(std::calloc(1, sizeof(ble_device_manager_t)));
    g_devices_map[manager] = std::vector<std::shared_ptr<CBLEDevice>>();
    return manager;
}

void ble_backend_device_manager_destroy(ble_device_manager_t* manager) {
    if (!manager) return;
    g_devices_map.erase(manager);
    g_found_callbacks.erase(manager);
    g_found_user_data.erase(manager);
    std::free(manager);
}

ble_status_t ble_backend_device_manager_start_scan(
    ble_device_manager_t* manager,
    ble_on_device_found_cb on_device_found,
    void* user_data
) {
    if (!manager || !on_device_found) {
        return BLE_STATUS_INVALID_ARGUMENT;
    }

    g_found_callbacks[manager] = on_device_found;
    g_found_user_data[manager] = user_data;

    [g_central_delegate startScan:^(CBPeripheral *peripheral) {
        auto& devices = g_devices_map[manager];

        // Create device
        auto device = std::make_shared<CBLEDevice>();
        device->peripheral = peripheral;
        // Retain the peripheral to keep it alive
        CFBridgingRetain(peripheral);

        device->c_device.identifier = strdup([[peripheral.identifier UUIDString] UTF8String]);
        device->c_device.name = strdup([peripheral.name UTF8String] ?: "");
        device->c_device.is_connected = NO;
        device->c_device.backend_state = device.get();

        @synchronized(g_central_delegate) {
            NSArray<CBUUID*>* advertisedServices = g_central_delegate.advertisedServiceUUIDs[peripheral.identifier];
            for (CBUUID* serviceUUID in advertisedServices) {
                device->advertised_service_uuids.emplace_back([[serviceUUID UUIDString] UTF8String]);
            }
        }

        devices.push_back(device);

        // Call callback
        if (g_found_callbacks.count(manager)) {
            auto callback = g_found_callbacks[manager];
            auto cb_user_data = g_found_user_data[manager];
            if (callback) {
                callback(&device->c_device, cb_user_data);
            }
        }
    }];

    return BLE_STATUS_OK;
}

void ble_backend_device_manager_stop_scan(ble_device_manager_t* manager) {
    (void)manager;
    if (g_central_delegate) {
        [g_central_delegate stopScan];
    }
}

ble_status_t ble_backend_device_manager_scan_for(
    ble_device_manager_t* manager,
    int duration_seconds,
    ble_on_device_found_cb on_device_found,
    void* user_data
) {
    if (!manager || !on_device_found) {
        return BLE_STATUS_INVALID_ARGUMENT;
    }

    // Start the scan
    ble_status_t status = ble_backend_device_manager_start_scan(manager, on_device_found, user_data);
    if (status != BLE_STATUS_OK) {
        return status;
    }

    // Pump the run loop for the specified duration
    NSDate* endTime = [NSDate dateWithTimeIntervalSinceNow:duration_seconds];
    while ([endTime timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    }

    // Stop the scan
    ble_backend_device_manager_stop_scan(manager);

    return BLE_STATUS_OK;
}

size_t ble_backend_device_manager_get_device_count(const ble_device_manager_t* manager) {
    if (!manager || !g_devices_map.count(const_cast<ble_device_manager_t*>(manager))) {
        return 0;
    }
    return g_devices_map[const_cast<ble_device_manager_t*>(manager)].size();
}

ble_device_t* ble_backend_device_manager_get_device(const ble_device_manager_t* manager, size_t index) {
    if (!manager || !g_devices_map.count(const_cast<ble_device_manager_t*>(manager))) {
        return nullptr;
    }

    auto& devices = g_devices_map[const_cast<ble_device_manager_t*>(manager)];
    if (index >= devices.size()) {
        return nullptr;
    }

    return &devices[index]->c_device;
}

const char* ble_backend_device_get_identifier(const ble_device_t* device) {
    return device ? device->identifier : nullptr;
}

const char* ble_backend_device_get_name(const ble_device_t* device) {
    return device ? device->name : nullptr;
}

ble_status_t ble_backend_device_connect(ble_device_t* device) {
    if (!device || !device->backend_state) {
        return BLE_STATUS_INVALID_ARGUMENT;
    }

    auto ble_device = static_cast<CBLEDevice*>(device->backend_state);
    if (!ble_device->peripheral || !g_central_delegate) {
        return BLE_STATUS_ERROR;
    }

    NSLog(@"Connecting to device: %@ (%@)",
          ble_device->peripheral.name ?: @"Unknown",
          ble_device->peripheral.identifier.UUIDString);

    // Initiate connection
    [g_central_delegate.centralManager connectPeripheral:ble_device->peripheral options:nil];

    // Wait for connection (with timeout)
    BOOL connected = [g_central_delegate waitForConnection:ble_device->peripheral timeout:10.0];
    if (!connected) {
        NSLog(@"Connection timeout for %@", ble_device->peripheral.identifier.UUIDString);
        return BLE_STATUS_ERROR;
    }

    NSLog(@"Connection established for %@, discovering services...", ble_device->peripheral.identifier.UUIDString);

    // Wait for service discovery (with timeout)
    BOOL servicesFound = [g_central_delegate waitForServices:ble_device->peripheral timeout:10.0];
    if (!servicesFound) {
        NSLog(@"Service discovery timeout for %@", ble_device->peripheral.identifier.UUIDString);
        return BLE_STATUS_ERROR;
    }

    NSLog(@"Services discovered successfully for %@: %lu services",
          ble_device->peripheral.identifier.UUIDString,
          (unsigned long)[ble_device->peripheral.services count]);
    device->is_connected = YES;

    return BLE_STATUS_OK;
}

void ble_backend_device_disconnect(ble_device_t* device) {
    if (!device || !device->backend_state) {
        return;
    }

    auto ble_device = static_cast<CBLEDevice*>(device->backend_state);
    if (ble_device->peripheral && g_central_delegate) {
        [g_central_delegate.centralManager cancelPeripheralConnection:ble_device->peripheral];
        device->is_connected = NO;
    }
}

bool ble_backend_device_is_connected(const ble_device_t* device) {
    return device ? device->is_connected : false;
}

void ble_backend_device_set_disconnect_callback(
    ble_device_t* device,
    ble_on_device_disconnect_cb on_disconnect,
    void* user_data
) {
    if (!device || !device->backend_state) {
        return;
    }

    auto ble_device = static_cast<CBLEDevice*>(device->backend_state);
    ble_device->on_disconnect_cb = on_disconnect;
    ble_device->disconnect_user_data = user_data;
}

size_t ble_backend_device_get_service_count(const ble_device_t* device) {
    if (!device || !device->backend_state) {
        NSLog(@"get_service_count: device or backend_state is null");
        return 0;
    }

    auto ble_device = static_cast<CBLEDevice*>(device->backend_state);
    if (!ble_device->peripheral) {
        NSLog(@"get_service_count: peripheral is null");
        return 0;
    }

    if (ble_device->peripheral.services) {
        return [ble_device->peripheral.services count];
    }

    return ble_device->advertised_service_uuids.size();
}

const ble_service_t* ble_backend_device_get_service(const ble_device_t* device, size_t index) {
    if (!device || !device->backend_state) {
        return nullptr;
    }

    auto ble_device = static_cast<CBLEDevice*>(device->backend_state);
    if (!ble_device->peripheral) {
        return nullptr;
    }

    if (ble_device->peripheral.services) {
        size_t service_count = [ble_device->peripheral.services count];
        if (index >= service_count) {
            return nullptr;
        }

        ble_device->services.resize(service_count);
        ble_device->cached_service_uuids.resize(service_count);
        for (size_t i = 0; i < service_count; ++i) {
            CBService* service = [ble_device->peripheral.services objectAtIndex:i];
            ble_device->cached_service_uuids[i] = std::string([[service.UUID UUIDString] UTF8String]);
            ble_device->services[i].uuid = ble_device->cached_service_uuids[i].c_str();
            ble_device->services[i].backend_state = (void*)service;
        }
        return &ble_device->services[index];
    }

    if (index >= ble_device->advertised_service_uuids.size()) {
        return nullptr;
    }

    size_t advertised_count = ble_device->advertised_service_uuids.size();
    ble_device->services.resize(advertised_count);
    ble_device->cached_service_uuids = ble_device->advertised_service_uuids;
    for (size_t i = 0; i < advertised_count; ++i) {
        ble_device->services[i].uuid = ble_device->cached_service_uuids[i].c_str();
        ble_device->services[i].backend_state = nullptr;
    }

    return &ble_device->services[index];
}

const char* ble_backend_service_get_uuid(const ble_service_t* service) {
    return service ? service->uuid : nullptr;
}

size_t ble_backend_service_get_characteristic_count(const ble_service_t* service) {
    if (!service || !service->backend_state) {
        return 0;
    }

    CBService* cb_service = (CBService*)service->backend_state;
    return cb_service.characteristics ? [cb_service.characteristics count] : 0;
}

const ble_characteristic_t* ble_backend_service_get_characteristic(
    const ble_service_t* service,
    size_t index
) {
    if (!service || !service->backend_state) {
        return nullptr;
    }

    CBService* cb_service = (CBService*)service->backend_state;
    if (!cb_service.characteristics || index >= [cb_service.characteristics count]) {
        return nullptr;
    }

    // Note: This is a simplified implementation - in production you'd want to cache this
    CBCharacteristic* characteristic = [cb_service.characteristics objectAtIndex:index];

    static ble_characteristic_t cached_char;
    cached_char.uuid = strdup([[characteristic.UUID UUIDString] UTF8String]);
    cached_char.backend_state = (void*)characteristic;

    return &cached_char;
}

const char* ble_backend_characteristic_get_uuid(const ble_characteristic_t* characteristic) {
    return characteristic ? characteristic->uuid : nullptr;
}

ble_status_t ble_backend_characteristic_subscribe(
    ble_device_t* device,
    const ble_characteristic_t* characteristic,
    ble_on_characteristic_notification_cb on_notification,
    void* user_data
) {
    if (!device || !device->backend_state || !characteristic || !characteristic->backend_state) {
        return BLE_STATUS_INVALID_ARGUMENT;
    }

    auto ble_device = static_cast<CBLEDevice*>(device->backend_state);
    CBCharacteristic* cb_char = (CBCharacteristic*)characteristic->backend_state;

    if (!ble_device->peripheral) {
        return BLE_STATUS_ERROR;
    }

    ble_device->on_notification_cb = on_notification;
    ble_device->notification_user_data = user_data;
    ble_device->notification_characteristic_uuid = characteristic->uuid ? characteristic->uuid : "";
    ble_device->notification_characteristic_cache.uuid = ble_device->notification_characteristic_uuid.c_str();
    ble_device->notification_characteristic_cache.backend_state = characteristic->backend_state;

    [ble_device->peripheral setNotifyValue:YES forCharacteristic:cb_char];

    return BLE_STATUS_OK;
}

ble_status_t ble_backend_characteristic_unsubscribe(
    ble_device_t* device,
    const ble_characteristic_t* characteristic
) {
    if (!device || !device->backend_state || !characteristic || !characteristic->backend_state) {
        return BLE_STATUS_INVALID_ARGUMENT;
    }

    auto ble_device = static_cast<CBLEDevice*>(device->backend_state);
    CBCharacteristic* cb_char = (CBCharacteristic*)characteristic->backend_state;

    if (!ble_device->peripheral) {
        return BLE_STATUS_ERROR;
    }

    [ble_device->peripheral setNotifyValue:NO forCharacteristic:cb_char];
    ble_device->on_notification_cb = nullptr;
    ble_device->notification_user_data = nullptr;
    ble_device->notification_characteristic_uuid.clear();
    ble_device->notification_characteristic_cache.uuid = nullptr;
    ble_device->notification_characteristic_cache.backend_state = nullptr;

    return BLE_STATUS_OK;
}


