# elan-fingerprint-linux
Automated install scripts for **Elan** fingerprint readers not natively supported on Linux.
Tested on a **LG Gram 17 2025** with sensor `04f3:0ca2` (ELAN:ARM-M4).

---

## Why this script?
The version of `libfprint` available in official repositories does not support all recent Elan sensors. These scripts compile and install the community branch [`elanmoc2`](https://gitlab.freedesktop.org/Depau/libfprint/) of `libfprint`, and automatically inject your sensor ID into the source code if needed.

---

## Requirements
- sudo privileges
- Internet connection
- A supported distribution (see [Compatibility](#compatibility))

---

## Installation
Clone the repository:
```bash
git clone https://github.com/navycrow/elan-fingerprint-linux.git
cd elan-fingerprint-linux
```

Then run the script for your distribution:

### Debian / Ubuntu
```bash
chmod +x debian-install.sh
./debian-install.sh
```

### Fedora
```bash
chmod +x fedora-install.sh
./fedora-install.sh
```

### Bazzite (and other Fedora Atomic / immutable systems)
Bazzite uses an immutable filesystem, so the install runs in **two passes**:

**Pass 1** — layers `fprintd` via `rpm-ostree`, then prompts for a reboot:
```bash
chmod +x bazzite-install.sh
./bazzite-install.sh
```

After the reboot, run the script again for **Pass 2** — compiles the driver inside a Distrobox container and enrolls your fingerprint:
```bash
./bazzite-install.sh
```

Each script handles everything:
1. Automatically detect your Elan sensor
2. Install build dependencies
3. Clone and compile `libfprint` (`elanmoc2` branch)
4. Add your sensor ID to the driver if missing
5. Install and configure `fprintd`
6. Enable PAM authentication
7. Launch fingerprint enrollment

---

## Usage after installation

**Enroll a finger:**
```bash
fprintd-enroll -f right-index-finger
```
Available fingers: `right-index-finger`, `right-middle-finger`, `left-index-finger`, `left-middle-finger`, etc.

**List enrolled fingerprints:**
```bash
fprintd-list $USER
```

**Delete all fingerprints:**
```bash
fprintd-delete $USER
```

**Re-enroll (if a previous enrollment exists):**
```bash
fprintd-delete $USER
fprintd-enroll -f right-index-finger
```

**Manage via GUI:**
```bash
gnome-control-center users
```
→ "Fingerprint Login" section

---

## Known limitations
- Fingerprint authentication **does not work on the GDM login screen** (known Linux limitation)
- Works for: `sudo`, screen unlock, in-session authentication
- **Bazzite:** the compiled library is installed to `/usr/local/lib64/`. This path survives updates but may need to be re-registered after a major `rpm-ostree` rebase (re-run the script from pass 2)

---

## Troubleshooting

If after installation you can no longer log in (password rejected), see [RECOVERY.md](./RECOVERY.md).

**Fedora only:** If enrollment fails with `No devices available`, the library path may not be registered. The script handles this automatically, but if it persists:
```bash
echo '/usr/local/lib64' | sudo tee /etc/ld.so.conf.d/local-lib64.conf
sudo ldconfig
sudo systemctl restart fprintd
```

**Bazzite:** If enrollment fails with `EnrollStart failed: PrintsNotDeletedFromDevice`, a previous enrollment is stored on the chip. Delete it first:
```bash
fprintd-delete $USER
fprintd-enroll -f right-index-finger
```

---

## Compatibility

| Distro | Script | Tested |
|---|---|---|
| Ubuntu 24+ | `debian-install.sh` | ✅ |
| Debian 12+ | `debian-install.sh` | ⚠️ (untested) |
| Linux Mint 22+ | `debian-install.sh` | ✅ |
| Fedora 43+ | `fedora-install.sh` | ✅ |
| Bazzite (latest) | `bazzite-install.sh` | ✅ |
| Arch | — | ❌ (coming soon) |

---

## Contributing
If you have a different Elan sensor and the script worked for you, open an issue or a PR with your machine model and PID (`lsusb`).

---

## License
MIT