# RTL8821CU macOS Hardware Coexistence Daemon (`rtwcoexd`)

[![Platform](https://img.shields.io/badge/Platform-macOS%2012%20%7C%2013%20%7C%2014-blue.svg)](https://apple.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hardware](https://img.shields.io/badge/Chipset-Realtek%20RTL8821CU-green.svg)](https://www.realtek.com)

Production-grade background daemon that enables **simultaneous, high-performance Wi-Fi and Bluetooth operation** on Realtek RTL8821CU USB combo dongles (`0bda:c820`) using a **single physical external antenna**.

Tested and verified on **macOS Ventura 13.7.x** on a MacBook 12" Retina with torn internal antennas, delivering uninterrupted **AirPods Pro AAC audio** alongside concurrent **high-speed Wi-Fi** connectivity.

---

## 🎯 The Problem
On devices where internal Wi-Fi/Bluetooth antenna cables are damaged or missing, both radios must share the single external antenna of the USB dongle.

By default, the Realtek macOS driver locks the internal RF switch to Wi-Fi manual mode (`0x0cb4 = 0x10000077`), cutting Bluetooth off from the antenna. As a result:
- Bluetooth connection attempts fail with **Page Timeout (`0xe00002d6`)**.
- If Bluetooth is manually forced on, Wi-Fi starves with **100% packet loss**.
- Vendor watchdog scripts repeatedly force the Wi-Fi radio off (`rfoff.rtl`).

---

## 🚀 The Solution: `rtwcoexd`
`rtwcoexd` leverages low-level IOKit structural calls to:
1. Configure Realtek's Packet Traffic Arbitration (PTA) hardware mode (`0x0cb4 = 0x10000066`).
2. Run a high-precision, sub-millisecond **Time-Division Multiplexing (TDMA)** loop:
   - **30 ms Bluetooth Slot**: Uninterrupted audio packet transfer and instant device paging.
   - **35 ms Wi-Fi Slot**: Sustained TCP/UDP throughput and low ping latency.
3. Automatically recover from USB hotplug and bus resets.
4. Run cleanly as a root `launchd` daemon (`com.realtek.coex.plist`).

---

## 📦 Repository Structure

```
.
├── Makefile               # Build, install, status, and clean targets
├── launchd/
│   └── com.realtek.coex.plist # System LaunchDaemon definition
├── scripts/
│   ├── install.sh         # 1-step automated installation script
│   ├── uninstall.sh       # Clean removal script
│   └── status.sh          # Real-time health check dashboard
├── src/
│   ├── rtwcoexd.c         # High-precision TDMA coexistence daemon
│   ├── btconnect.m        # IOBluetooth CLI connection helper
│   └── set_audio.m        # CoreAudio device switcher and diagnostic tool
└── docs/
    └── ARCHITECTURE.md    # Low-level register map and reverse engineering notes
```

---

## 🛠️ Quick Installation

Clone this repository and run the automated installer:

```bash
git clone git@github.com:YOUR_USERNAME/RTL8821CU-macOS-Coexistence.git
cd RTL8821CU-macOS-Coexistence
make
sudo make install
```

The installer will:
1. Compile all binaries (`rtwcoexd`, `btconnect`, `set_audio`).
2. Install binaries to `/usr/local/bin/`.
3. Apply immutable file protection against vendor RF-OFF helper watchdogs.
4. Configure macOS network service priority and DNS fallback.
5. Load and start the `com.realtek.coex` LaunchDaemon.

---

## 🔍 Verification & Health Check

Run the health check tool:

```bash
make status
# or directly:
./scripts/status.sh
```

Example Output:
```
==========================================================
      RTL8821CU macOS Coexistence Health Check
==========================================================
1. rtwcoexd Daemon: RUNNING (PID: 13696)
2. Wi-Fi (en2) Connection: ONLINE (IP: 192.168.0.181)
   Gateway Ping (192.168.0.1 via en2): 0.0% packet loss
3. Bluetooth Status:
      Connected:
          AirPods Pro von Magnus:
              Case Battery Level: 42 %
              Left Battery Level: 100 %
              Right Battery Level: 100 %
4. RF-OFF Lock: PROTECTED (flags: uchg, val: 0)
==========================================================
```

---

## 🎧 Connecting AirPods Pro
1. Take at least one AirPod **out of the charging case and place it in your ear**.
   > **Note**: macOS CoreAudio intentionally sets `mAudioRouteHidden = 1` while AirPods rest in the charging case. Putting them in your ear triggers the optical sensor, causing CoreAudio to unhide the device and route sound automatically.
2. If connecting from CLI:
   ```bash
   btconnect 40-b3-fa-21-d8-91
   set_audio AirPods
   ```

---

## ⚙️ Customizing Slot Timing
The daemon supports custom slot durations via command-line arguments in `com.realtek.coex.plist`:

```bash
# Example: 25ms Bluetooth / 30ms Wi-Fi
/usr/local/bin/rtwcoexd -b 25 -w 30
```

---

## 📄 License
Released under the [MIT License](LICENSE).
