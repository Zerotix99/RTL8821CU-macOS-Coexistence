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

## 3. High-Precision Time-Division Multiplexing (TDMA)
To deliver glitch-free Bluetooth audio (AirPods Pro AAC frames ~21.3 ms) and responsive Wi-Fi throughput concurrently:
- `rtwcoexd` runs on macOS with `QOS_CLASS_USER_INTERACTIVE` priority.
- Alternates antenna grant every:
  - **30 ms** for Bluetooth (ensures reliable paging connection establishment and uninterrupted A2DP audio frame transfer).
  - **35 ms** for Wi-Fi (ensures high TCP/UDP throughput and sub-25ms ping latency).
- Cycle Period: **65 ms (~15.4 Hz)**.

```mermaid
sequenceDiagram
    participant CoexDaemon as rtwcoexd
    participant HW as RTL8821CU RF Switch
    participant BT as Bluetooth Radio (AirPods)
    participant WL as Wi-Fi Radio (802.11ac)

    rect rgb(230, 245, 255)
        Note over CoexDaemon,WL: Bluetooth Slot (30 ms)
        CoexDaemon->>HW: write_indirect(0x38, 0x0000ff00)
        HW->>BT: Antenna granted
        BT->>AirPods: Transmit/Receive AAC audio packets
    end
    rect rgb(240, 255, 240)
        Note over CoexDaemon,WL: Wi-Fi Slot (35 ms)
        CoexDaemon->>HW: write_indirect(0x38, 0x00003300)
        HW->>WL: Antenna granted
        WL->>Router: Transmit/Receive TCP/IP packets
    end
```

---

## 4. macOS CoreAudio & AirPods Smart Routing Integration
AirPods Pro firmware reports in-ear optical sensor status via Apple Accessory Communication Protocol (AACP):
- **In Case**: `primaryStatus = 3, secondaryStatus = 3`. CoreAudio marks the device `mAudioRouteHidden = 1`.
- **In Ear**: `primaryStatus = 1`. CoreAudio immediately unhides the audio endpoint (`mAudioRouteHidden = 0`) and routes system audio to AirPods.

The repository includes `src/set_audio.m` to verify and force default system routing when endpoints are published.
