# Recovery procedure

If after installation you can no longer log in (password rejected on the login screen), follow this procedure.

---

## Symptoms

- The login screen rejects your password even though it is correct
- You cannot open a session

---

## Cause

The PAM configuration (`/etc/pam.d/common-auth`) was modified to enable fingerprint authentication. In some cases, this change can block classic password-based login.

---

## Recovery steps

### Step 1 — Access recovery mode

At startup, hold the **Shift** key (or **Escape**) to display the GRUB menu.

Select:
```
Advanced options for Ubuntu
```
Then:
```
Ubuntu ... (recovery mode)
```

### Step 2 — Open a root shell

In the recovery menu, choose **root** → you get a shell with root privileges.

### Step 3 — Remount the filesystem as writable

```bash
mount -o remount,rw /
```

### Step 4 — Reset PAM configuration

```bash
pam-auth-update --force
```

In the interactive menu, **uncheck** "Fingerprint authentication" if present, then confirm with Ok.

Or edit the file directly:

```bash
nano /etc/pam.d/common-auth
```

Remove any line containing `fprintd`, save with `Ctrl+O` and exit with `Ctrl+X`.

### Step 5 — Reboot

```bash
reboot
```

Your password works again.

---

## After recovery

You can re-enable fingerprint authentication via the GUI:

```bash
gnome-control-center users
```

Or re-run only the PAM step:

```bash
sudo pam-auth-update --enable fprintd
```