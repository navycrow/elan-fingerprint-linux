#!/bin/bash
# ============================================================
# Elan fingerprint installation on Ubuntu
# Usage : bash install.sh
# ============================================================

set -e  # arrête le script si une commande échoue

# --- 0. Vérification des droits sudo ---
if ! sudo -v 2>/dev/null; then
  echo "❌ Ce script nécessite les droits sudo."
  exit 1
fi
# Garde sudo actif en arrière-plan pour éviter l'expiration
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# --- 1. Détection automatique de l'ID capteur ---
echo "🔍 Détection du capteur Elan..."
DEVICE=$(lsusb | grep -i "elan")

if [ -z "$DEVICE" ]; then
  echo "❌ Aucun capteur Elan détecté. Vérifie avec : lsusb"
  exit 1
fi

echo "Capteur trouvé : $DEVICE"
PID=$(echo "$DEVICE" | head -n 1 | grep -oP '04f3:\K[0-9a-f]{4}')
echo "➡️  PID détecté : 0x$PID"

# --- 2. Dépendances ---
echo ""
echo "📦 Installation des dépendances..."
sudo apt update -q
sudo apt install -y \
  libglib2.0-dev libgusb-dev libgirepository1.0-dev \
  libpixman-1-dev libnss3-dev libgudev-1.0-dev gtk-doc-tools \
  meson ninja-build git libssl-dev libcairo2-dev \
  fprintd libpam-fprintd

# --- 3. Clone dans un dossier temporaire ---
echo ""
echo "⬇️  Téléchargement de libfprint (branche elanmoc2)..."
TMPDIR=$(mktemp -d)
echo "📁 Dossier temporaire : $TMPDIR"
git clone -b elanmoc2 https://gitlab.freedesktop.org/Depau/libfprint/ "$TMPDIR/libfprint"
cd "$TMPDIR/libfprint"

DRIVER_FILE="libfprint/drivers/elanmoc2/elanmoc2.c"

# --- 4. Ajout de l'ID si absent ---
if [ ! -f "$DRIVER_FILE" ]; then
  echo "❌ Fichier driver introuvable : $DRIVER_FILE"
  echo "   La structure du repo a peut-être changé."
  exit 1
fi

if grep -q "0x$PID" "$DRIVER_FILE"; then
  echo "✅ ID 0x$PID déjà présent dans le driver."
else
  echo "➕ Ajout de l'ID 0x$PID dans le driver..."
  LAST_ID=$(grep -oP '\.pid = \K0x0c[0-9a-f]+' "$DRIVER_FILE" | tail -1)
  sed -i "s/\(.pid = $LAST_ID, .driver_data = ELANMOC2_ALL_DEV\),/\1,\n  {.vid = ELANMOC2_VEND_ID, .pid = 0x$PID, .driver_data = ELANMOC2_ALL_DEV},/" "$DRIVER_FILE"
  echo "✅ ID ajouté."
fi

# --- 5. Compilation et installation ---
echo ""
echo "🔨 Compilation..."
meson setup builddir
cd builddir
ninja
sudo ninja install
sudo ldconfig

# --- 6. Nettoyage ---
echo ""
echo "🧹 Nettoyage du dossier temporaire..."
rm -rf "$TMPDIR"

# --- 7. Activation PAM ---
echo ""
echo "🔐 Activation de l'authentification par empreinte (PAM)..."
sudo systemctl restart fprintd
sudo pam-auth-update --enable fprintd

# --- 8. Enrôlement ---
echo ""
echo "👆 Enrôlement de l'empreinte (index droit)..."
echo "   Pose et enlève ton doigt plusieurs fois jusqu'à 'enroll-completed'."
fprintd-enroll -f right-index-finger

echo ""
echo "✅ Installation terminée ! Teste avec : sudo ls"
