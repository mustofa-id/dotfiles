# AGENTS.md

## Install

```bash
./install         # dry-run by default
./install --apply # create symlinks
```

Maps:

| Repo dir    | Target                     |
| ----------- | -------------------------- |
| `config/*`  | `~/.config/*`              |
| `home/*`    | `~/.*`                     |
| `systemd/*` | `~/.config/systemd/user/*` |

- Existing non-symlink files at the target are skipped with a warning; symlinks (incl. broken) are replaced.
- Real directories are recursed into, so `config/niri/` links file-by-file rather than replacing `~/.config/niri`.
- `.exclude` lists names to skip (currently `alacritty`); existing symlinks for them are removed.

## Notable configs

| Dir/File                             | Purpose                   |
| ------------------------------------ | ------------------------- |
| `config/niri/`                       | Niri Wayland compositor   |
| `config/waybar/`                     | Status bar                |
| `config/fuzzel/`                     | App launcher              |
| `config/foot/`                       | Terminal emulator         |
| `config/mako/`                       | Notifications             |
| `config/pipewire/`                   | Mic filter chains + gain  |
| `config/prayer/`                     | Prayer notifier settings  |
| `config/swaylock/`                   | Screen locker             |
| `config/gtk-3.0/`, `config/gtk-4.0/` | GTK theme overrides       |
| `config/assets/`                     | Wallpapers and icons      |
| `config/environment.d/`              | User environment vars     |
| `home/.bashrc`                       | Shell config              |
| `home/.fns`                          | Shell functions           |
| `home/.gitconfig`                    | Git config                |
| `systemd/notify-prayer.*`            | Prayer notification timer |
| `systemd/mic-gain.service`           | Pins mic hardware gain    |

## Repo conventions

- `config/niri/keyboard.kdl` is gitignored (machine-local keyboard config). It is a symlink managed by `config/niri/scripts/swap-xkb`, which toggles between `templates/keyboard-default.kdl` and `templates/keyboard-remap.kdl`. Editing it directly risks being overwritten.
- `config/niri/scripts/` has `notify-prayer`, `osd` (volume/brightness OSD), `swap-xkb`, `toggle-wfr` (screen recorder), `toggle-mnr` (mic source cycle), and `utils`. Scripts source `utils` for `notify_replace` (replacement-ID notifications using `/tmp/osd-*.id` or `ID_FILE`).
- `.vscode/settings.json` maps `*.kdl` → `groovy`, `*.toml` → `ini`, `*.service`/`*.timer`/`config` → `ini`.
- No build/test/lint tooling; plain shell scripts and static config files.
- `config/assets/README.md` documents wallpaper and icon sources.
- `SETUP.md` has machine-specific setup guides (not relevant for agent tasks).
- Shell functions and scripts use `local` variables, guard required args/paths, and print concise terminal messages.
- Commits use multiline messages: a short summary line (`feat:`, `fix:`, etc.), a blank line, then details.

## Microphone / audio

Hardware: `HDA Intel PCH` / `Realtek ALC256`, internal mic at
`alsa_input.pci-0000_00_1f.3.analog-stereo`. Full write-up in `guides/rnnoise-pipewire.md`.

**The trap:** udev/`alsactl` restore three capture controls to max at boot —
`Internal Mic Boost` `3/3`, `Capture Volume` `63/63`, `Digital Capture Volume`
`120/120` = ~+90 dB before the ADC. The ADC then saturates with preamp noise
(idle RMS near `0 dBFS`), and any denoiser sounds worse because it only sees noise.

- `config/pipewire/set-mic-gain` pins `0 / 52 / 60` (0 dB boost, +21.75 dB capture, 0 dB digital), which lands the idle floor near `-44 dBFS`. `systemd/mic-gain.service` runs it 2 s after PipeWire starts; it is not triggered by udev, so re-run it after hotplug/profile changes. Raise `CAPTURE` in ~5 step increments if the mic is too quiet; never go back to tapping all three controls at max.
- `api.alsa.soft-mixer = true` (in the untracked `~/.config/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf`) makes the GUI volume slider *software* gain applied after the ADC. That is intentional — it cannot re-saturate the hardware. Never "fix quiet mic" by raising hardware capture controls.
- Filter chains in `config/pipewire/pipewire.conf.d/` must set `node.target` to the physical source. `stream.capture.sink = true` makes them capture the speaker monitor instead.
- Each chain is `highpass -> denoiser -> amp_mono (Gain 5.4) -> hardLimiter (-1 dBFS)`. The limiter is from `swh-plugins` and exists because DeepFilterNet boosts transients up to +13 dB on its own, which pushed real recordings past 0 dBFS. `swh`'s `fastLookaheadLimiter` is stereo-only and silently outputs silence in a mono graph — use `hard_limiter_1413`.
- Sources: raw `alsa_input.*`, `rnnoise_microphone` (lightweight), `deepfilter_microphone` (better quality, from `deepfilternet-plus-bin`). `Mod+Ctrl+M` cycles them; WirePlumber persists the pick in `~/.local/state/wireplumber/default-nodes`.
- Verify with `pw-record --target <source> /tmp/x.wav` then check levels; idle noise floor should be ~`-44 dBFS`, not `-6 dBFS`.
- `~/.config/wireplumber/` is not tracked by this repo; only `config/pipewire/` is.

## Prayer notifier

`systemd/notify-prayer.*` runs `%h/.config/niri/scripts/notify-prayer` every minute. The script reads `~/.config/prayer/config`, caches daily API responses in `~/.cache/prayer/`, and falls back to `~/.prayer-location` when latitude/longitude are empty in the config.

## `notification_mode` function (`home/.fns`)

Three mako modes: `default`, `dnd` (invisible), `private` (app name only).

- `notification_mode` — prints current mode.
- `notification_mode <mode>` — switches to that mode.
- Because `makoctl -a` always appends, non-default modes are always stripped first (`makoctl mode -r dnd -r private`) before adding the target. If target is `default`, nothing is added back.
