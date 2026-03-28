# elanmoc2-driver

Automated install script for **Elan** fingerprint readers not natively supported on Ubuntu.

Tested on a **LG Gram 17** with sensor `04f3:0ca2` (ELAN:ARM-M4).

---

## Why this script?

The version of `libfprint` available in Ubuntu's official repositories does not support all recent Elan sensors. This script compiles and installs the community branch [`elanmoc2`](https://gitlab.freedesktop.org/Depau/libfprint/) of `libfprint`, and automatically injects your sensor ID into the source code if needed.

---

## Requirements

- Ubuntu 22.04 or later
- sudo privileges
- Internet connection

---

## Installation

```bash
git clone https://github.com/navycrow/elanmoc2-driver.git
cd elanmoc2-driver
chmod +x install.sh
./install.sh
```

The script handles everything:

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

**Manage via GUI:**
```bash
gnome-control-center users
```
→ "Fingerprint Login" section

---

## Known limitations

- Fingerprint authentication **does not work on the GDM login screen** (known Linux limitation)
- Works for: `sudo`, screen unlock, in-session authentication

---

## Troubleshooting

If after installation you can no longer log in (password rejected), see [RECOVERY.md](./RECOVERY.md).

---

## Compatibility

| Distro | Supported |
|---|---|
| Ubuntu 22.04+ | ✅ |
| Debian 12+ | ✅ (untested) |
| Fedora | ❌ (coming soon) |
| Arch | ❌ (coming soon) |

---

## Contributing

If you have a different Elan sensor and the script worked for you, open an issue or a PR with your machine model and PID (`lsusb`).

---

## License

MIT