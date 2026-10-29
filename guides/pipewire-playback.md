# PipeWire Playback, Jack Switching and Volume

Playback side of the ALC256 on this machine: why outputs went silent, why the
3.5 mm jack did not switch, and why an app's volume never matched the system
slider. Microphone side is in `guides/pipewire-microphone.md`.

## Symptoms

- Plugging headphones into the 3.5 mm jack gave silence from both the headphones
  and the speakers; unplugging did not bring the speakers back.
- `alsamixer` and the PipeWire/WirePlumber slider disagreed. Apps that only know
  ALSA could change their own loudness but the system slider never followed.
- Audio disappeared entirely after using and closing an app, and stayed gone
  (the sink was replaced by `auto_null`, "Dummy Output") until a service restart.

All three had one root cause plus one independent bug.

## Root cause: `api.alsa.soft-mixer` was set on the whole card

The property was added for the microphone (see the mic guide) in
`~/.config/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf`, matching
`~alsa_card.*`. **ACP does not apply it per direction.**

With `soft-mixer = true`, ACP skips writing the route volume to the hardware, so
on every sink creation the DAC amps are left at zero:

```text
Speaker Playback Volume    0/87    0%   -65.25 dB  [off]
Headphone Playback Volume  0/87    0%   -65.25 dB  [off]
```

Both ports are muted at the codec, so the PipeWire slider does nothing — moving
it to 100 % still produced `-65.25 dB` at the DAC. That is the "no sound" and
the "jack does not switch" symptom: the route may change, but every destination
is silent.

It also created a second volume stage. ALSA-only programs write the hardware
mixer directly, and with soft-mixer on, PipeWire treated that as an invisible
extra gain under its own software volume:

```text
stream volume  x  PipeWire volume  x  hardware mixer (untouched by PipeWire)
```

Example: `Concat` (`concat-bin`) links `libasound.so.2` and **never loads
`libpulse` or `libpipewire`** — `objdump -p` shows no pulse dependency and the
only dlopen string is `libasound.so.2`. It writes `Master`/`PCM` straight to the
codec, so its volume lived in a layer the system slider never saw.

## Fix

`config/wireplumber/wireplumber.conf.d/50-alsa-card.conf` pins
`api.alsa.soft-mixer = false` for `~alsa_card.*`. ACP then drives the hardware
mixer and there is exactly one volume stage:

```text
PipeWire sink volume  =  alsamixer Master  =  what the app writes
```

Verified in both directions:

| Action | Result |
| --- | --- |
| `pactl set-sink-volume 50%` | `Master 63 [72%] [-18.00 dB]`, sink `-18.06 dB` |
| `pactl set-sink-volume 100%` | `Master 87 [100%] [0.00 dB]`, `Speaker 87 [100%] [on]` |
| `amixer sset Master 60%` | sink reports `-26.25 dB` (Master step 52 = `-26.2 dB`) |
| `amixer sset PCM 50%` | sink volume follows |
| `amixer sset Speaker 50%` | sink volume follows |

So whatever element an ALSA-only app touches, the PipeWire slider tracks it.

Consequence for the microphone: the source slider is now **hardware** gain.
`25 %` maps to `Mic Boost 0` / `Capture 54` (+23 dB), which is the sane point.
Raising it can re-saturate the ADC. See `guides/pipewire-microphone.md`.

## Jack switching

With soft-mixer off, ACP owns the route and mutes the inactive port. Measured:

| State | Active Port | Speaker amp | Headphone amp |
| --- | --- | --- | --- |
| plugged in | `analog-output-headphones` | `0% [off]` | `87 [100%] [on]` |
| plugged out | `analog-output-speaker` | `87 [100%] [on]` | `0% [off]` |

WirePlumber's `find-best-routes` only needs the port availability to change;
`analog-output-headphones` reports `not available` while empty and `yes` once
plugged, which forces the switch. `Auto-Mute Mode` stays `Enabled` in the codec;
it is redundant with the route mute but harmless.

Volume is remembered **per port**, not per sink:

```text
alsa_card...:output:analog-output-speaker    channelVolumes [0.124989]   -> 50 %
alsa_card...:output:analog-output-headphones channelVolumes [0.063997]   -> 40 %
```

So plugging in can change the loudness by design. Set the slider once with the
headphones connected and it is remembered.

## The dead sink (`auto_null`)

Separate from soft-mixer: when the analog sink fails to resume, WirePlumber does
not retry.

```text
spa.alsa: 'front:0': playback open failed: Device or resource busy
pw.node: (alsa_output...-71) suspended -> error (Start error: Device or resource busy)
mod.adapter: can't get format: Device or resource busy
wireplumber: s-monitors: Failed to create ALSA node ... Object activation aborted
```

`alsa.lua` has a recovery path for *runtime* node errors (profile off, reopen,
up to 3 attempts), but a node that fails during **creation** is never retried, so
the system falls back to `auto_null` and stays there.

`config/pipewire/fix-sink` reopens the card by toggling the profile off/on,
which is the same mechanism WirePlumber's recovery uses, and waits for the sink
to return. Volume survives the toggle.

```bash
~/.config/pipewire/fix-sink
```

## Verification

```bash
pactl list short sinks
pactl get-sink-volume @DEFAULT_SINK@
amixer -c0 sget Master | grep 'Mono:'
```

Sink dB and `Master` dB must be equal. For the jack:

```bash
pactl list sinks | grep -E 'Active Port|Volume: front'
for c in Speaker Headphone; do amixer -c0 sget "$c" | grep 'Front Left'; done
```

## Gotchas

- Do not re-enable `soft-mixer` to "protect" the mic slider. It is not
  per-direction, and it silences playback.
- `api.acp.auto-port` / `api.acp.auto-profile` are `false` by WirePlumber design
  (`/usr/share/wireplumber/scripts/monitors/alsa.lua`). Route selection is
  WirePlumber's job, not ACP's — do not "fix" it by turning ACP auto-port on.
- `device.routes.mute-on-alsa-playback-removed` defaults to `false`; leave it
  alone, or unplugging headphones mutes everything.
- AppImages carry their own audio stack. Check before blaming PipeWire:
  `objdump -p <app> | grep NEEDED` and `7z l <app>.AppImage | grep -i -E 'lib(pulse|asound|sdl)'`.
