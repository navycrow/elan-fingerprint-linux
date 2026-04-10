#!/bin/bash
# ============================================================
# Elan fingerprint reader driver installer (elanmoc2) - Bazzite
# Usage: bash install.sh
#
# ⚠️  Bazzite is an immutable system (Fedora Atomic).
#     This script runs in two passes:
#       Pass 1: layer fprintd via rpm-ostree, then reboot (if needed)
#       Pass 2: compile inside Distrobox (rootful) + enroll fingerprint
# ============================================================
set -e

PASS_FLAG="$HOME/.elan_install_pass1_done"

# --- 0. Check sudo privileges ---
if ! sudo -v 2>/dev/null; then
  echo "❌ This script requires sudo privileges."
  exit 1
fi
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ============================================================
# PASS 1 — Layer fprintd + reboot (if needed)
# ============================================================
if [ ! -f "$PASS_FLAG" ]; then
  echo "🔍 Detecting Elan sensor..."
  DEVICE=$(lsusb | grep -i "elan")
  if [ -z "$DEVICE" ]; then
    echo "❌ No Elan sensor detected. Check with: lsusb"
    exit 1
  fi
  echo "Sensor found: $DEVICE"
  PID=$(echo "$DEVICE" | head -n 1 | grep -oP '04f3:\K[0-9a-f]{4}')
  echo "➡️  Detected PID: 0x$PID"
  echo "$PID" > "$HOME/.elan_pid"

  echo ""
  echo "📦 Layering fprintd via rpm-ostree..."
  REBOOT_NEEDED=true
  rpm_output=$(rpm-ostree install --allow-inactive fprintd fprintd-pam 2>&1) || {
    if echo "$rpm_output" | grep -q "already requested\|already provided"; then
      echo "✅ fprintd already layered, skipping."
      REBOOT_NEEDED=false
    else
      echo "❌ rpm-ostree error: $rpm_output"
      exit 1
    fi
  }

  touch "$PASS_FLAG"

  if [ "$REBOOT_NEEDED" = true ]; then
    echo ""
    echo "✅ Pass 1 complete."
    echo "   ⚠️  A reboot is required before continuing."
    echo "   👉 Reboot your system, then run this script again for pass 2."
    echo "      sudo systemctl reboot"
    exit 0
  else
    echo "✅ Pass 1 complete — no reboot needed, continuing to pass 2..."
  fi
fi

# ============================================================
# PASS 2 — Compile inside Distrobox (rootful) + enroll fingerprint
# ============================================================
echo "▶️  Pass 2: compiling and installing the driver..."

PID=$(cat "$HOME/.elan_pid" 2>/dev/null)
if [ -z "$PID" ]; then
  echo "❌ PID not found. Delete $PASS_FLAG and re-run from pass 1."
  exit 1
fi
echo "➡️  Retrieved PID: 0x$PID"

# Check that distrobox is available
if ! command -v distrobox &>/dev/null; then
  echo "❌ distrobox not found (should be included in Bazzite by default)."
  exit 1
fi

# Create the rootful Fedora container if it doesn't exist yet
# --root is required so that sudo works correctly inside the container
BOX_NAME="fedora-elan-build"
if ! distrobox list 2>/dev/null | grep -q "$BOX_NAME"; then
  echo "📦 Creating rootful Fedora Distrobox container..."
  distrobox create --name "$BOX_NAME" --image fedora:latest --yes --root
else
  echo "✅ Container $BOX_NAME already exists, reusing."
fi

echo ""
echo "🔨 Compiling inside Distrobox container ($BOX_NAME)..."

distrobox enter --root "$BOX_NAME" -- bash -s << INNERSCRIPT
set -e

echo "📦 Installing build dependencies..."
sudo dnf install -y gcc-c++ libgusb-devel glib2-devel libgudev-devel \
  gobject-introspection-devel pixman-devel nss-devel libusb1-devel \
  gtk-doc meson ninja-build git openssl-devel cairo-devel \
  cmake systemd-devel systemd-udev

# Fallback: expose udev pkgconfig from systemd-devel if libudev-devel is missing
if ! pkg-config --exists libudev 2>/dev/null; then
  export PKG_CONFIG_PATH="/usr/lib64/pkgconfig:/usr/share/pkgconfig:$PKG_CONFIG_PATH"
fi

TMPDIR=\$(mktemp -d)
echo "⬇️  Cloning libfprint (elanmoc2 branch)..."
git clone -b elanmoc2 https://gitlab.freedesktop.org/Depau/libfprint/ "\$TMPDIR/libfprint"
cd "\$TMPDIR/libfprint"

