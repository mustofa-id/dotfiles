# Dotfiles

Dry-run by default; `--apply` flag creates symlinks from `config/` → `~/.config` and `home/` → `~`. To exclude files from installation, list them in the `.exclude` file (see `.exclude.example`).

## Packages

`niri` `waybar` `fuzzel` `swaybg` `swayosd` `swaylock` `mako` `xdg-desktop-portal` `xdg-desktop-portal-gnome` `xdg-desktop-portal-gtk` `alacritty` `foot` `cliphist` `rofimoji` `wl-clipboard networkmanager bluez-utils bluez wf-recorder`

## Setting Gnome UI

Using `gsettings` command like `gsettings (get|set|describe|range) org.gnome.desktop.interface gtk-theme <value>`. To get all keys run `gsettings list-keys org.gnome.portal`.

## Private/Incognito Default Browser

This is handy if you want to safely open unknown links without letting them access your browser session or personal data.

Create desktop file, for example (Chrome Incognito): `~/.local/share/applications/google-chrome-incognito.desktop`.

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

Then set it as default browser:

```bash
xdg-settings set default-web-browser google-chrome-incognito.desktop
```

For Firefox, the `Exec` line should be: `firefox -private-window %u`.

### Fingerprint Setup

> _TODO_

### Battery Charing Limit

> _TODO_

### Btrfs Snapshot

> _TODO_

### Auto Unlock Keyring

---

> _PS. No best practices, no DRY, etc. it's just work._
