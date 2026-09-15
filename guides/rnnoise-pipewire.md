# RNNoise Microphone with PipeWire

Lightweight microphone noise suppression using **PipeWire's native filter-chain** and the **RNNoise LADSPA plugin**.

This setup does **not** require EasyEffects and automatically creates an `RNNoise Microphone` source when PipeWire starts.

## Requirements

- Arch Linux
- PipeWire
- WirePlumber
- `noise-suppression-for-voice`

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
~/.config/pipewire/pipewire.conf.d/rnnoise-microphone.conf
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
            type = ladspa
            name = rnnoise
            plugin = ladspa/librnnoise_ladspa
            label = noise_suppressor_mono

            control = {
              "VAD Threshold (%)" = 30.0
            }
          }
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

## Configuration Files

The relevant configuration is:

```text
~/.config/
├── pipewire/
│   └── pipewire.conf.d/
│       └── rnnoise-microphone.conf
│
└── wireplumber/
    └── wireplumber.conf.d/
        └── alsa-soft-mixer.conf
```

The existing `alsa-soft-mixer.conf` is independent of RNNoise and does not need to be modified for this setup.

---

## Troubleshooting

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

- Native PipeWire DSP
- RNNoise voice noise suppression
- Mono processing
- 30% VAD threshold
- Automatic startup with PipeWire
- `rnnoise_microphone` exposed as a normal PipeWire source
- RNNoise configured as the default microphone
- No EasyEffects
- No manual activation required

### Key configuration

```ini
plugin = ladspa/librnnoise_ladspa
label = noise_suppressor_mono

control = {
  "VAD Threshold (%)" = 30.0
}

node.target = "alsa_input.pci-0000_00_1f.3.analog-stereo"

audio.channels = 1
audio.position = [ MONO ]
```
