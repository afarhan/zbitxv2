# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**sbitx** (also called zbitx) is a Software Defined Radio (SDR) transceiver application for amateur radio, designed to run on Raspberry Pi. It supports multi-mode operation (USB, LSB, CW, FT8/FT4, AM, NBFM, Fldigi digital modes) with a GTK3 GUI, web-based remote control, and hardware interfaces for the sBitx radio board.

## Build

```bash
./build sbitx        # Build the main application
./build              # Defaults to sbitx target
```

The build script creates `audio/`, `data/`, and `web/` directories, initializes the SQLite logbook if absent, then compiles all `.c` files and links against wiringPi, ALSA, FFTW3, FFTW3f, pthreads, ncurses, sqlite3, and GTK3.

To rebuild the FT8 codec library (`ft8_lib/libft8.a`):

```bash
cd ft8_lib
make all     # Build encode/decode tools and test binary
make install # Build and install libft8.a
```

Run FT8 codec unit tests:

```bash
cd ft8_lib
make run_tests
```

## Architecture

### Signal processing pipeline

The core DSP uses **frequency-domain (overlap-save) convolution** via FFTW3, not traditional time-domain FIR filters. Audio samples come in from ALSA at 48 kHz, an FFT converts them to the frequency domain, bin rotation shifts the desired carrier to baseband, a frequency-domain filter window is applied, and an IFFT reconstructs the time-domain audio. This approach achieves steep filter skirts without ringing.

Key files:
- `sbitx_sound.c` — ALSA audio thread; calls `sound_process()` each block
- `fft_filter.c` — Frequency-domain filtering, overlap-save convolution
- `vfo.c` — Phase-accumulator VFO (tone generation)
- `sdr.h` — Core DSP structs (receivers, FFT state, filter parameters)

### Hardware abstraction

- `si5351v2.c` / `si570.c` — Frequency synthesizer drivers (I2C)
- `i2cbb.c` — Bit-banged I2C master over GPIO (used for synthesizers, OLED)
- `oled.c` — SSD1306 OLED display driver
- `sbitx_utils.c` — GPIO relay and band-switch control (wiringPi)

### Demodulation / modulation

- `modems.c` — Mode dispatch and FT8 QSO state machine
- `modem_ft8.c` — FT8/FT4 interface to `ft8_lib/libft8.a`
- `modem_cw.c` — CW (Morse) encoder/decoder
- `ft8_lib/` — Standalone FT8/FT4 codec (Kiss FFT, LDPC, pack/unpack)

### User interface

- `sbitx_gtk.c` — GTK3 window, drawing, encoder/button input
- `settings_ui.c` — Settings panel
- `hist_disp.c` — Spectrum histogram display
- `sdr_ui.h` — UI function declarations, version constant, font/color definitions
- `main_ui.ini` — Declarative UI field definitions (loaded at runtime)

### Connectivity

- `webserver.c` + `mongoose.c` — Embedded HTTP/WebSocket server on port 8080 (port 80 via iptables redirect)
- `remote.c` — Telnet command server on port 8081
- `hamlib.c` — Hamlib CAT protocol compatibility
- `telnet.c` — DX Cluster/RBN telnet client

### Configuration & data

- `data/hw_settings.ini` — Hardware pin assignments, audio card index, frequency calibration
- `data/user_settings.ini` — Callsign, grid locator, power level
- `main_ui.ini` — UI layout / field definitions
- `data/sbitx.db` — SQLite3 QSO logbook (schema in `data/create_db.sql`)
- `data/sbitx_wisdom.wis` — FFTW3 wisdom cache (speeds up FFT plan initialization)
- `ini.c` — INI file parser used for all `.ini` config files

### Audio loopback (WSJT-X integration)

The `snd-aloop` kernel module creates three virtual ALSA cards:
- `hw:1,0`/`hw:1,1` — sbitx RX output → WSJT-X capture
- `hw:2,0`/`hw:2,1` — WSJT-X TX output → sbitx TX input

Enable at boot via `/etc/rc.local`:
```bash
sudo modprobe snd-aloop enable=1,1,1 index=1,2,3
```

## Runtime

```bash
./sbitx   # Launch the radio (requires hardware, ALSA loopback, and GPIO access)
```

The process starts the audio thread, GTK event loop, web server (port 8080), and telnet server (port 8081) concurrently.

## Dependencies

Install order matters — see `install.txt` for full steps:

1. wiringPi (from drogon.net deb)
2. FFTW3 double + single precision (build from source at fftw.org)
3. `sudo apt-get install ncurses-dev libasound2-dev libgtk-3-dev libgtk+-3-dev libsqlite3-dev ntp ntpstat`
4. `snd-aloop` kernel module (ALSA loopback)
5. AudioInjector WM8731 dtoverlay in `/boot/config.txt`
6. iptables redirect port 80 → 8080
