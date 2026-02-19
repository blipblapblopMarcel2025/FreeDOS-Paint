# FreeDOS-Paint

A 16-bit `.COM` paint/graphics prototype for FreeDOS, written in NASM assembly.

## What's new in this revision

- Top menu bar title: **FreeDOS Paint 1.0a**
- Menu labels on the bar: **File, Edit, Options, Help**
- Clickable **File** dropdown menu with simple slide animation (~0.25s target)
  - New (`Ctrl+N` label)
  - Load (`Ctrl+L` label)
  - Beep (`Ctrl+B` label)
  - Quit (`Alt+X` label)
- Basic text tool support (`T` to toggle text mode, then type printable characters)

## Core features

- 16-bit real mode `.COM` target (`ORG 100h`)
- Keyboard + mouse driver initialization via BIOS/DOS interrupts
  - PS/2 works through standard BIOS/mouse driver
  - USB input can work when legacy USB emulation is provided by BIOS
- PC speaker beep (`B` key)
- Resolution/mode cycling (`R` key):
  - VGA `13h` (320x200x256)
  - CGA `06h` (640x200 mono)
  - VESA `101h` (640x480x256)
  - VESA `103h` (800x600x256)
  - BGA-compatible environments are typically exposed through VBE-compatible BIOS calls
- Color and monochrome drawing toggle
  - `C` cycles paint color
  - `M` toggles monochrome mode
- File type gate: only `.BMP` or `.GIF` filenames are accepted
- BMP loader:
  - Supports uncompressed 8-bit BMP frames
  - Draws with clipping to the active resolution
- GIF loader status:
  - GIF files are detected and accepted as valid type
  - Full LZW decode is currently a stub (message shown)

## Controls

- Arrow keys: move cursor
- Space: draw pixel
- `T`: toggle text tool mode
- `C`: next color
- `M`: monochrome toggle
- `R`: next video mode/resolution
- `L`: load image from command-line filename
- `B`: PC speaker beep
- `Q`: quit
- Mouse: click **File** in top bar to open/close dropdown menu

## Build

```bash
nasm -f bin paint16.asm -o paint16.com
```

or

```bash
make
```

## Run in FreeDOS

```dos
PAINT16.COM IMAGE.BMP
```

or

```dos
PAINT16.COM IMAGE.GIF
```

If no filename is given, it defaults to `IMAGE.BMP`.

## Notes

- VESA/BGA mode availability depends on your BIOS/emulator.
- In pure DOS, hardware USB support generally depends on BIOS legacy emulation or extra DOS USB drivers.
- Dropdown animation timing is an approximation and depends on CPU/emulator speed.
