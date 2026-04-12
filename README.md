# QuartzFocus

A macOS utility for switching focus (active window) with hotkeys.

Features:

- Directional focus jump on to different active windows via hotkeys (vim-styled
    keymap by default)
- Active window border highlight
- Focus dim

**Note:** Vibe coded, use at your own risk.

## Install

```bash
make install
```

## Build

```bash
$ make help
QuartzFocus — make targets

  make app      Build, assemble, and ad-hoc sign the .app bundle (default)
  make icon     Regenerate App/AppIcon.icns
  make install  Build app and open a DMG installer (drag to Applications)
  make open     make app, then open the bundle

  make build    swift build (debug)
  make release  swift build -c release
  make test     swift test
  make fmt      Format Swift sources in place (swift format)
  make run      swift run QuartzFocus (dev mode, no bundle)

  make wipe-tcc Quit app and reset Accessibility grant for com.lumither.QuartzFocus
  make clean    Remove .build
```

## Known Issue(s)

- Wiping TCC may be required during upgrades.
