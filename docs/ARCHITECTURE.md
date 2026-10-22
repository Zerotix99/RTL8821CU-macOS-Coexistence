# Technical Architecture & Reverse Engineering

## 1. Hardware Overview & The Single-Antenna Problem
The Realtek **RTL8821CU** (`0bda:c820`) is a combo Wi-Fi 5 (802.11ac 1T1R) and Bluetooth 4.2 controller connected via USB 2.0.
On devices with severed or damaged internal antennas (such as a MacBook with torn U.FL coaxial cables), **both Wi-Fi and Bluetooth must share a single external antenna** connected to the dongle's RF port.

By default:
- The Realtek macOS Wi-Fi driver (`RtWlanU.kext`) configures the internal RF switch to Wi-Fi manual mode (`0x0cb4 = 0x10000077`).
- Bluetooth is physically disconnected from the antenna, causing all Bluetooth connection attempts (paging) to fail with Page Timeout (`0xe00002d6`).
- Conversely, granting 100% antenna time to Bluetooth completely starves Wi-Fi (100% packet loss).

---

## 2. Register Map & Hardware Coexistence Control
Through low-level IOKit structural reverse engineering of `RtWlanU` method 2 (`IOConnectCallStructMethod`), the following register map was uncovered:

### `0x0cb4` (`REG_RFE_CTRL8`) - RF Front-End Switch Mode
- **`0x10000077`**: Wi-Fi manual mode. Wi-Fi has 100% exclusive antenna access. BT is isolated.
- **`0x30000077`**: BT manual mode. BT has 100% exclusive antenna access. Wi-Fi is isolated.
- **`0x10000066`**: **PTA Hardware Mode**. Low-order nibbles `0x66` delegate antenna switch pins to internal Packet Traffic Arbitration (PTA) logic and indirect register control.

### Indirect Register `0x38` (`LTE_COEX_CTRL`)
Accessed indirectly via:
1. Writing 32-bit data to `0x1704` (`REG_LTECOEX_WDATA`).
2. Delaying 15 µs.
3. Writing `0xc00f0000 | 0x38` to `0x1700` (`REG_LTECOEX_RPT`).

Bitfield definitions for Indirect Register `0x38`:
- Bits 15:14 (`0xc000`): `GNT_BT_TX`
- Bits 13:12 (`0x3000`): `GNT_WL_TX`
- Bits 11:10 (`0x0c00`): `GNT_BT_RX`
- Bits 9:8   (`0x0300`): `GNT_WL_RX`

Values:
- `0x0`: Hardware PTA arbitration
- `0x1`: Software Low (force deny)
- `0x3`: Software High (force grant)

Key register states used in TDMA:
- **BT Grant Slot (`0x0000ff00`)**: BT TX/RX forced to `SW_HIGH` with priority over Wi-Fi.
- **Wi-Fi Grant Slot (`0x00003300`)**: WL TX/RX forced to `SW_HIGH`, BT set to `HW_PTA`.

---

## 3. Dynamic Auto-Adaptive State Machine & Slot Architecture

Instead of running a rigid static TDMA loop that penalizes Wi-Fi when Bluetooth is idle, `rtwcoexd` implements a reactive 5-state engine:

```
[System Poller]
       │
       ├─ Bluetooth Powered OFF? ──────► MODE_WIFI_ONLY (100% Wi-Fi, No TDMA)
       │
       ├─ Wi-Fi Interface Disabled? ──► MODE_BT_ONLY (100% BT, No TDMA)
       │
       ├─ Wi-Fi Channel > 14 (5 GHz)? ─► MODE_CONCURRENT_5G (100% WL + 100% BT Simultaneous!)
       │
       ├─ 0 BT Devices Connected? ────► MODE_STANDBY_LOW_OVERHEAD (470ms WL / 30ms BT)
       │
       └─ ≥1 BT Device Connected? ────► MODE_ACTIVE_TDMA (35ms WL / 30ms BT)
```

### The 5 GHz Frequency-Division Multiplexing (FDM) Breakthrough
The RTL8821CU hardware integrates an internal RF Diplexer (frequency splitter) right at the common antenna port:
- $f \le 2.4835\text{ GHz} \rightarrow$ 2.4 GHz Low-Pass Path (Bluetooth & 2.4G Wi-Fi)
- $f \ge 5.150\text{ GHz} \rightarrow$ 5 GHz Bandpass Path (802.11ac Wi-Fi)

