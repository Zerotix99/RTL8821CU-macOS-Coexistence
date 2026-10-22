/**
 * btconnect - Fast macOS Bluetooth connection utility using IOBluetooth
 * 
 * Usage: btconnect [device_mac_address]
 * Default: 40-b3-fa-21-d8-91 (AirPods Pro)
 *
 * Copyright (c) 2026 Magnus Krüger & DeepMind Antigravity Pair-Programming.
 * Licensed under the MIT License.
 */

#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

#define DEFAULT_DEVICE_ADDR @"40-b3-fa-21-d8-91"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *targetAddr = DEFAULT_DEVICE_ADDR;
        if (argc > 1) {
            targetAddr = [NSString stringWithUTF8String:argv[1]];
        }
        targetAddr = [targetAddr stringByReplacingOccurrencesOfString:@":" withString:@"-"].lowercaseString;

        IOBluetoothDevice *dev = [IOBluetoothDevice deviceWithAddressString:targetAddr];
        if (!dev) {
            fprintf(stderr, "Error: Bluetooth device '%s' not found in paired device cache.\n", [targetAddr UTF8String]);
            return 1;
        }

        NSString *name = [dev name] ? [dev name] : @"(Unknown Name)";
        printf("Target Device: %s [%s]\n", [name UTF8String], [[dev addressString] UTF8String]);

        if ([dev isConnected]) {
            printf("Status: Device is ALREADY connected.\n");
            return 0;
        }

        printf("Initiating connection (page timeout: 3000ms)...\n");
        IOReturn kr = [dev openConnection:nil withPageTimeout:3000 authenticationRequired:NO];
        if (kr == kIOReturnSuccess) {
            printf("Success: Connection opened (kr = 0x%08x).\n", kr);
            // Brief wait for services to settle
            usleep(200000); // 200ms
            printf("Connected: %s\n", [dev isConnected] ? "YES" : "PENDING");
            return 0;
        } else {
            fprintf(stderr, "Failed: openConnection returned error 0x%08x (%d).\n", kr, kr);
            if (kr == (IOReturn)0xe00002d6) {
                fprintf(stderr, "Hint: Page Timeout (0xe00002d6). Check that AirPods are OUT of the case or case lid is open.\n");
            }
            return 2;
        }
    }
}
