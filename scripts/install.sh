#!/bin/bash
# install.sh - 1-step installer for RTL8821CU Coexistence System on macOS
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./scripts/install.sh)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== RTL8821CU macOS Coexistence Installer ==="

# 1. Compile binaries
echo "[1/6] Compiling rtwcoexd, btconnect, set_audio..."
clang -O2 -framework IOKit "$REPO_DIR/src/rtwcoexd.c" -o "$REPO_DIR/build/rtwcoexd"
clang -O2 -framework Foundation -framework IOBluetooth "$REPO_DIR/src/btconnect.m" -o "$REPO_DIR/build/btconnect"
clang -O2 -framework Foundation -framework CoreAudio "$REPO_DIR/src/set_audio.m" -o "$REPO_DIR/build/set_audio"

# 2. Install to /usr/local/bin
echo "[2/6] Installing binaries to /usr/local/bin..."
mkdir -p /usr/local/bin
cp -f "$REPO_DIR/build/rtwcoexd" /usr/local/bin/rtwcoexd
cp -f "$REPO_DIR/build/btconnect" /usr/local/bin/btconnect
cp -f "$REPO_DIR/build/set_audio" /usr/local/bin/set_audio
chmod 755 /usr/local/bin/rtwcoexd /usr/local/bin/btconnect /usr/local/bin/set_audio
chown root:wheel /usr/local/bin/rtwcoexd /usr/local/bin/btconnect /usr/local/bin/set_audio

# 3. Permanently lock rogue RF-OFF helper file
echo "[3/6] Applying immutable protection against rogue RF-OFF watchdog..."
RFOFF_FILE="/Library/Application Support/WLAN/com.realtek.utility.wifi/e0ad474257a2rfoff.rtl"
if [ -d "$(dirname "$RFOFF_FILE")" ]; then
    chflags nouchg "$RFOFF_FILE" 2>/dev/null || true
    echo "0" > "$RFOFF_FILE"
    chmod 444 "$RFOFF_FILE"
    chflags uchg "$RFOFF_FILE"
    echo "      Locked $RFOFF_FILE with uchg flag (value=0)."
fi

# 4. Install LaunchDaemon
echo "[4/6] Installing and starting LaunchDaemon (com.realtek.coex)..."
PLIST_DST="/Library/LaunchDaemons/com.realtek.coex.plist"
cp -f "$REPO_DIR/launchd/com.realtek.coex.plist" "$PLIST_DST"
chown root:wheel "$PLIST_DST"
chmod 644 "$PLIST_DST"

launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"
sleep 1

# 5. Configure Network Service Priority and DNS
echo "[5/6] Optimizing network service order and DNS fallback..."
# Remove conflicting PAN if present
networksetup -removenetworkservice "Bluetooth PAN" 2>/dev/null || true

# Order: Ethernet -> Realtek WiFi -> Wi-Fi -> iPhone USB
networksetup -ordernetworkservices "AX88179B" "Realtek WiFi" "Wi-Fi" "iPhone USB" 2>/dev/null || \
networksetup -ordernetworkservices "Realtek WiFi" "AX88179B" "Wi-Fi" "iPhone USB" 2>/dev/null || true

# Add DNS fallback to Realtek WiFi
networksetup -setdnsservers "Realtek WiFi" 192.168.0.1 1.1.1.1 8.8.8.8 2>/dev/null || true

# 6. Verify daemon execution
echo "[6/6] Verifying rtwcoexd status..."
if pgrep -x "rtwcoexd" > /dev/null; then
    echo "SUCCESS: rtwcoexd is running (PID: $(pgrep -x rtwcoexd))."
else
    echo "WARNING: rtwcoexd did not start immediately. Check /var/log/rtwcoexd.log."
fi

echo ""
echo "=== Installation complete! ==="
