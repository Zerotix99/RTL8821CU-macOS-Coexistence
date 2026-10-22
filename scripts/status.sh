#!/bin/bash
# status.sh - Universal health check for RTL8821CU Coexistence System

echo "=========================================================="
echo "      RTL8821CU macOS Coexistence Health Check"
echo "=========================================================="

echo -n "1. rtwcoexd Daemon: "
if pgrep -x "rtwcoexd" > /dev/null; then
    PID=$(pgrep -x rtwcoexd)
    echo "RUNNING (PID: $PID)"
else
    echo "STOPPED"
fi

# Detect Realtek Wi-Fi interface
RT_IF=$(networksetup -listallhardwareports 2>/dev/null | awk '/802.11ac NIC/{getline; print $2}' | head -n 1)
RT_IF=${RT_IF:-en2}

echo -n "2. Wi-Fi ($RT_IF) Connection: "
IP=$(ifconfig "$RT_IF" 2>/dev/null | grep "inet " | awk '{print $2}')
if [ -n "$IP" ]; then
    echo "ONLINE (IP: $IP)"
    GATEWAY=$(netstat -rn | grep default | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    GATEWAY=${GATEWAY:-1.1.1.1}
    echo -n "   Ping to Gateway ($GATEWAY via $RT_IF): "
    PING_RES=$(ping -c 3 -W 1000 -S "$IP" "$GATEWAY" 2>/dev/null | grep "packet loss" | awk -F', ' '{print $3}')
    echo "${PING_RES:-Available}"

    # Detect operating frequency band
    PROF_PLIST="/Library/Application Support/WLAN/com.realtek.utility.wifi/ProfilesList.plist"
    if [ -f "$PROF_PLIST" ]; then
        CH=$(python3 -c '
import plistlib
try:
    with open("'"$PROF_PLIST"'", "rb") as f:
        pl = plistlib.load(f)
    for obj in pl.get("$objects", []):
        if isinstance(obj, int) and 1 <= obj <= 196 and obj not in (1, 6):
            print(obj)
            break
except:
    pass
' 2>/dev/null)
        if [ -n "$CH" ] && [ "$CH" -gt 14 ] 2>/dev/null; then
            echo "   Band: 5 GHz (Channel $CH) -> Dynamic Adaptive TDMA (High-Throughput 802.11ac)"
        elif [ -n "$CH" ]; then
            echo "   Band: 2.4 GHz (Channel $CH) -> Dynamic Adaptive TDMA Mode"
        fi
    fi
else
    echo "OFFLINE"
fi

echo "3. Bluetooth Status:"
CONNECTED_BT=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -A 8 "Connected:" | grep -v "^$" || true)
if [ -n "$CONNECTED_BT" ]; then
    echo "$CONNECTED_BT"
else
    echo "   No active Bluetooth devices connected."
fi

echo -n "4. RF-OFF Watchdog Protection: "
WLAN_DIR="/Library/Application Support/WLAN/com.realtek.utility.wifi"
PROTECTED_COUNT=0
if [ -d "$WLAN_DIR" ]; then
    for f in "$WLAN_DIR"/*rfoff.rtl; do
        if [ -e "$f" ]; then
            FLAGS=$(ls -lO "$f" 2>/dev/null | awk '{print $5}')
            if [[ "$FLAGS" == *"uchg"* ]]; then
                ((PROTECTED_COUNT++))
            fi
        fi
    done
fi
if [ "$PROTECTED_COUNT" -gt 0 ]; then
    echo "PROTECTED ($PROTECTED_COUNT file(s) locked with uchg)"
else
    echo "Default (No locks)"
fi

echo "=========================================================="
