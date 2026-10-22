/**
 * set_audio - CoreAudio device switcher and diagnostic tool
 * 
 * Sets the default macOS CoreAudio output and input to AirPods or specified device.
 *
 * Copyright (c) 2026 Magnus Krüger & DeepMind Antigravity Pair-Programming.
 * Licensed under the MIT License.
 */

#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *filter = @"AirPods";
        if (argc > 1) {
            filter = [NSString stringWithUTF8String:argv[1]];
        }

        AudioObjectPropertyAddress addr = {
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        UInt32 size = 0;
        AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, NULL, &size);
        UInt32 count = size / sizeof(AudioDeviceID);
        AudioDeviceID devices[count];
        AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, devices);

        printf("Available CoreAudio Output/Input Devices (%u total):\n", count);
        AudioDeviceID targetId = 0;
        NSString *targetName = nil;

        for (UInt32 i = 0; i < count; i++) {
            CFStringRef name = NULL;
            UInt32 s = sizeof(name);
            AudioObjectPropertyAddress nameAddr = {
                kAudioObjectPropertyName,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            AudioObjectGetPropertyData(devices[i], &nameAddr, 0, NULL, &s, &name);
            if (name) {
                NSString *str = (__bridge NSString*)name;
                printf("  [%u] %s\n", devices[i], [str UTF8String]);
                if ([str localizedCaseInsensitiveContainsString:filter] && targetId == 0) {
                    targetId = devices[i];
                    targetName = [str copy];
                }
                CFRelease(name);
            }
        }

        if (targetId != 0) {
            AudioObjectPropertyAddress defaultOutputAddr = {
                kAudioHardwarePropertyDefaultOutputDevice,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            OSStatus err = AudioObjectSetPropertyData(kAudioObjectSystemObject, &defaultOutputAddr, 0, NULL, sizeof(targetId), &targetId);
            printf("\nSetting Default Output to '%s' (ID %u): %s (status %d)\n",
                   [targetName UTF8String], targetId, (err == noErr) ? "SUCCESS" : "FAILED", (int)err);
            return (err == noErr) ? 0 : 2;
        } else {
            printf("\nDevice matching '%s' not found in active CoreAudio device list.\n", [filter UTF8String]);
            printf("Note: If using AirPods, they must be taken OUT of the case and placed in-ear to be published by CoreAudio.\n");
            return 1;
        }
    }
}
