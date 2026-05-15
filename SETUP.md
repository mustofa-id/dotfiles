# Setup guides

Personal reference for machine-specific setup tasks.

## Setting Gnome UI

```bash
gsettings (get|set|describe|range) org.gnome.desktop.interface gtk-theme <value>
```

To get all keys: `gsettings list-keys org.gnome.portal`.

## Private/Incognito Default Browser

Create desktop file, e.g. `~/.local/share/applications/google-chrome-incognito.desktop`:

```ini
[Desktop Entry]
Name=Google Chrome (Incognito)
GenericName=Web Browser
Comment=Access the Internet with incognito mode
Exec=/usr/bin/google-chrome-stable --incognito %u
Icon=google-chrome
Type=Application
Terminal=false
Categories=Network;WebBrowser;
StartupWMClass=Google-chrome
MimeType=x-scheme-handler/unknown;x-scheme-handler/about;application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xhtml_xml;application/xml;image/gif;image/jpeg;image/png;image/webp;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;
```

Then set as default:

```bash
xdg-settings set default-web-browser google-chrome-incognito.desktop
```

For Firefox: `Exec=firefox -private-window %u`.

## Fingerprint Setup

Edit `/etc/pam.d/swaylock`:

```conf
#%PAM-1.0

auth      sufficient   pam_unix.so try_first_pass likeauth nullok
auth      sufficient   pam_fprintd.so max-tries=3
auth      include      system-local-login

account   include      system-local-login
password  include      system-local-login
session   include      system-local-login
```

## Battery Charging Limit

Temporary:

```bash
echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold
```

Persistent (systemd) — create `/etc/systemd/system/battery-charge-limit.service`:

```ini
[Unit]
Description=Set battery charge limit
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now battery-charge-limit.service
```

Persistent (udev) — create `/etc/udev/rules.d/90-battery-charge-limit.rules`:

```conf
ACTION=="add", SUBSYSTEM=="power_supply", RUN+="/bin/sh -c 'echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold'"
```

```bash
sudo udevadm control --reload
sudo udevadm trigger
```

## Podman — allow low ports for rootless containers

```bash
sudo sysctl net.ipv4.ip_unprivileged_port_start=80
```

Persistent:

```bash
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-rootless-ports.conf
sudo sysctl --system
```

## Btrfs Snapshot

Using `snapper` with automatic snapshots on a timer.

```bash
# Install
sudo pacman -S snapper

# Enable/start timer (takes snapshots every hour by default)
sudo systemctl enable --now snapper-timeline.timer

# Cleanup (keeps hourly/daily/weekly/monthly/yearly)
sudo systemctl enable --now snapper-cleanup.timer
```

For pacman integration (auto snapshot before/after installs), install `snap-pac`:

```bash
sudo pacman -S snap-pac
```

Manual snapshot:

```bash
sudo snapper -c root create -d "before update"
```

List/rollback:

```bash
sudo snapper -c root list
# Restore a snapshot (boot from snapshot or use snapper undochange)
```

> Config files: `/etc/snapper/configs/root`, `/etc/snapper/configs/home`

## Auto Unlock Keyring

Unlock the GNOME/GTK keyring automatically on login by hooking into PAM.

Edit `/etc/pam.d/login`:

Add `auth` and `session` lines for `pam_gnome_keyring.so`:

```conf
# At the end of the auth section:
auth       optional     pam_gnome_keyring.so

# At the end of the session section:
session    optional     pam_gnome_keyring.so auto_start
```
