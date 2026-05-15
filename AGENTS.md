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
| `config/swaylock/`                   | Screen locker             |
| `config/gtk-3.0/`, `config/gtk-4.0/` | GTK theme overrides       |
| `config/assets/`                     | Wallpapers and icons      |
| `config/environment.d/`              | User environment vars     |
| `home/.bashrc`                       | Shell config              |
| `home/.fns`                          | Shell functions           |
| `home/.gitconfig`                    | Git config                |
| `systemd/notify-prayer.*`            | Prayer notification timer |

## Repo conventions

- `config/niri/keyboard.kdl` is gitignored (machine-local keyboard config).
- `.vscode/settings.json` maps `*.kdl` → `groovy`, `*.toml` → `ini`, `*.service`/`*.timer` → `ini` for syntax highlighting.
- No build/test/lint tooling; plain shell scripts and static config files.
- `config/assets/README.md` documents wallpaper and icon sources.
- `SETUP.md` has machine-specific setup guides (not relevant for agent tasks).
