# Board weirdisms

Only the things that are strange about each board. General method is in
[flashing.md](flashing.md) and [recovery.md](recovery.md).

## Summary

| Board | Chip | What bites |
|---|---|---|
| Metro RP2040 | RP2040 | Comes back on a full VBUS cycle, not `-a on`. `rp2040.cfg` will not attach |
| Metro RP2350 | RP2350 | No `rp2350.cfg` in stock OpenOCD. BOOTSEL is the last resort |
| Metro M0 Express | SAMD21 | SWD pins are LED pins. NeoPixel is blocked while a probe is attached |
| Metro M4 AirLift Lite | SAMD51 | Connect at 500 kHz. SWD reset works, VBUS cycle does not |
| Feather nRF52840 | nRF52840 | Bootloader shows no drive. Flash over SWD in two pieces |
| Feather STM32F405 | STM32F405 | No UF2 bootloader. 1000 kHz, `reset halt`, write at `0x08000000` |
| Metro ESP32-S2 | ESP32-S2 | No JTAG. Wedges and needs a long power-off |
| Metro ESP32-S3 | ESP32-S3 | JTAG only before CircuitPython takes the USB PHY |

## Bring-up cheat sheet

| Board | Bootloader entry | Bootloader install | Image push | How you know it landed |
|---|---|---|---|---|
| Metro RP2040 | 1200-baud touch | none | `cp` `.uf2` to the boot drive | CIRCUITPY at its USB path |
| Metro RP2350 | 1200-baud touch | none | `cp` `.uf2` to `RP2350` | same |
| Metro ESP32-S2 | touch, lands in `303a:0002` | `esptool`, tinyuf2 at S2 offsets | `cp` `.uf2` to `METROS2BOOT` | same |
| Metro ESP32-S3 | touch, lands in `0009` or `1001` | `esptool`, tinyuf2 at S3 offsets | `cp` `.uf2` to `METROS3BOOT` | same |
| Metro M4 AirLift | none | none | `openocd program ... 0x4000` | enumerates as `239a:8038` |
| Metro M0 Express | none | none | `openocd`, `0x2000` | enumerates as `239a:8014` |
| Feather nRF52840 | none | none | `openocd`, `0x26000` + `0x27000` | enumerates as `239a:802a` |
| Feather STM32F405 | none | none | `openocd`, `0x08000000` | enumerates as `239a:805a` |

## Metro M0 Express (SAMD21)

**The debug pins are LED pins.** SWDIO is `PA31`, shared with the RX LED. SWCLK
is `PA30`, shared with the NeoPixel. CircuitPython claims `PA31` as an output
for its whole run. The source says so itself: "Comment this out if you have
trouble connecting over SWD. It's one of the SWD pins."

What follows from that:

- A cold SWD attach fails on a healthy board and works on a broken one. If USB
  never came up, CircuitPython never claimed the pin.
- Adapter speed is not the fix. 50 to 1000 kHz all fail on a running board.
- `reset halt` is the fix. It halts the core before CircuitPython claims the
  pin. After that 2000 kHz is clean.

**NeoPixel and SWD conflict.** `board.NEOPIXEL` is `PA30`, which is SWCLK. With
a probe attached, any use of the pixel fails:

```
ValueError: NEOPIXEL in use
```

The cause is in `ports/atmel-samd/common-hal/microcontroller/Pin.c`.
`pin_number_is_free()` returns false for `PA30` and `PA31` whenever the SAMD21
debugger-present bit `DSU->STATUSB.DBGPRES` is set.

- The bit is latched by the probe being physically connected. Stopping OpenOCD
  does not clear it. The board booted with both pins blocked after plain power
  cycles with OpenOCD never run.
- No software path gets around it. Every pin binding goes through the same
  check, including `bitbangio`.
- Pressing reset with the cable on sets the bit again.
- A Metro M0 with no probe has a working pixel. This is a property of the rig,
  not the board.
- Not yet done: the positive control. Unplug the SWD cable, power cycle, and
  confirm the pixel lights.

The idle sketch handles this by catching the error and using only the red LED
on this board.

Other M0 traps:

- `microcontroller.reset()` took the board off USB twice after a host write to
  CIRCUITPY. Six VBUS cycles and an SWD reset did not bring it back. The RAM
  poke in [recovery.md](recovery.md) did.
- No `binascii`, no `zlib`, no `ulab` in the SAMD21 build. A check that works on
  seven boards raises `NameError` here. Use `len()` and `sum()`.
- App base is `0x2000`.

