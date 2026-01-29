# Dotfiles

Dry-run by default; `--apply` flag creates symlinks from `config/` → `~/.config` and `home/` → `~`. To exclude files from installation, list them in the `.exclude` file (see `.exclude.example`).

## Packages

`niri` `waybar` `fuzzel` `swaybg` `swayosd` `swaylock` `mako` `xdg-desktop-portal` `xdg-desktop-portal-gnome` `xdg-desktop-portal-gtk` `alacritty` `foot` `cliphist` `rofimoji` `wl-clipboard`

## Setting Gnome UI

Using `gsettings` command like `gsettings (get|set|describe|range) org.gnome.desktop.interface gtk-theme <value>`. To get all keys run `gsettings list-keys org.gnome.portal`.

> _PS. No best practices, no DRY, etc. it's just work._
