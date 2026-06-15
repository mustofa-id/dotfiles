# AGENTS.md

## Install

```bash
# dry-run by default
./install

# apply (create symlinks)
./install --apply
```

Maps:

| Repo dir    | Target                     |
| ----------- | -------------------------- |
| `config/*`  | `~/.config/*`              |
| `home/*`    | `~/.*`                     |
| `systemd/*` | `~/.config/systemd/user/*` |

Existing non-symlink files at target are skipped. Items listed in `.exclude` are skipped (and their existing symlinks are removed). Currently excludes: `alacritty`.

## Notable configs

| Dir/File                             | Purpose                   |
| ------------------------------------ | ------------------------- |
| `config/niri/`                       | Niri Wayland compositor   |
| `config/waybar/`                     | Status bar                |
| `config/fuzzel/`                     | App launcher              |
| `config/foot/`                       | Terminal emulator         |
| `config/mako/`                       | Notifications             |
| `config/prayer/`                     | Prayer notifier settings  |
| `config/swaylock/`                   | Screen locker             |
| `config/gtk-3.0/`, `config/gtk-4.0/` | GTK theme overrides       |
| `config/assets/`                     | Wallpapers and icons      |
| `config/environment.d/`              | User environment vars     |
| `home/.bashrc`                       | Shell config              |
| `home/.fns`                          | Shell functions           |
| `home/.gitconfig`                    | Git config                |
| `systemd/notify-prayer.*`            | Prayer notification timer |

## Repo conventions

- `config/niri/keyboard.kdl` is gitignored (machine-local keyboard config). It is a symlink managed by `config/niri/scripts/swap-xkb` which toggles between `templates/keyboard-default.kdl` and `templates/keyboard-remap.kdl`. Editing it directly risks being overwritten.
- `config/niri/scripts/` contains helper scripts: `notify-prayer`, `osd` (volume/brightness OSD), `swap-xkb` (keyboard layout toggle), `toggle-wfr` (screen recorder), and `utils` (shared functions). Scripts source `utils` for `notify_replace` (replacement-ID notifications using `/tmp/osd-*.id` files).
- `.vscode/settings.json` maps `*.kdl` → `groovy`, `*.toml` → `ini`, `*.service`/`*.timer` → `ini` for syntax highlighting.
- No build/test/lint tooling; plain shell scripts and static config files.
- `config/assets/README.md` documents wallpaper and icon sources.
- `SETUP.md` has machine-specific setup guides (not relevant for agent tasks).
- Shell functions and scripts generally use `local` variables, guard required args/paths, and print concise terminal messages.
- Commits use multiline messages: a short summary line (with `feat:`, `fix:`, etc. prefix), then a blank line, then a detailed body.

## Prayer notifier

`systemd/notify-prayer.*` runs `%h/.config/niri/scripts/notify-prayer` every minute. The script reads `~/.config/prayer/config`, caches daily API responses in `~/.cache/prayer/`, and falls back to `~/.prayer-location` when latitude/longitude are empty in the config.

## `notification_mode` function (`home/.fns`)

Three mako modes: `default`, `dnd` (invisible), `private` (app name only).

- `notification_mode` — prints current mode.
- `notification_mode <mode>` — switches to that mode.
- Because `makoctl -a` always appends, non-default modes are always stripped first (`makoctl mode -r dnd -r private`) before adding the target. If target is `default`, nothing is added back.
