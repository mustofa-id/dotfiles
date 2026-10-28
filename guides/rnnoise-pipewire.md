# RNNoise Microphone with PipeWire

Lightweight microphone noise suppression using **PipeWire's native filter-chain** and the **RNNoise LADSPA plugin**.

This setup does **not** require EasyEffects and automatically creates an `RNNoise Microphone` source when PipeWire starts.

> **Read [Hardware capture gain](#0-hardware-capture-gain-read-this-first) before tuning anything else.**
> No denoiser can rescue a capture path whose analog gain is maxed out — RNNoise will just
> gate noise, which sounds worse than no filter at all.

## Requirements

- Arch Linux
- PipeWire
- WirePlumber
- `noise-suppression-for-voice`
- `deepfilternet-plus-bin` (optional, better quality)
- `swh-plugins` (limiter ceiling)

Install RNNoise:

```bash
sudo pacman -S noise-suppression-for-voice
```

Verify the LADSPA plugin:

```bash
listplugins /usr/lib/ladspa/librnnoise_ladspa.so
```

Expected plugins include:

```text
noise_suppressor_mono
noise_suppressor_stereo
```

For a voice microphone, use the **mono** plugin.

---

## 0. Hardware capture gain (read this first)

Noise suppression only works if the ADC sees a clean, unsaturated signal. On this
laptop (`HDA Intel PCH` / `Realtek ALC256`, ASUS X1404) ALSA exposes three
capture gain stages, and udev/`alsactl` restores **all of them to maximum** at boot:

| Control | Max value | Gain at max |
|---|---|---|
| `Internal Mic Boost Volume` | `3,3` | +30 dB |
| `Capture Volume` | `63,63` | +30 dB |
| `Digital Capture Volume` | `120,120` | +30 dB |

That is ~+90 dB of gain in front of the ADC. The preamp's own noise floor then
saturates the converter and the idle level sits near **-6 dBFS** — regardless of
what the PipeWire volume slider says.

Symptom: recording is loud but sounds like a wall of hiss/rumble, and RNNoise
makes it worse because it only ever sees noise and gates the voice away.

Check the current values:

```bash
for n in 9 7 48; do amixer -c0 cget numid=$n | grep -E 'name=|values='; done
```

Pin a sane gain stage:

```bash
# 0 dB analog boost, +21.75 dB capture, 0 dB digital
amixer -c0 cset "name='Internal Mic Boost Volume'" 0
amixer -c0 cset "name='Capture Volume'" 52
amixer -c0 cset "name='Digital Capture Volume'" 60
```

`config/pipewire/set-mic-gain` does this, and `systemd/mic-gain.service` runs it
after PipeWire starts so a reboot cannot undo it.

With `api.alsa.soft-mixer = true` (see `wireplumber.conf.d/alsa-soft-mixer.conf`)
the PipeWire/WirePlumber volume slider is **software gain applied after the ADC**.
Use it for level adjustments — it cannot re-saturate the hardware. Hardware gain
belongs to `set-mic-gain` only.

Verify the result before touching any filter:

```bash
pw-record --target alsa_input.pci-0000_00_1f.3.analog-stereo /tmp/raw.wav
# idle noise floor should be around -44 dBFS, not -6 dBFS
```

Level budget after the fix (measured through the laptop speakers, so treat as a
ballpark): idle floor `-44 dBFS`, speech peaks `-9 dBFS` for a person at
normal distance. Both denoisers are level-transparent (output peak tracks input
peak within 1 dB). Each filter chain then adds a fixed `amp_mono` makeup gain of
`5.4` (+14.6 dB) **after** the denoiser, so loudness can be raised without
amplifying analog noise. Tune that one number, or `CAPTURE` in `set-mic-gain`.

Caveat measured on this machine: DeepFilterNet is **not** level-transparent the
way RNNoise is. On speech-like transients it boosted the raw signal by up to
+13 dB on its own, which pushed a real recording to `+3 dBFS` (i.e. clipped in
any s16 app for a couple of samples). Each chain therefore ends with an
`swh-plugins` `hardLimiter` at `-1 dBFS`:

```ini
{
  type = ladspa
  name = lim
  plugin = ladspa/hard_limiter_1413
  label = hardLimiter
  control = { "dB limit" = -1.0 "Wet level" = 1.0 "Residue level" = 0.0 }
}
```

Verified offline: peak `-0.00` -> `-1.00 dBFS`, RMS unchanged (`-24.1`), so it
only touches overs. With the ceiling in place the makeup gain can be raised
past `2.0` safely; `swh`'s `fastLookaheadLimiter` is stereo-only and does not
pass audio in a mono graph — don't waste time on it.

---

## 1. Identify the physical microphone

List PipeWire devices:

```bash
wpctl status
```

Example physical microphone:

```text
alsa_input.pci-0000_00_1f.3.analog-stereo
```

Inspect it if necessary:

```bash
wpctl inspect alsa_input.pci-0000_00_1f.3.analog-stereo
```

---

## 2. Create the PipeWire filter-chain

Create the configuration directory:

```bash
mkdir -p ~/.config/pipewire/pipewire.conf.d
```

Create:

```text
~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf
```

Configuration:

```ini
context.modules = [
  {
    name = libpipewire-module-filter-chain

    args = {
      node.description = "RNNoise Microphone"
      media.name = "RNNoise Microphone"

      filter.graph = {
        nodes = [
          {
            type = builtin
            name = hp
            label = bq_highpass

            control = {
              "Freq" = 85
              "Q" = 0.707
            }
          }
          {
            type = ladspa
            name = rnnoise
            plugin = ladspa/librnnoise_ladspa
            label = noise_suppressor_mono

            control = {
              "VAD Threshold (%)" = 30.0
            }
          }
        ]

        links = [
          { output = "hp:Out" input = "rnnoise:Input" }
        ]
      }

      capture.props = {
        node.name = "capture.rnnoise"
        node.description = "RNNoise Microphone Capture"

        node.target = "alsa_input.pci-0000_00_1f.3.analog-stereo"
        node.passive = true

        audio.channels = 1
        audio.position = [ MONO ]
      }

      playback.props = {
        node.name = "rnnoise_microphone"
        node.description = "RNNoise Microphone"
        media.name = "RNNoise Microphone"
        media.class = "Audio/Source"

        audio.channels = 1
        audio.position = [ MONO ]
      }
    }
  }
]
```

### Important: `node.target`

The filter must explicitly target the physical microphone:

```ini
node.target = "alsa_input.pci-0000_00_1f.3.analog-stereo"
```

Do **not** use:

```ini
stream.capture.sink = true
```

That can cause the filter to capture the **speaker/output monitor** instead of the microphone.

The desired routing is:

```text
Physical microphone
        |
        v
alsa_input.*
        |
        v
capture.rnnoise
        |
        v
      RNNoise
        |
        v
rnnoise_microphone
```

---

## 3. Why mono?

The physical microphone may expose two channels:

```text
audio.channels = 2
audio.position = [ FL, FR ]
```

RNNoise voice suppression does not need stereo processing.

The filter therefore converts the microphone to:

```ini
audio.channels = 1
audio.position = [ MONO ]
```

This also reduces CPU usage compared with stereo processing.

---

## 4. Restart PipeWire

After creating or modifying the configuration:

```bash
systemctl --user restart pipewire
```

Check the resulting nodes:

```bash
wpctl status
```

Expected:

```text
Sources:
   Built-in Audio Analog Stereo

Filters:
   - filter-chain-XXXX-XX
       capture.rnnoise [Stream/Input/Audio]
     * rnnoise_microphone [Audio/Source]
```

---

## 5. Verify microphone routing

Use:

```bash
pw-link -l
```

The filter should receive audio from the physical microphone:

```text
capture.rnnoise:input_FL
    |<- alsa_input.pci-0000_00_1f.3.analog-stereo:capture_FL

capture.rnnoise:input_FR
    |<- alsa_input.pci-0000_00_1f.3.analog-stereo:capture_FR
```

### Incorrect routing

If you see:

```text
capture.rnnoise:input_FL
    |<- alsa_output...:monitor_FL
```

the filter is processing the **speaker output**, not the microphone.

Check that `stream.capture.sink` is not present and that `node.target` points to the physical microphone.

---

## 6. Set RNNoise as the default microphone

Find the RNNoise source ID:

```bash
wpctl status
```

For example:

```text
37. rnnoise_microphone
```

Set it as the default:

```bash
wpctl set-default 37
```

Verify:

```bash
wpctl inspect @DEFAULT_AUDIO_SOURCE@
```

It should show:

```text
node.name = "rnnoise_microphone"
```

WirePlumber persists the default-device selection, so an additional WirePlumber rule is not required just to make RNNoise the default source.

---

## 7. VAD Threshold

The important setting is:

```ini
"VAD Threshold (%)" = 30.0
```

The final tested value is:

**30%**

The behavior observed during tuning:

| Threshold | Behavior |
|-----------|----------|
| `50%` | More aggressive; quiet words may get chopped |
| **`30%`** | **Good balance; preserves quiet speech** |
| `25%` | More sensitive; potentially more background noise |
| `20%` | Very sensitive; more background noise may pass |

For this setup:

```ini
control = {
  "VAD Threshold (%)" = 30.0
}
```

is the recommended value.

---

## 8. Test the microphone

Record through the RNNoise source:

```bash
pw-record --target rnnoise_microphone test-rnnoise.wav
```

Test:

- quiet speech
- normal speech
- words at the beginning/end of sentences
- pauses
- keyboard noise
- fan noise
- other ambient noise

Play the recording:

```bash
pw-play test-rnnoise.wav
```

---

## Audio Flow

```text
+----------------------+
|  Physical Microphone |
+----------+-----------+
           |
           v
+------------------------------+
| ALSA / PipeWire              |
| alsa_input.*                 |
+----------+-------------------+
           |
           v
+------------------------------+
| capture.rnnoise              |
| Mono                         |
+----------+-------------------+
           |
           v
+------------------------------+
| RNNoise LADSPA               |
| noise_suppressor_mono        |
| VAD Threshold: 30%           |
+----------+-------------------+
           |
           v
+------------------------------+
| rnnoise_microphone           |
| Audio/Source                 |
+----------+-------------------+
           |
     +-----+-----+---------+
     |           |         |
     v           v         v
  Discord      Zoom     Browser
```

---

## 9. DeepFilterNet as an alternative (recommended for natural voice)

RNNoise is tiny and low-CPU, but it is an old model: it muffles consonants and
sounds "underwater" compared to what Windows/Realtek's array processing does.
`deepfilternet-plus-bin` ships a LADSPA plugin that sounds markedly closer to a
studio mic, at the cost of some CPU.

Plugin:

```bash
listplugins /usr/lib/ladspa/libdeep_filter_ladspa.so
# DeepFilter Mono (deep_filter_mono)
# DeepFilter Stereo (deep_filter_stereo)
```

`config/pipewire/pipewire.conf.d/98-deepfilter.conf` registers a second source,
`deepfilter_microphone`, with the same high-pass stage. Both sources coexist:

```text
alsa_input.pci-0000_00_1f.3.analog-stereo   raw
rnnoise_microphone                          lightweight
deepfilter_microphone                       best quality
```

`Mod+Ctrl+M` (`config/niri/scripts/toggle-mnr`) cycles raw -> RNNoise ->
DeepFilter. The choice is persisted by WirePlumber, so it survives reboots.

---

## Configuration Files

The relevant configuration is:

```text
~/.config/
├── pipewire/
│   ├── set-mic-gain
│   └── pipewire.conf.d/
│       ├── 98-deepfilter.conf
│       └── 99-input-denoising.conf
│
├── wireplumber/
│   └── wireplumber.conf.d/
│       └── alsa-soft-mixer.conf
│
└── systemd/user/
    └── mic-gain.service
```

`alsa-soft-mixer.conf` keeps PipeWire from writing hardware volume registers, so
the GUI volume slider becomes software gain. That is desirable here: hardware
gain stays pinned by `set-mic-gain` and the slider cannot re-saturate the ADC.

---

## Troubleshooting

### Sounds loud but like hiss/rumble, and RNNoise makes it worse

Hardware gain is maxed (`Internal Mic Boost` 3/3, `Capture Volume` 63/63,
`Digital Capture Volume` 120/120). Record the raw source and check the level:

```bash
pw-record --target alsa_input.pci-0000_00_1f.3.analog-stereo /tmp/raw.wav
ffmpeg -i /tmp/raw.wav -af astats -f null - 2>&1 | grep -E 'RMS level|Peak level'
```

Idle RMS near `0 dBFS` means the ADC is saturated with preamp noise. Run
`set-mic-gain` (or `systemctl --user restart mic-gain.service`) and re-measure;
it should land around `-44 dBFS`.

Lowering the PipeWire volume slider does **not** help in that state: with
`api.alsa.soft-mixer = true` the slider is software gain applied after the ADC.

---

### RNNoise source doesn't appear

Restart PipeWire:

```bash
systemctl --user restart pipewire
```

Then:

```bash
wpctl status
```

Check PipeWire logs:

```bash
journalctl --user -u pipewire -b
```

---

### Filter captures speaker audio

Check:

```bash
pw-link -l
```

If the input comes from:

```text
alsa_output...:monitor_*
```

remove:

```ini
stream.capture.sink = true
```

and make sure the capture configuration contains:

```ini
node.target = "alsa_input.pci-0000_00_1f.3.analog-stereo"
```

---

### Quiet speech is being removed

Lower:

```ini
"VAD Threshold (%)" = 30.0
```

Possible values to test:

```text
30 -> 25 -> 20
```

Lower values preserve quieter speech but may allow more background noise through.

---

### Check the filter properties

Find the node:

```bash
wpctl status
```

Then:

```bash
wpctl inspect <NODE_ID>
```

The RNNoise capture node should have properties similar to:

```text
audio.channels = "1"
audio.position = "[ MONO ]"
media.class = "Stream/Input/Audio"
node.name = "capture.rnnoise"
node.target = "alsa_input.pci-0000_00_1f.3.analog-stereo"
```

The output source should have:

```text
audio.channels = "1"
audio.position = "[ MONO ]"
media.class = "Audio/Source"
node.name = "rnnoise_microphone"
```

---

## Result

The final setup provides:

- Hardware capture gain pinned to a sane level (`set-mic-gain`)
- Native PipeWire DSP
- 85 Hz high-pass before the denoiser (kills rumble and the power-up DC thump)
- RNNoise voice noise suppression (lightweight) and DeepFilterNet (better quality)
- Mono processing
- 30% VAD threshold
- Automatic startup with PipeWire
- `rnnoise_microphone` / `deepfilter_microphone` exposed as normal PipeWire sources
- No EasyEffects
- No manual activation required

### Key configuration

```ini
label = bq_highpass
"Freq" = 85

label = noise_suppressor_mono
"VAD Threshold (%)" = 30.0

node.target = "alsa_input.pci-0000_00_1f.3.analog-stereo"

audio.channels = 1
audio.position = [ MONO ]
```
