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
mkdir -p "$REPO_DIR/build"
clang -O2 -Wall -framework IOKit "$REPO_DIR/src/rtwcoexd.c" -o "$REPO_DIR/build/rtwcoexd"
clang -O2 -Wall -framework Foundation -framework IOBluetooth "$REPO_DIR/src/btconnect.m" -o "$REPO_DIR/build/btconnect"
clang -O2 -Wall -framework Foundation -framework CoreAudio "$REPO_DIR/src/set_audio.m" -o "$REPO_DIR/build/set_audio"

# 2. Install to /usr/local/bin
echo "[2/6] Installing binaries to /usr/local/bin..."
mkdir -p /usr/local/bin
cp -f "$REPO_DIR/build/rtwcoexd" /usr/local/bin/rtwcoexd
cp -f "$REPO_DIR/build/btconnect" /usr/local/bin/btconnect
cp -f "$REPO_DIR/build/set_audio" /usr/local/bin/set_audio
chmod 755 /usr/local/bin/rtwcoexd /usr/local/bin/btconnect /usr/local/bin/set_audio
chown root:wheel /usr/local/bin/rtwcoexd /usr/local/bin/btconnect /usr/local/bin/set_audio

# 3. Permanently lock rogue RF-OFF helper files
echo "[3/6] Applying immutable protection against rogue RF-OFF watchdogs..."
WLAN_DIR="/Library/Application Support/WLAN/com.realtek.utility.wifi"
if [ -d "$WLAN_DIR" ]; then
    for f in "$WLAN_DIR"/*rfoff.rtl; do
        if [ -e "$f" ]; then
            chflags nouchg "$f" 2>/dev/null || true
            echo "0" > "$f"
            chmod 444 "$f"
            chflags uchg "$f"
            echo "      Protected: $(basename "$f") (locked with uchg, value=0)."
        fi
    done
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

# 5. Optimize Network Service Priority and DNS Fallback
echo "[5/6] Optimizing network service order and DNS fallback..."
# Remove conflicting PAN if present
networksetup -removenetworkservice "Bluetooth PAN" 2>/dev/null || true

# Find Realtek Wi-Fi service name
RT_SERVICE=$(networksetup -listallhardwareports 2>/dev/null | awk '/802.11ac NIC/{getline; print $2}' | head -n 1)
if [ -n "$RT_SERVICE" ]; then
    SERVICE_NAME=$(networksetup -listnetworkserviceorder 2>/dev/null | grep -B 1 "$RT_SERVICE" | head -n 1 | sed 's/^[^(]*([0-9]*) //')
    if [ -n "$SERVICE_NAME" ]; then
        echo "      Detected Realtek Wi-Fi Service: '$SERVICE_NAME'"
        # Discover current gateway for DNS fallback
        GATEWAY=$(netstat -rn | grep default | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
        if [ -n "$GATEWAY" ]; then
            networksetup -setdnsservers "$SERVICE_NAME" "$GATEWAY" 1.1.1.1 8.8.8.8 2>/dev/null || true
        else
            networksetup -setdnsservers "$SERVICE_NAME" 1.1.1.1 8.8.8.8 2>/dev/null || true
        fi
    fi
fi

# 6. Verify daemon execution
echo "[6/6] Verifying rtwcoexd status..."
if pgrep -x "rtwcoexd" > /dev/null; then
    echo "SUCCESS: rtwcoexd is running (PID: $(pgrep -x rtwcoexd))."
else
    echo "WARNING: rtwcoexd did not start immediately. Check /var/log/rtwcoexd.log."
fi

echo ""
echo "=== Installation complete! ==="
