/**
 * btconnect - Flexible macOS Bluetooth Connection Utility using IOBluetooth
 * 
 * Connects to Bluetooth audio devices (AirPods, headphones, speakers) by MAC address
 * or device name substring. If no argument is given, lists paired devices.
 *
 * Copyright (c) 2026 Magnus Krüger. Released under the MIT License.
 */

#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

void print_usage(const char *prog) {
    printf("Usage:\n");
    printf("  %s <device-name-or-mac>    Connect to a specific paired device\n", prog);
    printf("  %s --list                  List all paired devices\n", prog);
    printf("  %s                         Auto-connect to the first paired audio device\n", prog);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray *pairedDevices = [IOBluetoothDevice pairedDevices];
        if (!pairedDevices || [pairedDevices count] == 0) {
            fprintf(stderr, "No paired Bluetooth devices found.\n");
            return 1;
        }

        if (argc > 1 && (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0)) {
            print_usage(argv[0]);
            return 0;
        }

        if (argc > 1 && (strcmp(argv[1], "-l") == 0 || strcmp(argv[1], "--list") == 0)) {
            printf("Paired Bluetooth Devices (%lu found):\n", (unsigned long)[pairedDevices count]);
            for (IOBluetoothDevice *d in pairedDevices) {
                printf("  - %s [%s] (Connected: %s)\n",
                       [[d name] UTF8String],
                       [[d addressString] UTF8String],
                       [d isConnected] ? "YES" : "NO");
            }
            return 0;
        }

        IOBluetoothDevice *targetDevice = nil;

        if (argc > 1) {
            NSString *query = [NSString stringWithUTF8String:argv[1]];
            NSString *normalizedQuery = [query stringByReplacingOccurrencesOfString:@":" withString:@"-"].lowercaseString;

            for (IOBluetoothDevice *d in pairedDevices) {
                NSString *addr = [[d addressString] lowercaseString];
                NSString *name = [d name] ? [d name] : @"";

                if ([addr isEqualToString:normalizedQuery] ||
                    [name localizedCaseInsensitiveContainsString:query]) {
                    targetDevice = d;
                    break;
                }
            }

            if (!targetDevice) {
                // Try direct address lookup if not matched in paired list
                targetDevice = [IOBluetoothDevice deviceWithAddressString:normalizedQuery];
            }
        } else {
            // Auto-detect first paired audio device (Headphones/AirPods)
            for (IOBluetoothDevice *d in pairedDevices) {
                BluetoothDeviceClassMinor minor = [d deviceClassMinor];
                NSString *name = [d name] ? [d name] : @"";
                // Minor class 1 = Wearable Headset, 2 = Hands-free, 6 = Headphones
                if (minor == 1 || minor == 2 || minor == 6 ||
                    [name localizedCaseInsensitiveContainsString:@"AirPods"] ||
                    [name localizedCaseInsensitiveContainsString:@"Headphones"] ||
                    [name localizedCaseInsensitiveContainsString:@"Buds"]) {
                    targetDevice = d;
                    break;
                }
            }
            if (!targetDevice && [pairedDevices count] > 0) {
                targetDevice = [pairedDevices firstObject];
            }
        }

        if (!targetDevice) {
            fprintf(stderr, "Error: No matching Bluetooth device found.\n");
            return 1;
        }

        NSString *devName = [targetDevice name] ? [targetDevice name] : @"(Unknown Device)";
        NSString *devAddr = [targetDevice addressString] ? [targetDevice addressString] : @"(Unknown Address)";

        printf("Target: %s [%s]\n", [devName UTF8String], [devAddr UTF8String]);

        if ([targetDevice isConnected]) {
            printf("Status: Device is already connected.\n");
            return 0;
        }

        printf("Opening connection (page timeout: 5000ms)...\n");
        IOReturn kr = [targetDevice openConnection:nil withPageTimeout:5000 authenticationRequired:NO];
        if (kr == kIOReturnSuccess) {
            usleep(250000); // 250ms for services to settle
            printf("Success: Connected to %s (status: %s)\n",
                   [devName UTF8String], [targetDevice isConnected] ? "ACTIVE" : "ESTABLISHING");
            return 0;
        } else {
            fprintf(stderr, "Connection failed: openConnection returned 0x%08x (%d)\n", kr, kr);
            if (kr == (IOReturn)0xe00002d6) {
                fprintf(stderr, "Note: Page Timeout (0xe00002d6). Ensure the target device is awake and in range.\n");
            }
            return 2;
        }
    }
}
