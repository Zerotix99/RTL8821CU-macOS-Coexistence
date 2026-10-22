/**
 * rtwcoexd - Realtek RTL8821CU Single-Antenna Hardware Coexistence Daemon for macOS
 * 
 * Multiplexes the single physical RF antenna between Wi-Fi and Bluetooth using
 * Realtek's PTA (Packet Traffic Arbitration) hardware mode and indirect register 0x38.
 *
 * Copyright (c) 2026 Magnus Krüger & DeepMind Antigravity Pair-Programming.
 * Licensed under the MIT License.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <signal.h>
#include <pthread.h>
#include <syslog.h>
#include <getopt.h>
#include <IOKit/IOKitLib.h>

#define REG_RFE_CTRL8       0x0cb4
#define REG_LTECOEX_RPT     0x1700
#define REG_LTECOEX_WDATA   0x1704
#define REG_LTECOEX_CTRL    0x38

// Hardware PTA mode: delegates RF switch pins to hardware arbitration logic
#define VAL_RFE_PTA         0x10000066
#define VAL_RFE_WIFI_MANUAL 0x10000077

// Indirect Register 0x38 values
// 0x0000ff00: BT_TX/RX = SW_HIGH (Bluetooth has antenna grant)
// 0x00003300: WL_TX/RX = SW_HIGH, BT = HW_PTA (Wi-Fi has antenna grant)
#define COEX_BT_PRIORITY    0x0000ff00
#define COEX_WL_PRIORITY    0x00003300

// Default slot times in milliseconds
#define DEFAULT_BT_SLOT_MS  30
#define DEFAULT_WL_SLOT_MS  35

static volatile sig_atomic_t g_running = 1;
static io_connect_t g_connect = 0;
static bool g_verbose = false;

static void handle_signal(int sig) {
    g_running = 0;
}

static kern_return_t write_reg(io_connect_t connect, uint32_t type, uint32_t reg, uint32_t val, uint32_t size) {
    uint32_t inData[10] = {type, 0, 1, reg, size, val};
    uint32_t outData[10] = {0};
    size_t outSize = 40;
    return IOConnectCallStructMethod(connect, 2, inData, 40, outData, &outSize);
}

static kern_return_t write_indirect(io_connect_t connect, uint16_t offset, uint32_t val) {
    kern_return_t kr = write_reg(connect, 1, REG_LTECOEX_WDATA, val, 4);
    if (kr != KERN_SUCCESS) return kr;
    usleep(15);
    return write_reg(connect, 1, REG_LTECOEX_RPT, 0xc00f0000 | offset, 4);
}

static void close_device(void) {
    if (g_connect) {
        // Reset RF switch to Wi-Fi manual mode on shutdown
        write_reg(g_connect, 1, REG_RFE_CTRL8, VAL_RFE_WIFI_MANUAL, 4);
        write_indirect(g_connect, REG_LTECOEX_CTRL, COEX_WL_PRIORITY);
        IOServiceClose(g_connect);
        g_connect = 0;
        if (g_verbose) {
            syslog(LOG_INFO, "Closed RtWlanU connection and restored Wi-Fi manual RF mode");
        }
    }
}

static int open_device(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("RtWlanU"));
    if (!service) {
        return -1;
    }
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &g_connect);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS || !g_connect) {
        g_connect = 0;
        return -2;
    }

    // Initialize PTA hardware mode on the RF switch
    kr = write_reg(g_connect, 1, REG_RFE_CTRL8, VAL_RFE_PTA, 4);
    if (kr != KERN_SUCCESS) {
        close_device();
        return -3;
    }
    return 0;
}

static void print_usage(const char *prog) {
    printf("Usage: %s [options]\n", prog);
    printf("Options:\n");
    printf("  -b, --bt-slot <ms>    Bluetooth slot duration in ms (default: %d)\n", DEFAULT_BT_SLOT_MS);
    printf("  -w, --wl-slot <ms>    Wi-Fi slot duration in ms (default: %d)\n", DEFAULT_WL_SLOT_MS);
    printf("  -v, --verbose         Enable verbose log output\n");
    printf("  -h, --help            Show this help message\n");
}

int main(int argc, char **argv) {
    int bt_slot_ms = DEFAULT_BT_SLOT_MS;
    int wl_slot_ms = DEFAULT_WL_SLOT_MS;

    static struct option long_options[] = {
        {"bt-slot", required_argument, 0, 'b'},
        {"wl-slot", required_argument, 0, 'w'},
        {"verbose", no_argument,       0, 'v'},
        {"help",    no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "b:w:vh", long_options, NULL)) != -1) {
        switch (opt) {
            case 'b':
                bt_slot_ms = atoi(optarg);
                if (bt_slot_ms < 5 || bt_slot_ms > 200) {
                    fprintf(stderr, "Error: invalid bt-slot %d (must be between 5 and 200 ms)\n", bt_slot_ms);
                    return 1;
                }
                break;
            case 'w':
                wl_slot_ms = atoi(optarg);
                if (wl_slot_ms < 5 || wl_slot_ms > 200) {
                    fprintf(stderr, "Error: invalid wl-slot %d (must be between 5 and 200 ms)\n", wl_slot_ms);
                    return 1;
                }
                break;
            case 'v':
                g_verbose = true;
                break;
            case 'h':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }

    signal(SIGTERM, handle_signal);
    signal(SIGINT, handle_signal);

    // Boost thread QoS to User Interactive for sub-millisecond timer accuracy
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);

    openlog("rtwcoexd", LOG_PID | LOG_CONS, LOG_DAEMON);
    syslog(LOG_INFO, "rtwcoexd starting: BT slot = %d ms, Wi-Fi slot = %d ms (Period: %d ms, %.1f Hz)",
           bt_slot_ms, wl_slot_ms, bt_slot_ms + wl_slot_ms, 1000.0 / (bt_slot_ms + wl_slot_ms));

    useconds_t bt_us = bt_slot_ms * 1000;
    useconds_t wl_us = wl_slot_ms * 1000;
    int refresh_counter = 0;

    while (g_running) {
        if (!g_connect) {
            if (open_device() != 0) {
                // Device not plugged in; wait and retry
                usleep(500000); // 500ms
                continue;
            }
            syslog(LOG_INFO, "rtwcoexd: connected to RtWlanU, PTA hardware mode engaged (0x%08x)", VAL_RFE_PTA);
        }

        // BT Slot: Grant Bluetooth antenna priority
        kern_return_t kr1 = write_indirect(g_connect, REG_LTECOEX_CTRL, COEX_BT_PRIORITY);
        usleep(bt_us);

        // WL Slot: Grant Wi-Fi antenna priority
        kern_return_t kr2 = write_indirect(g_connect, REG_LTECOEX_CTRL, COEX_WL_PRIORITY);
        usleep(wl_us);

        // Detect USB disconnect or bus failure
        if (kr1 != KERN_SUCCESS || kr2 != KERN_SUCCESS) {
            syslog(LOG_WARNING, "rtwcoexd: IOKit call failed (kr1=0x%x, kr2=0x%x). Reconnecting...", kr1, kr2);
            close_device();
            continue;
        }

        // Periodically refresh PTA mode register (~every 2.5 seconds) in case vendor helper tried to touch it
        if (++refresh_counter >= 50) {
            refresh_counter = 0;
            write_reg(g_connect, 1, REG_RFE_CTRL8, VAL_RFE_PTA, 4);
        }
    }

    syslog(LOG_INFO, "rtwcoexd: stopping cleanly...");
    close_device();
    closelog();
    return 0;
}
