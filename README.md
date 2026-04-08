# Spectrum

![Spectrum hero graphic](icon.png)

Spectrum is a native macOS Wi-Fi analyzer built for a big, visual live view of nearby wireless networks.

Instead of showing Wi-Fi data as a dense utility table, Spectrum focuses on a full-window spectrum-style display that helps you keep a clear mental picture of the radio environment. Weak or intermittent signals do not instantly vanish. They fade gradually so you can still see where they were and how stable they are.

## Highlights

- Live visualization of nearby Wi-Fi networks across `2.4 GHz`, `5 GHz`, and `6 GHz`
- Persistent fading signal traces instead of instant disappear/reappear behavior
- Strong visual emphasis for networks you mark as your own
- Friendly naming for radios based on BSSID / MAC address
- Simple inspector for browsing and labeling detected networks

## Requirements

- macOS `26` or newer
- Xcode `26.4` or newer
- Location Services enabled if you want macOS to reveal Wi-Fi names and BSSIDs

## Build

### Quick Build

Run the root build script:

```bash
./build.sh
```

This creates:

- `build/Artifacts/Spectrum.app`
- `build/Artifacts/Spectrum.dmg`

### Download

Releases are also provided on this repo for download.