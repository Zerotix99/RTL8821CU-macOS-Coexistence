#!/bin/bash
# uninstall.sh - Clean uninstaller for RTL8821CU Coexistence System
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./scripts/uninstall.sh)"
    exit 1
fi

echo "=== Uninstalling RTL8821CU Coexistence System ==="

PLIST_DST="/Library/LaunchDaemons/com.realtek.coex.plist"
if [ -f "$PLIST_DST" ]; then
    echo "Stopping LaunchDaemon..."
    launchctl unload "$PLIST_DST" 2>/dev/null || true
    rm -f "$PLIST_DST"
fi

killall rtwcoexd 2>/dev/null || true
rm -f /usr/local/bin/rtwcoexd
rm -f /usr/local/bin/btconnect
rm -f /usr/local/bin/set_audio
rm -f /var/log/rtwcoexd.log

RFOFF_FILE="/Library/Application Support/WLAN/com.realtek.utility.wifi/e0ad474257a2rfoff.rtl"
if [ -f "$RFOFF_FILE" ]; then
    chflags nouchg "$RFOFF_FILE" 2>/dev/null || true
fi

echo "Uninstallation complete."