DRIVER_FILE="libfprint/drivers/elanmoc2/elanmoc2.c"
if [ ! -f "\$DRIVER_FILE" ]; then
  echo "❌ Driver file not found: \$DRIVER_FILE"
  echo "   The repository structure may have changed."
  exit 1
fi

PID="$PID"
if grep -q "0x\$PID" "\$DRIVER_FILE"; then
  echo "✅ ID 0x\$PID already present in driver."
else
  echo "➕ Adding ID 0x\$PID to driver..."
  LAST_ID=\$(grep -oP '\.pid = \K0x0c[0-9a-f]+' "\$DRIVER_FILE" | tail -1)
  sed -i "s/\.pid = \$LAST_ID, .driver_data = ELANMOC2_ALL_DEV},/& \\n  {.vid = ELANMOC2_VEND_ID, .pid = 0x\$PID, .driver_data = ELANMOC2_ALL_DEV},/" "\$DRIVER_FILE"
  grep -q "0x\$PID" "\$DRIVER_FILE" && echo "✅ ID successfully added." || { echo "❌ Failed to add ID."; exit 1; }
fi

echo "🔨 Building..."
# Install to ~/.local to avoid writing to the read-only host filesystem
meson setup builddir --prefix="\$HOME/.local" -Dudev_rules=disabled
cd builddir
ninja
ninja install

echo "📁 Library installed to ~/.local"
rm -rf "\$TMPDIR"
INNERSCRIPT

# --- Copy the compiled library to the system path ---
echo "📁 Copying library to system path..."

LIB_SRC="$HOME/.local/lib64/libfprint-2.so.2.0.0"
TYPELIB_SRC="$HOME/.local/lib64/girepository-1.0/FPrint-2.0.typelib"

if [ ! -f "$LIB_SRC" ]; then
  echo "❌ Compiled library not found at $LIB_SRC"
  echo "   The build may have installed to a different path inside the container."
  echo "   Check with: find \$HOME/.local -name 'libfprint*'"
  exit 1
fi

sudo mkdir -p /usr/local/lib64/girepository-1.0

sudo cp "$LIB_SRC" /usr/local/lib64/
sudo cp "$TYPELIB_SRC" /usr/local/lib64/girepository-1.0/
sudo ln -sf /usr/local/lib64/libfprint-2.so.2.0.0 /usr/local/lib64/libfprint-2.so.2
sudo ln -sf /usr/local/lib64/libfprint-2.so.2     /usr/local/lib64/libfprint-2.so

echo "✅ Library copied and symlinks created."

# Register /usr/local/lib64 with ldconfig
echo "🔗 Updating ldconfig for /usr/local/lib64..."
if ! grep -qr '/usr/local/lib64' /etc/ld.so.conf.d/ 2>/dev/null; then
  echo '/usr/local/lib64' | sudo tee /etc/ld.so.conf.d/local-lib64.conf
fi
sudo ldconfig

# --- Restart fprintd so it picks up the new libfprint ---
echo "🔄 Restarting fprintd..."
sudo systemctl restart fprintd
sleep 2

# --- Verify the device is detected ---
echo "🔎 Verifying device detection..."
if fprintd-list "$USER" 2>&1 | grep -q "No devices available"; then
  echo "❌ fprintd still reports no devices. Check: sudo lsof -p \$(pgrep fprintd) | grep libfprint"
  exit 1
fi
echo "✅ Device detected."

# --- Enable fingerprint authentication via PAM ---
echo "🔐 Enabling fingerprint authentication (PAM)..."
if command -v authselect &>/dev/null; then
  sudo authselect enable-feature with-fingerprint
  sudo authselect apply-changes
else
  echo "⚠️  authselect not found. Enable fingerprint manually via GNOME Settings > Users."
fi

# --- Delete any existing fingerprints before enrolling ---
echo "🗑️  Removing any previously enrolled fingerprints..."
fprintd-delete "$USER" 2>/dev/null || sudo fprintd-delete "$USER" 2>/dev/null || true

# --- Enroll fingerprint ---
echo ""
echo "👆 Enrolling fingerprint (right index finger)..."
echo "   Place and lift your finger several times until 'enroll-completed'."
fprintd-enroll -f right-index-finger

# --- Clean up pass flags ---
rm -f "$PASS_FLAG" "$HOME/.elan_pid"

echo ""
echo "✅ Installation complete! Test with: sudo ls"