## Metro M4 AirLift Lite (SAMD51)

- Connect at 500 kHz. At OpenOCD's default 2000 it reports
  `Error connecting DP: cannot read IDR`, which looks exactly like an unplugged
  cable. Raise the speed after `init`.
- `cannot read IDR` at 500 kHz as well means something is holding SWDIO. Reset
  the board and attach again before blaming the cable.
- A VBUS cycle does not reset it. The port reads powered with no connect while
  SWD still sees a running core. `init; reset run; exit` brings it back in 1 to
  2 s.
- App base is `0x4000`. Below that is the UF2 bootloader.
- Flash over SWD, not the UF2 drive. The `METROM4BOOT` volume went stale (size
  0) three times. Four SWD flashes in a row had no failures.
- The double-tap RAM address is `0x2002fffc`, not the SAMD21's `0x20007ffc`.
- Its mass storage interface is `:1.4`, not `:1.2`. Resolve the block device
  with a wildcard.
- The ESP32 co-processor needed a nina-fw upgrade. See
  [wippersnapper.md](wippersnapper.md).

## Feather nRF52840 Express

- The 1200-baud touch works and the PID flips to `239a:002a`. No boot drive ever
  appears. The bootloader enumerates serial only on this unit.
- So flash over SWD. The image has a gap: two runs at `0x26000` (256 bytes) and
  `0x27000`. Use `uf2extract.py`.
- Never `nrf5 mass_erase`. The bootloader is at `0xF4000`.
- Asking for 4000 kHz works and 8000 is no faster. See the note on speeds in
  [flashing.md](flashing.md).
- The NeoPixel has a power pin. It stays dark until `NEOPIXEL_POWER` is driven.
- Slowest board to flash, about 30 s.

## Feather STM32F405 Express

- No UF2 bootloader, and CircuitPython publishes only a `.bin`. The touch gives
  no drive.
- ST's ROM bootloader is always there at `0x1FFF0000` and speaks DFU. See
  [flashing.md](flashing.md).
- `adapter speed 1000`. At 4000 the erase fails.
- `reset halt`, not `halt`. A plain attach to a running board fails with
  `stalled AP operation` because the app has put the core to sleep.
- Write at `0x08000000`. Read `0x08000000` first: a stack pointer like
  `0x2002xxxx` and a reset vector mean the app is based there.
- Wait for it to settle after a port cycle before flashing.
- CircuitPython drives PB3 (JTDO) low, so JTAG reads all zeroes. SWD is fine.

## Metro RP2040

- The probe plugs straight into the 3-pin connector.
- After a bring-up the port can sit powered with no connect while the board is
  alive (SWD reads `0x0bc12477`). `uhubctl -a on` does nothing. A full off, wait
  5 s, on brings it back.
- `target/rp2040.cfg` does not attach with stock OpenOCD 0.12.0.
- No WipperSnapper build ships for it.

## Metro RP2350

- The probe plugs straight in. Its probe serial starts `E661`, the others start
  `E664`. Easy to miss when grepping.
- Stock OpenOCD has no `rp2350.cfg`. See [debug.md](debug.md).
- It once sat powered but off the bus through three VBUS cycles and a probe
  reset. Holding BOOT and tapping RESET fixed it. That needs a person.
- A 1200-baud touch gives a real `RP2350` drive.

## Metro ESP32-S2

- No working JTAG on this unit. See [debug.md](debug.md).
- The touch lands in ROM download mode, `303a:0002`.
- When wedged (`error -71`, `unable to enumerate`) it needs a long power-off:
  off with `-r 20 -w 200`, sleep 6, on. A wedged board took up to four rounds.
- Release builds print nothing on the debug UART after the bootloader. A
  `make DEBUG=1` build should put output there. Not tried.
- 4 MB flash, so its CIRCUITPY drive is under 1 MB. Large files do not fit.

## Metro ESP32-S3

- JTAG and CircuitPython cannot run at the same time. See [debug.md](debug.md).
- Its USB ID changes with what is running: `239a:0145` CircuitPython,
  `303a:1001` USB-JTAG, `303a:0009` DFU. A PID change is not a board change.
- In USB-JTAG mode it resists power-off. Use `-r 80 -w 300`.
- After a core reset the strapping pins are not read again, so it can stay in
  download mode. Power cycle it.

## Both ESP32 boards

Scripts pasted over the raw REPL sometimes arrive corrupted. The sign is a
`SyntaxError` at a different line each time for the same input. It happens
only on the two ESP32 boards and is not explained. Rerun, and do not count a
single failed pass as a result.
