# Vitals

A menu bar system monitor for macOS 26 on Apple silicon. Three slim bars in the menu bar show
CPU load, memory pressure and GPU use at a glance; clicking them opens a glass panel with live
graphs for CPU (per performance level and per core), memory composition and swap, GPU, network,
disk, power and the top processes.

Built with Swift 6.4 and the Xcode Command Line Tools only — no Xcode required.

## Build

```sh
make test         # run the Swift Testing suite
make app          # build/Vitals.app, signed with the "RunCat Local" certificate
make install      # copy to /Applications and launch
make screenshots  # render the indicator, panel and settings to build/screenshots/*.png
```

The Makefile pins the macOS 26.5 SDK because the 27.0 SDK bundled with the CLT needs a SwiftUI
macro plugin the CLT doesn't ship, and passes the Swift Testing macro plugin explicitly.

To use a different signing identity, run `make app SIGN_ID="Your Identity"`.

## Layout

- `Sources/VitalsKit/Stats` — readers for CPU (`host_processor_info`), memory (`host_statistics64`),
  GPU and disk (IOKit), network (`getifaddrs`), battery (`AppleSmartBattery`) and processes
  (`proc_pid_rusage`). No helper tools, no elevated privileges.
- `Sources/VitalsKit/Model` — persisted `Settings`, time-bounded `History`, and the `Monitor` that
  samples on a background timer and publishes on the main actor.
- `Sources/VitalsKit/UI` — the status item, the panel window, and the SwiftUI dashboard/settings.
- `Sources/Vitals` — the launcher.
- `Tests/VitalsKitTests` — unit tests for every reader and the model layer.

## Settings

Open at login, which metrics appear in the menu bar and in what order, an optional fixed-width
CPU percentage, refresh interval (1/2/5 s), graph window (1/5 min), the amber/red thresholds, and
which panel sections are shown. All persisted in `UserDefaults`.

## Development hooks

- `Vitals -ShowPanel YES` opens the panel on launch.
- `Vitals -Screenshot <dir>` renders the UI to PNGs (no Screen Recording permission needed) and quits.
- `Vitals -LoginItemStatus YES` prints the `SMAppService` registration state and quits.