When the Wi-Fi connection operates on the 5 GHz band (Channels 36–165), Wi-Fi communicates exclusively through the 5 GHz path, leaving the 2.4 GHz path completely unused. 

`rtwcoexd` detects 5 GHz operation and activates `MODE_CONCURRENT_5G`:
1. Antenna register `0x0cb4` is set to `VAL_RFE_PTA` (`0x10000066`).
2. Indirect register `0x38` is granted to Wi-Fi (`0x00003300`) while hardware PTA handles Bluetooth.
3. The TDMA multiplexing loop is **completely bypassed** (`usleep` 1s idle).
4. Both radios operate at **100% simultaneous duty cycle** with zero latency penalty and maximum 433 Mbps Wi-Fi throughput.

### The Slot Inversion Rationale (2.4 GHz)
In early iterations on 2.4 GHz, the TDMA loop granted the Wi-Fi slot first and Bluetooth slot second (`WL -> BT`). As a consequence, whenever the loop completed an iteration and performed daemon housekeeping (such as calling `[IOBluetoothDevice pairedDevices]`, which issues synchronous XPC calls to `bluetoothd` taking 20–50 ms), the physical RF switch was left in the **Bluetooth state**.

This caused periodic latency spikes and packet loss on Wi-Fi every 1–2 seconds.

`rtwcoexd` inverts this sequence:
1. **Bluetooth slot is granted first** (`write_indirect(0x38, COEX_BT_PRIORITY); usleep(bt_us);`)
2. **Wi-Fi slot is granted second** (`write_indirect(0x38, COEX_WL_PRIORITY); usleep(wl_us);`)

This guarantees that whenever the loop exits or state evaluation is executed, the RF switch **always remains locked to Wi-Fi**, completely eliminating evaluation latency penalties.

### Timing & Multiplexing Characteristics

| Mode | Wi-Fi Slot | BT Slot | Cycle Period | Switching Freq | Wi-Fi Antenna Ratio | Typical Gateway Ping |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **`MODE_CONCURRENT_5G`** | **100% (Simul.)** | **100% (Simul.)**| N/A | **0 Hz (No TDMA)** | **100.0%** | **1.8 – 2.8 ms** |
| **`MODE_WIFI_ONLY`** | ∞ | 0 ms | N/A | 0 Hz | 100% | 1.5 – 2.0 ms |
| **`MODE_STANDBY_LOW_OVERHEAD`** | 470 ms | 30 ms | 500 ms | 2.0 Hz | 94.0% | 1.9 – 3.5 ms |
| **`MODE_ACTIVE_TDMA`** | 35 ms | 30 ms | 65 ms | 15.4 Hz | 53.8% | 11.0 – 15.0 ms |
| **`MODE_BT_ONLY`** | 0 ms | ∞ | N/A | 0 Hz | 0.0% | N/A |

```mermaid
sequenceDiagram
    participant CoexDaemon as rtwcoexd
    participant HW as RTL8821CU RF Switch
    participant BT as Bluetooth Radio
    participant WL as Wi-Fi Radio

    rect rgb(230, 245, 255)
        Note over CoexDaemon,WL: 1. Bluetooth Slot First (30 ms)
        CoexDaemon->>HW: write_indirect(0x38, 0x0000ff00)
        HW->>BT: Antenna granted
        BT->>BT: Paging / A2DP Audio Transmission
    end
    rect rgb(240, 255, 240)
        Note over CoexDaemon,WL: 2. Wi-Fi Slot Second (35 ms or 470 ms)
        CoexDaemon->>HW: write_indirect(0x38, 0x00003300)
        HW->>WL: Antenna granted
        WL->>WL: 802.11ac Frames & TCP Traffic
    end
    Note over CoexDaemon,WL: Loop exits on Wi-Fi -> State Evaluation runs while Wi-Fi holds antenna!
```

---

## 4. macOS CoreAudio & AirPods Smart Routing Integration
AirPods Pro firmware reports in-ear optical sensor status via Apple Accessory Communication Protocol (AACP):
- **In Case**: `primaryStatus = 3, secondaryStatus = 3`. CoreAudio marks the device `mAudioRouteHidden = 1`.
- **In Ear**: `primaryStatus = 1`. CoreAudio immediately unhides the audio endpoint (`mAudioRouteHidden = 0`) and routes system audio to AirPods.

The repository includes `src/set_audio.m` to verify and force default system routing when endpoints are published.
