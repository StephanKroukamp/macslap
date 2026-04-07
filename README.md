# MacSlap

Your MacBook reacts to physical interactions. Slap it, move the lid, plug in the charger — it makes sounds.

Built for Apple Silicon Macs (M1 Pro or later) using the built-in accelerometer and lid angle sensor.

![macOS](https://img.shields.io/badge/macOS-14.0+-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%20Pro+-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

| Feature | Sensor | Description |
|---------|--------|-------------|
| **Slap Detection** | Accelerometer (Bosch BMI286 IMU) | Detects physical impacts on the MacBook body. Volume scales with force. |
| **Lid Angle** | SPU Hinge Sensor | Plays sound continuously while moving the lid. Volume tracks movement speed. |
| **Charger Detection** | IOKit Power Sources | Plays different sounds for plug-in and unplug events. |

- Choose from system sounds or use your own audio files
- Separate sound selection for each event type
- Configurable sensitivity, cooldown, and thresholds
- Menu bar icon with quick access and slap counter
- Runs in the background when the window is closed

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon: **M1 Pro, M1 Max, M2, M2 Pro, M2 Max, M3, M3 Pro, M3 Max, M4** or later
- Standard M1 and A-series chips are **not supported** (no exposed accelerometer)

## Installation

### Download (Recommended)

1. Go to [**Releases**](https://github.com/StephanKroukamp/macslap/releases/latest)
2. Download `MacSlap-x.x.x.dmg`
3. Open the DMG and drag **MacSlap** to **Applications**
4. On first launch, macOS will warn about an unidentified developer:
   - Click **Done**
   - Go to **System Settings > Privacy & Security**
   - Click **Open Anyway** next to the MacSlap warning
5. Grant any requested permissions (the app uses the accelerometer sensor)

### Build from Source

```bash
git clone https://github.com/StephanKroukamp/macslap.git
cd macslap
chmod +x build.sh
./build.sh
open build/MacSlap.app
```

Requires Xcode Command Line Tools:
```bash
xcode-select --install
```

## Usage

MacSlap runs as both a **menu bar app** and a **windowed app**.

### Slap Detection
- Open the **Slap** tab to configure sensitivity
- **Light tap** (slider left) = triggers on gentle taps
- **Hard slap** (slider right) = only triggers on firm impacts
- Adjust **cooldown** to control how quickly it can re-trigger

### Lid Angle
- Open the **Lid Angle** tab
- Sound plays **continuously while the lid is moving**
- Volume is proportional to movement speed — slow = quiet, fast = loud
- Sound fades out when you stop moving the lid

### Charger
- Open the **Charger** tab
- Different sounds for **plug-in** and **unplug** events
- Default: rising tone for plug, falling tone for unplug

### Custom Sounds
Each feature lets you:
- Pick from **system sounds** (Basso, Blow, Bottle, etc.)
- **Choose File** to use any `.aiff`, `.wav`, `.mp3`, `.m4a`, or `.caf` file
- Click **Use Default** to reset to the built-in sound
- Click **Preview** to hear the current selection

## How It Works

### Accelerometer Access
MacSlap reads raw HID reports from the Apple SPU (Signal Processing Unit) accelerometer at ~800Hz. The sensor data arrives as 22-byte reports with X/Y/Z acceleration as Int32 little-endian values at byte offsets 6, 10, and 14. Values are divided by 65536 to convert to g-force.

The accelerometer is matched via IOKit HID:
- **UsagePage**: `0xFF00` (vendor-specific)
- **Usage**: `3` (accelerometer)
- **Transport**: `SPU`

### Lid Angle Sensor
The lid angle is read from a separate SPU sensor device:
- **UsagePage**: `0x20` (Sensor)
- **Usage**: `138`
- **Element Usage**: `0x47F` (hinge angle, range 0-360 degrees)

Polled at 20Hz with volume mapped to angular velocity.

### Charger Detection
Uses `IOPSNotificationCreateRunLoopSource` from IOKit Power Sources to receive instant callbacks on power state changes.

## CI/CD

Every push to `main` automatically:
1. Builds the app on a macOS 14 runner
2. Creates a versioned `.dmg` file
3. Auto-increments the patch version
4. Creates a GitHub Release with notes from commit messages

## Credits

Accelerometer access approach inspired by [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer) and [taigrr/spank](https://github.com/taigrr/spank).

## License

MIT
