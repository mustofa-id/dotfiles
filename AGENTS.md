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
| `config/wireplumber/`                | ALSA card properties      |
| `config/prayer/`                     | Prayer notifier settings  |
| `config/swaylock/`                   | Screen locker             |
| `config/gtk-3.0/`, `config/gtk-4.0/` | GTK theme overrides       |
| `config/assets/`                     | Wallpapers and icons      |
| `config/environment.d/`              | User environment vars     |
| `guides/`                            | Long-form write-ups       |
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
- Before committing, show the proposed message in full and wait for explicit approval. Never commit in the same turn as the proposal.
- Stage only paths related to the task. Leave unrelated modified files alone (they are usually in-progress work) and never `git add -A`.

## Microphone / audio

Hardware: `HDA Intel PCH` / `Realtek ALC256`, internal mic at
`alsa_input.pci-0000_00_1f.3.analog-stereo`. Full write-up in
`guides/pipewire-microphone.md`; playback/jack/volume notes in
`guides/pipewire-playback.md`.

**The trap:** udev/`alsactl` restore three capture controls to max at boot —
`Internal Mic Boost` `3/3`, `Capture Volume` `63/63`, `Digital Capture Volume`
`120/120` = ~+90 dB before the ADC. The ADC then saturates with preamp noise
(idle RMS near `0 dBFS`), and any denoiser sounds worse because it only sees noise.

- `config/pipewire/set-mic-gain` pins `0 / 54 / 59` (0 dB boost, +23 dB capture, 0 dB digital), which lands the idle floor near `-45 dBFS`. `systemd/mic-gain.service` runs it after PipeWire starts; it is not triggered by udev, so re-run it after hotplug/profile changes. Raise `CAPTURE` in ~5 step increments if the mic is too quiet; never go back to tapping all three controls at max.
- `api.alsa.soft-mixer` must stay **off** (`config/wireplumber/wireplumber.conf.d/50-alsa-card.conf`). It was briefly enabled to make the GUI slider a software gain after the ADC, but ACP does not apply that per direction: with it on, ACP skips writing the route volume, the DAC amps stay at `0` (`-65.25 dB`, pin `off`) on every sink creation, and **every output is silent regardless of the slider**. It also adds a second invisible volume layer — ALSA-only apps (`Concat` links `libasound.so.2` and never loads `libpulse`) write `Master`/`PCM` directly, so alsamixer and the system slider disagree and audio goes missing when one of them lands on zero.
- With soft-mixer off there is exactly one volume stage: the PipeWire slider *is* alsamixer's `Master`, verified in both directions (same dB), and the mic slider maps to hardware gain (`25%` -> `Mic Boost 0` / `Capture 54`). Raising the mic slider can therefore re-saturate the ADC — keep it near 25%.
- `config/pipewire/fix-sink` recovers a dead analog sink without restarting PipeWire, by toggling the card profile off/on (ACP then reopens the device). Use it when the sink fails to resume (`spa.alsa: 'front:0': playback open failed: Device or resource busy`) and the system falls back to `auto_null`; WirePlumber does not retry a node that failed to be created.
- Filter chains in `config/pipewire/pipewire.conf.d/` must set `node.target` to the physical source. `stream.capture.sink = true` makes them capture the speaker monitor instead.
- Each chain is `highpass -> denoiser -> amp_mono (Gain 5.4) -> hardLimiter (-1 dBFS)`. The limiter is from `swh-plugins` and exists because DeepFilterNet boosts transients up to +13 dB on its own, which pushed real recordings past 0 dBFS. `swh`'s `fastLookaheadLimiter` is stereo-only and silently outputs silence in a mono graph — use `hard_limiter_1413`.
- Sources: raw `alsa_input.*`, `rnnoise_microphone` (lightweight), `deepfilter_microphone` (better quality, from `deepfilternet-plus-bin`). `Mod+Ctrl+M` cycles them; WirePlumber persists the pick in `~/.local/state/wireplumber/default-nodes`.
- Verify with `pw-record --target <source> /tmp/x.wav` then check levels; idle noise floor should be ~`-45 dBFS`, not `-6 dBFS`.
- `~/.config/wireplumber/` is now tracked here: `config/wireplumber/wireplumber.conf.d/` holds the card properties. Keep it in sync with `./install --apply`.

## Prayer notifier

`systemd/notify-prayer.*` runs `%h/.config/niri/scripts/notify-prayer` every minute. The script reads `~/.config/prayer/config`, caches daily API responses in `~/.cache/prayer/`, and falls back to `~/.prayer-location` when latitude/longitude are empty in the config.

## `notification_mode` function (`home/.fns`)

Three mako modes: `default`, `dnd` (invisible), `private` (app name only).

- `notification_mode` — prints current mode.
- `notification_mode <mode>` — switches to that mode.
- Because `makoctl -a` always appends, non-default modes are always stripped first (`makoctl mode -r dnd -r private`) before adding the target. If target is `default`, nothing is added back.
