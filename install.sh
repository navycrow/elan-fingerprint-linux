#!/bin/bash
# ============================================================
# Elan fingerprint reader driver installer (elanmoc2) - Ubuntu
# Usage: bash install.sh
# ============================================================

set -e  # exit immediately if a command fails

# --- 0. Check sudo privileges ---
if ! sudo -v 2>/dev/null; then
  echo "❌ This script requires sudo privileges."
  exit 1
fi
# Keep sudo alive in the background to prevent timeout during compilation
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# --- 1. Detect Elan sensor ---
echo "🔍 Detecting Elan sensor..."
DEVICE=$(lsusb | grep -i "elan")

if [ -z "$DEVICE" ]; then
  echo "❌ No Elan sensor detected. Check with: lsusb"
  exit 1
fi

echo "Sensor found: $DEVICE"
PID=$(echo "$DEVICE" | head -n 1 | grep -oP '04f3:\K[0-9a-f]{4}')
echo "➡️  Detected PID: 0x$PID"

# --- 2. Install build dependencies ---
echo ""
echo "📦 Installing dependencies..."
sudo apt update -q
sudo apt install -y \
  libglib2.0-dev libgusb-dev libgirepository1.0-dev \
  libpixman-1-dev libnss3-dev libgudev-1.0-dev gtk-doc-tools \
  meson ninja-build git libssl-dev libcairo2-dev \
  fprintd libpam-fprintd

# --- 3. Clone into a temporary directory ---
echo ""
echo "⬇️  Downloading libfprint (elanmoc2 branch)..."
TMPDIR=$(mktemp -d)
echo "📁 Temporary directory: $TMPDIR"
git clone -b elanmoc2 https://gitlab.freedesktop.org/Depau/libfprint/ "$TMPDIR/libfprint"
cd "$TMPDIR/libfprint"

DRIVER_FILE="libfprint/drivers/elanmoc2/elanmoc2.c"

# --- 4. Inject sensor ID if missing ---
if [ ! -f "$DRIVER_FILE" ]; then
  echo "❌ Driver file not found: $DRIVER_FILE"
  echo "   The repository structure may have changed."
  exit 1
fi

if grep -q "0x$PID" "$DRIVER_FILE"; then
  echo "✅ ID 0x$PID already present in driver."
else
  echo "➕ Adding ID 0x$PID to driver..."
  LAST_ID=$(grep -oP '\.pid = \K0x0c[0-9a-f]+' "$DRIVER_FILE" | tail -1)
  sed -i "s/\.pid = $LAST_ID, .driver_data = ELANMOC2_ALL_DEV},/& \n  {.vid = ELANMOC2_VEND_ID, .pid = 0x$PID, .driver_data = ELANMOC2_ALL_DEV},/" "$DRIVER_FILE"

  # Check writing
  if grep -q "0x$PID" "$DRIVER_FILE"; then
    echo "✅ ID 0x$PID successfully added to $DRIVER_FILE"
  else
    echo "❌ Failed to add ID. Check permissions or file path."
    exit 1
  fi
fi

# --- 5. Build and install ---
echo ""
echo "🔨 Compiling..."
meson setup builddir
cd builddir
ninja
sudo ninja install
sudo ldconfig

# --- 6. Cleanup ---
echo ""
echo "🧹 Cleaning up temporary directory..."
cd ~
sudo rm -rf "$TMPDIR"

# --- 7. Enable PAM authentication ---
echo ""
echo "🔐 Enabling fingerprint authentication (PAM)..."
sudo systemctl restart fprintd
sudo pam-auth-update --enable fprintd

# --- 8. Enroll fingerprint ---
echo ""
echo "👆 Enrolling fingerprint (right index finger)..."
echo "   Place and lift your finger ** SEVERAL TIMES ** until 'enroll-completed'."
fprintd-enroll -f right-index-finger

echo ""
echo "✅ Installation complete! Test with: sudo ls"