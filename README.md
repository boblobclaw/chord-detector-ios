# ChordDetector

A real-time chord detection iOS app using audio analysis. Supports both **guitar** and **piano**.

## Features

- **Multi-instrument support** — Guitar and Piano modes
- **Real-time chord detection** from microphone input
- **Guitar tunings** — Standard, Drop D, Half Step Down, Open G, Open D, DADGAD
- **Piano ranges** — Full, Bass, Middle, Treble
- **Visual feedback** with confidence meter and detected notes
- **Fast FFT-based** pitch detection using the Accelerate framework
- **SwiftUI interface** with clean, modern design

## How It Works

1. **Audio Input**: Uses AVAudioEngine to capture microphone input
2. **Pitch Detection**: FFT-based spectral analysis with peak detection
3. **Chord Recognition**: Matches detected notes against chord interval patterns
4. **Display**: Shows the detected chord, confidence level, and individual notes

## Instrument Support

### Guitar
- Frequency range: 50Hz - 500Hz (E2 to B4)
- 6 tunings available
- Optimized for acoustic/electric guitar chords

### Piano
- Frequency range: 27.5Hz - 4186Hz (A0 to C8)
- 4 selectable ranges:
  - **Full**: A0 to C8 (88 keys)
  - **Bass**: A0 to E3 (left hand)
  - **Middle**: F3 to B5 (center)
  - **Treble**: C6 to C8 (right hand)

## Technical Details

- **Pitch Detection**: FFT with Hann windowing and quadratic interpolation for precise frequency estimation
- **Chord Matching**: Template-based recognition scoring matches against standard chord qualities
- **Performance**: Real-time processing on dedicated dispatch queue

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Microphone access (granted at runtime)

## Project Structure

```
ChordDetector/
├── ChordDetectorApp.swift    # App entry point
├── ContentView.swift         # Main UI
├── AudioEngine.swift         # Audio capture and management
├── PitchDetector.swift       # FFT-based pitch detection
├── ChordRecognizer.swift     # Chord recognition logic
└── Info.plist               # App configuration
```

## Build Instructions

1. Open the project in Xcode
2. Select your target device or simulator
3. Build and run (⌘+R)

## Usage

1. Launch the app and grant microphone permission
2. Select your instrument (Guitar or Piano)
3. Choose tuning (guitar) or range (piano)
4. Tap "Start Listening"
5. Play chords on your instrument
6. The detected chord will appear with confidence level

## Future Enhancements

- [x] Support for piano
- [ ] Chord progression logging
- [ ] Export detected chords
- [ ] Custom tuning support
- [ ] Chord diagram visualization
- [ ] Ukulele and other instruments

## License

MIT License
