#!/bin/bash
# status.sh - Comprehensive health check for RTL8821CU Coexistence System

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

echo -n "2. Wi-Fi (en2) Connection: "
IP=$(ifconfig en2 2>/dev/null | grep "inet " | awk '{print $2}')
if [ -n "$IP" ]; then
    echo "ONLINE (IP: $IP)"
    echo -n "   Gateway Ping (192.168.0.1 via en2): "
    PING_RES=$(ping -c 3 -t 2 -S "$IP" 192.168.0.1 2>/dev/null | grep "packet loss" | awk -F', ' '{print $3}')
    echo "${PING_RES:-Failed}"
else
    echo "OFFLINE"
fi

echo "3. Bluetooth Status:"
system_profiler SPBluetoothDataType 2>/dev/null | grep -A 10 "Connected:" || echo "   No Bluetooth devices connected."

echo -n "4. RF-OFF Lock: "
RFOFF="/Library/Application Support/WLAN/com.realtek.utility.wifi/e0ad474257a2rfoff.rtl"
if [ -f "$RFOFF" ]; then
    FLAGS=$(ls -lO "$RFOFF" | awk '{print $5}')
    VAL=$(cat "$RFOFF" 2>/dev/null)
    echo "PROTECTED (flags: $FLAGS, val: $VAL)"
else
    echo "Not found (Default)"
fi

echo "=========================================================="
