# Board weirdisms

Only the things that are strange about each board: how to reach it with a
debugger, how to get it into its bootloader, what pushes an image, how to know
the push landed, and what it does that the boards next to it do not. Most of
these took hours to find. General method is in [flashing.md](flashing.md) and
[recovery.md](recovery.md).

## Summary

| Board | Chip | What bites |
|---|---|---|
| Metro RP2040 | RP2040 | Comes back on a full VBUS cycle, not `-a on`. `rp2040.cfg` will not attach |
| Metro RP2350 | RP2350 | No `rp2350.cfg` in stock OpenOCD. BOOTSEL is the last resort |
| Metro M0 Express | SAMD21 | SWD pins are LED pins. NeoPixel is blocked while a probe is attached |
| Metro M4 AirLift Lite | SAMD51 | Connect at 500 kHz. SWD reset works, VBUS cycle does not. Its UF2 drive goes stale |
| Feather nRF52840 | nRF52840 | Bootloader shows no drive. Flash over SWD in two pieces |
| Feather STM32F405 | STM32F405 | No UF2 bootloader. `reset halt`, write at `0x08000000`, never at `UF2_OFFSET` |
| Metro ESP32-S2 | ESP32-S2 | JTAG TAP is dead on this unit. Wedges and needs a long power-off |
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

CIRCUITPY drive sizes when mounted, useful for telling boards apart:

| Board | Bytes |
|---|---|
| RP2040, RP2350 | 15,695,872 |
| ESP32-S3 | 14,319,616 |
| ESP32-S2 | 963,072 |
| M0, nRF52840, STM32F405 | 2,072,576 (external SPI flash) |

## Metro M0 Express (SAMD21)

**The debug pins are LED pins.** From the schematic: SWDIO is `PA31`, shared
with the RX LED through a 1K resistor. SWCLK is `PA30`, shared with the
NeoPixel data line through a 1K resistor. CircuitPython's `init_rxtx_leds()` in
`supervisor/shared/status_leds.c` claims `PA31` as a push-pull output and marks
it never-reset, so the chip drives SWDIO for CircuitPython's whole run. The
source carries its own warning: "Comment this out if you have trouble
connecting over SWD. It's one of the SWD pins." The UF2 bootloader claims both
pins as well (`LED_RX_PIN PIN_PA31`, `BOARD_NEOPIXEL_PIN PIN_PA30`).

**It is reachable over SWD exactly when it is broken.** If USB never comes up,
CircuitPython never claims `PA31`, so a cold OpenOCD connect succeeds. Once you
`reset run` and it enumerates, SWD is blocked again. A hung M0 is easy to
attach to. A working one is not. This was confirmed by mechanism: reset the
board so CircuitPython runs again, and OpenOCD goes straight back to
`cannot read IDR`.

- **Adapter speed is not the fix.** 50, 100, 200, 400 and 1000 kHz all give
  `cannot read IDR` on a running board. A sweep that once appeared to work only
  worked because a J-Link session had already halted the core.
- **`reset halt` is the fix.** Halting on the reset edge gets the core before
  `init_rxtx_leds()` runs. With that, 2000 kHz is clean: 400 kHz took 28.1 s,
  1000 kHz 17.3 s, 2000 kHz 12.7 s, with no errors.
- **A J-Link wins the reset race where OpenOCD cannot.** Halt the core with
  JLinkExe first. With the core halted, CircuitPython is not running, the pins
  are free, and OpenOCD attaches at any speed.

  ```sh
  printf "si SWD\nspeed 400\ndevice ATSAMD21G18\nconnect\n" > /tmp/j.jlink
  JLinkExe -SelectEmuBySN <serial> -NoGui 1 -CommanderScript /tmp/j.jlink
  ```

- **The durable fix is a build with `MICROPY_HW_LED_RX` commented out**, as the
  source suggests. Not done here.
- **Put `adapter speed` after `-f target/at91samdXX.cfg`.** The config sets 400
  itself and silently overrides a flag placed before it.

### NeoPixel and SWD conflict

`board.NEOPIXEL` is `PA30`, which is SWCLK. With a probe attached, any use of
the pixel fails:

```
ValueError: NEOPIXEL in use
```

`pin_number_is_free()` in
`ports/atmel-samd/common-hal/microcontroller/Pin.c` returns false for `PA30`
and `PA31` whenever `DSU->STATUSB.bit.DBGPRES == 1`, the SAMD21
debugger-present bit.

- **It is not a permanent property of the board.** A Metro M0 with no probe has
  a working pixel, which is why every Adafruit example assumes one. Commit
  `ff7e729` added the `DBGPRES` check in 2019 to make these pins *more*
  available. Before that they were reserved unconditionally (issue #1633). Its
  diff carries the comment
  `// Special case for Metro M0 where the NeoPixel is also SWCLK`.
- **The bit is latched by the probe being plugged in, not by OpenOCD traffic.**
  The board booted after plain VBUS cycles with OpenOCD never run, and still
  reported both pins in use. Stopping OpenOCD is not enough. The cable has to
  come off. `PA31` being blocked too is the proof, since it has no NeoPixel
  role. Per the SAM D21 datasheet section 13.6.3, a single SWCLK falling edge
  latches it, and cold-plug detection with a probe attached is reset extension.
- **Do not press reset with the cable on.** That is the normal way to *set* the
  bit you are trying to clear.
- **No software path gets around it.** Every pin-taking binding goes through
  `assert_pin_free()`. `bitbangio` looks like a gap but is checked one level
  down in `DigitalInOutProtocol.c`. `memorymap` is not built on atmel-samd, so
  Python cannot even read the bit. `microcontroller.pin.PA30 is board.NEOPIXEL`
  is `True`, so it is not a second path. `rgb_status_brightness = 0` does not
  help, and a claim in `boot.py` fails before user code runs. No claim ever
  succeeded, on any path.
- **On the farm** the M0 breathes its red D13 LED (`PA17`, not an SWD pin) and
  leaves the pixel dark. The idle sketch catches the error and carries on.
- **Not yet done:** the positive control. Unplug the SWD cable, power cycle, and
  confirm the pixel lights. It may also fix the M0's occasional enumeration
  flakiness, since an attached probe holds the chip in reset extension across a
  power cycle.

### An upstream bug nobody reported

`Pin.c` line 141 computes `4 * pin_index % 2`, which parses as
`(4 * pin_index) % 2` and is always 0. The intent was `4 * (pin_index % 2)`.
`PA30` works by luck. `PA31` reads `PA30`'s mux nibble. It has been there about
seven years. Only the Metro M0 and the SparkFun RedBoard Turbo put a NeoPixel
on an SWD pin, out of 117 atmel-samd boards.

### Other M0 traps

- **`microcontroller.reset()` is hazardous.** Twice it took the board fully off
  USB after a host write to CIRCUITPY. Six VBUS cycles and an SWD
  `init; reset run` did not bring it back. The RAM poke did (see below).
- **Remote double-tap.** When USB is dead (`error -71`, port stuck at
  `0101 power connect`), force the UF2 bootloader from RAM. No firmware is
  written:

  ```sh
  openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
    -c "transport select swd" -f target/at91samdXX.cfg -c "adapter speed 400" \
    -c "init" -c "halt" -c "mww 0x20007ffc 0xf01669ef" -c "reset run" -c "exit"
  ```

  It enumerates in about 1 s as `239a:0013` (UF2 Bootloader v4.0.0), which also
  proves the USB hardware is fine. A plain `reset run` brings CircuitPython back
  in about 3 s.
- **No `binascii`, no `zlib`, no `ulab`** in the SAMD21 build. A check that
  works on seven boards raises `NameError` here. Use `len()` and `sum()`.
- **A stale `lib/neopixel.mpy`** on this unit was a MicroPython build and raised
  `use CircuitPython mpy-cross`. It breaks any NeoPixel test regardless of the
  pin problem. Replace it.
- The UF2 route failed to enumerate twice in a row. SWD worked every time. Flash
  this board over SWD.
- App base is `0x2000`.

## Metro M4 AirLift Lite (SAMD51)

Replaced the Metro M4 Express as a permanent station, for WipperSnapper and
AirLift testing.

- **Connect at 500 kHz.** At OpenOCD's default 2000 it reports
  `Error connecting DP: cannot read IDR`, which looks exactly like an unplugged
  cable. It has already produced one wrong "no probe attached" verdict. Raise
  the speed after `init`: 26.6 s became 12.4 s.
- **`cannot read IDR` at 500 kHz as well** means something is holding SWDIO,
  usually a running app or a bootloader left sitting. Reset the board and
  attach again before blaming the cable.
- **A VBUS cycle does not reset it.** The port reads `0100 power` with no
  `connect` and the board never re-enumerates, while SWD still sees a running
  Cortex-M4. `init; reset run; exit` brings it back in 1 to 2 s. Three for three
  across separate sessions.
- **App base is `0x4000`.** `0x0` to `0x4000` is the UF2 bootloader. Never write
  there. `bossac` needs `-o 0x4000` explicitly.
- **Do not flash it through the UF2 drive.** Both the 1200-baud touch and the
  RAM poke reach `METROM4BOOT`, but the volume goes stale within seconds:
  `/sys/block/sd?/size` reads 0 and the copy never lands. Hit three times in a
  row. CI publishes only a `.uf2` for this board, so convert and program over
  SWD. Four SWD flashes in a row had no failures.

  ```sh
  python3 circuitpython/tools/uf2/utils/uf2conv.py fw.uf2 -o fw.bin
  # it must report: start address: 0x4000
  openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
    -c "transport select swd" -f target/atsame5x.cfg -c "adapter speed 500" \
    -c "program fw.bin 0x4000 verify reset exit"
  ```

- **The double-tap RAM address is `0x2002fffc`**, the end of the SAMD51J19A's
  192 KB RAM. Not the SAMD21's `0x20007ffc`.
- **Its mass storage interface is `:1.4`, not `:1.2`.** Resolve the block device
  with `$P:1.*`, not a fixed interface number.
- **Fastest station to flash**, because SWD skips bootloader entry and
  bootloader install. One command flashes, verifies and resets.

### The ESP32 co-processor

- **nina-fw version gate.** The co-processor shipped nina-fw 1.7.5. WipperSnapper
  `beta.131` requires 1.7.7 and otherwise refuses to associate and watchdog
  reboots every 25 s. It now runs nina-fw 3.3.0. Go to 3.3.0, not the 1.7.7
  minimum: `compareVersions()` is numeric, so any 3.x passes. The file is
  `NINA_ADAFRUIT-esp32-3.3.0.bin`. The `fruitjam_c6` build is for the ESP32-C6.
- **1.7.x reports the MAC byte-reversed.** `61:A9:0E:33:4F:C4` under 1.7.7,
  `C4:4F:33:0E:A9:61` under 3.3.0. The second matches esptool.
- **Fallback if ever needed:** WipperSnapper `1.0.0-beta.85` is the newest build
  that accepts nina-fw 1.6.0. It prints a bare `PING!` instead of
  `Sending MQTT PING: SUCCESS!`.
- **That failure passes every static check.** Correct board ID, firmware
  version, `secrets.json`, no ERROR in `wipper_boot_out.txt`, right USB ID, on a
  board in a reboot loop. Only the serial console shows it.
- **Upgrade nina-fw with the Arduino passthrough, never a CircuitPython
  bridge.** A CircuitPython `busio.UART` on `board.ESP_TX` and `board.ESP_RX`
  receives the ESP32 ROM banner perfectly but never transmits: 1610 bytes host
  to ESP, 0 back, while `uart.write()` returned 46 of 46 at timeouts of 0, 0.2
  and 1.0 s. The TX line is fine. The Arduino build drives `PA04` and
  CircuitPython evidently does not. That cost hours and produced a wrong
  "hardware fault" verdict. Recipe in [wippersnapper.md](wippersnapper.md).
- **Do not flash the AirLift WipperSnapper UF2 onto a plain Metro M4 Express.**
  Pins 36, 37 and 38 differ, so it drives A0, A1 and AREF as ESP32 control
  lines.

## Feather nRF52840 Express

- **The bootloader enumerates serial only, no mass storage.** The 1200-baud
  touch works and the PID switches to `239a:002a`, but no `FTHR840BOOT` volume
  ever appears. A power cycle returns it to CircuitPython and the touch fails
  the same way again.
- **So flash it over SWD**, extracting the `.uf2` first with
  [uf2extract.py](../scripts/uf2extract.py). The image has a gap. One build
  gave two runs, `0x026000` (256 bytes) and `0x027000` (644 KiB), with
  `0x026100..0x027000` left erased. Family ID `0xADA52840`. Check the runs on
  every build.
- **Never `nrf5 mass_erase`.** The UF2 bootloader lives at `0xF4000` and the app
  ends at `0xC8200`. A sector erase leaves the bootloader alone. A mass erase
  takes it.
- **Plain `halt` is enough.** No reset-then-attach needed.
- **About 22 KiB/s, 30 s for 644 KiB.** It sets the farm's flash floor. Asking
  for 8000 kHz was no faster than 4000, but see the note on adapter speeds in
  [flashing.md](flashing.md): `nrf52.cfg` sets 1000 and the flag was placed
  before it.
- **The NeoPixel has a power pin.** It stays dark until `NEOPIXEL_POWER` is
  driven high. It is the only board on the farm with one, and it looks like a
  dead pixel. The idle sketch handles it.

## Feather STM32F405 Express

- **No UF2 bootloader, and no `.uf2`.** CircuitPython publishes only a `.bin`
  for this board. A 1200-baud touch gives no drive at all.
- **There is a bootloader: ST's, in mask ROM at `0x1FFF0000`.** It speaks DFU as
  `0483:df11`, and `dfu-util` flashes it. Getting there needs SWD or a firmware
  change. Stock CircuitPython reaches it about 5 times in 12, because the ROM
  mismeasures the 12 MHz crystal and resets itself. Retrying makes it 12 of 12.
  See [findings.md](findings.md) and [flashing.md](flashing.md).
- **`reset halt`, not `halt`.** A plain attach to a running board gives
  `stalled AP operation, issuing ABORT` and `target examination failed`, because
  the app has put the core to sleep. `reset halt` asserts reset itself, which
  also took a flash from 34.2 s to 23.8 s and removed the need for a power cycle
  first.
- **Write at `0x08000000`.** This is the trap. `mpconfigboard.mk` declares
  `UF2_OFFSET = 0x8010000`, which describes a UF2 build variant, not this board.
  Writing the `.bin` at `0x08010000` erases sectors 4 to 9, where the running
  image's body lives, and leaves its vector table at `0x08000000` pointing into
  erased flash. It writes and verifies cleanly, and then the board
  double-faults and never enumerates. The signature:

  ```
  Error: [stm32f4x.cpu] clearing lockup after double fault
  msp (/32): 0xffffffe0
  ```

  Read `0x08000000` before choosing an offset. A plausible stack pointer
  (`0x2002xxxx` on this part) and a reset vector mean the app is based there and
  there is no bootloader to keep. Extracting the UF2 variant confirms it from
  the other direction: two runs at `0x08000000` (512 bytes) and `0x08004000`.
- **Verify by enumeration, not by `verify_image`.** The bad-offset write
  verified perfectly.
- **Erase failures at high adapter speed.** A run asking for 4000 kHz failed
  with `failed erasing sectors 4 to 9` while probe, DPIDR and halt all looked
  healthy. Nothing pointed at speed. `stm32f4x.cfg` sets its own speed on every
  reset, so the speed that actually ran is not certain. See
  [flashing.md](flashing.md). Do not raise it.
- **Let it settle after a port cycle.** Flashing 2 s after a power cycle failed
  three times and produced a wrong "unflashable" verdict. The normal recipe then
  worked unchanged.
- **CircuitPython drives PB3 (JTDO) low**, so JTAG reads all zeroes with a
  perfect probe. SWD still works, since it only needs two pins. That makes this
  board a good SWD positive control and a useless JTAG one.
- **A spare RAM word that survives a warm reset.** CCM RAM at `0x10000000` is
  declared in the linker script but nothing is placed there, and it is clocked
  from reset. Useful as a breadcrumb for bootloader experiments. Verified not to
  alias other memory.

## Metro RP2040

- **The probe plugs straight into the 3-pin connector.** Orange SWCLK, black
  GND in the middle, yellow SWDIO. It tolerates a cold attach.
- **It comes back on a VBUS cycle, not on a plain `-a on`.** After a bring-up
  the port sat at `0100 power` with no `connect` while the board was powered
  and running: SWD read `DPIDR 0x0bc12477`. So it was not a power fault, and
  `uhubctl -a on` is a no-op. A full `-a off -r 30 -w 400`, wait 5 s, `-a on`
  brought it straight back to `239a:813e`. `farm-up.sh` does this for any board
  still missing after the SWD stage.
- **This is the opposite of the SAMD boards**, where a VBUS cycle does nothing
  and SWD `reset run` is the fix. Try SWD first, then the cycle.
- **`target/rp2040.cfg` fails to attach** with
  `Failed to connect multidrop rp2040.dap0`, even at 1000 kHz, and even when a
  bare DPIDR sweep on the same probe succeeds a second earlier. Probably the
  multidrop support in OpenOCD 0.12.0. Use SWD on this board to answer "does it
  have power", not to reset it.
- **WipperSnapper lists it but ships no firmware.** The board has a full
  definition, a configurator entry with a pin map and `sdCardCS: 23`, and a
  product URL, and no build in any release.
- It has dropped off the bus at times for reasons nobody has pinned down.

## Metro RP2350

- **The probe plugs straight in**, same 3-pin connector as the RP2040. Its
  probe serial starts `E661`. The other five start `E664`. Easy to miss when
  grepping.
- **Stock OpenOCD 0.12.0 has no `rp2350.cfg`.** Under another target config the
  probe reports `Could not find MEM-AP to control the core`. So there is no
  `init; reset run` path. The raspberrypi fork has the config and is installed,
  but has not been tried on this station. It would make the board SWD-flashable
  and remove its bootloader step.
- **BOOTSEL is the last rung, not more VBUS cycling.** Once it came back from a
  power-up powered but off the bus, answering SWD with `DPIDR 0x4c013477`. Plain
  `-a on`, three VBUS cycles including a long `-r 80 -w 300`, and a reset
  through the probe all failed. Hold BOOT, tap RESET, release BOOT, then copy
  the UF2. The bootloader appeared in 15 s as `2e8a:000f RP2350 Boot`, and
  CircuitPython was back 9 s after the copy. That needs a person.
- **BOOTSEL is also the best diagnostic.** A board that will not enumerate
  normally but does in BOOTSEL has proven its cable, data lines and USB hardware
  in one step. The fault is in firmware.
- **A 1200-baud touch gives a real `RP2350` drive**, so no bootloader install
  step.
- **WipperSnapper is offline only** (`1.0.0-offline-beta.5`). It logs to an SD
  card, its MAC reads `00:00:00:00:00:00` by design, and there is no MQTT to
  check. **That build drops off the bus about every 18 s** on its own. Give
  volume lookups a budget longer than that.

## Metro ESP32-S2

**The JTAG TAP on this unit is dead.** It worked once: live TAP `0x120034e5`,
halt and PC read through both a J-Link PLUS and a J-Link EDU Mini. From two
days later it returned all ones under clean conditions: in ROM download mode,
`SOFT_DIS_JTAG` and `HARD_DIS_JTAG` both false, no secure boot or encryption,
VTarget 3.29 V, tried at 1000, 500, 200 and 100 kHz, J-Link straight to the
board. The one event in between was a solder short while building an FT232H
adapter. The schematic shows TCK, TDO and TDI run straight from the module to
the header with no resistors or protection. The board is otherwise healthy.

- **To reach its JTAG at all, it must be in ROM download mode.** The shipped
  factory sketch drives TDO low and gives all zeroes with a good probe.
- **A J-Link EDU Mini is enough.** An earlier day of "the EDU Mini never works"
  was measured against a dead beta board, which returns all ones to anything.
- **The header has to be soldered on.**

### Serial console

A CP2102 USB serial cable is the fallback. The notes disagree on whether it is
still connected to this board, so check before relying on it.

What it can do: show ROM and second-stage bootloader output, carry data both
ways, run `esptool` for a full erase and reflash once the board is in ROM
download mode (the real recovery path when the REPL is gone), and read
`supervisor.runtime.safe_mode_reason`, the first thing to check when a board
comes back looking untouched. What it cannot do: halt, step, read registers or
set breakpoints.

- **The console pins are `GPIO43` and `GPIO44`**, which are `board.DEBUG_TX`
  and `board.DEBUG_RX`. `board.TX` and `board.RX` are `GPIO5` and `GPIO6` and
  are not connected to the cable. A `busio.UART` on TX and RX reads a clean
  nothing and looks exactly like a dead adapter. That cost half an hour and a
  wrong verdict before `dir(board)` showed the `DEBUG_` pair. See
  `ports/espressif/boards/adafruit_metro_esp32s2/pins.c`.
- **Wiring:** black GND, green is TX out of the cable to board RX, white is RX
  into the cable from board TX, red is 5 V and stays disconnected.
- **Open it with DTR and RTS off.** A default open asserts both, which would
  hold the board in reset if those wires were ever added:
  `python3 -m serial.tools.miniterm --dtr 0 --rts 0 --raw /dev/ttyUSB0 115200`
- **DTR and RTS do not reset it.** Pulsing them gives no re-enumeration, and
  `esptool --before default-reset` gives `No serial data received`. Bootloader
  entry is a 1200-baud touch or the buttons.
- **The console goes quiet after `entry 0x4004a110` by design.** Release builds
  set `CONFIG_ESP_CONSOLE_NONE=y`, so the app prints nothing there. A
  `make DEBUG=1` build selects the debug sdkconfig and should stream
  CircuitPython's output down the same cable. Not tried.
- **Every power cycle prints a cut-off first banner** before the clean
  `rst:0x1 (POWERON)` one. The chip starts to boot on falling VBUS. Not a
  fault.

### Other S2 traps

- **The 1200-baud touch lands in ROM download mode, `303a:0002`,** not a drive.
  Write tinyuf2 with esptool first. See [flashing.md](flashing.md).
- **When the REPL is dead, get into ROM mode with a one-shot `code.py`** that
  restores the idle sketch, then calls
  `microcontroller.on_next_reset(microcontroller.RunMode.BOOTLOADER)` and
  `microcontroller.reset()`. It must be a software reset. The flag lives in RTC
  memory and a VBUS power cycle clears it, which is why doing this from
  `boot.py` plus a hub cycle silently fails. It lands in `303a:0002` in 4 s.
- **When wedged** (`0101 power connect`, `error -71`, `unable to enumerate`) it
  needs a long power-off: `-a off -r 20 -w 200`, sleep 6, `-a on`. A wedged
  board took up to four rounds. A healthy one came back first time on all four
  tries.
- **Its CIRCUITPY drive is under 1 MB.** An install once left a 958 KB
  WipperSnapper file on a 941 KB filesystem, and `code.py` failed with
  `No space left on device` while every other check read green. Clear old files
  first.
- **Firmware caveat, not the cause of the dead TAP:** CircuitPython's
  `reset_all_pins()` walks GPIO 0 to 46, and the forbidden-reset mask does not
  cover 39 to 42, the JTAG pins, so they get moved to plain GPIO
  (circuitpython #3843, #4211). Tested and ruled out here.

## Metro ESP32-S3

**Its own USB cable is the debugger.** A USB-Serial-JTAG controller in fixed
hardware on GPIO19 and GPIO20 gives halt, step, registers and flash access with
no probe. It enumerates as `303a:1001 USB JTAG/serial debug unit`. The IDCODE
is `0x120034e5` on both cores. Use the Espressif OpenOCD fork. See
[debug.md](debug.md).

- **Unusable while CircuitPython runs.** The S3 has two USB controllers and one
  USB PHY. When CircuitPython starts TinyUSB for its drive, the PHY switches
  over and the JTAG device leaves the bus. You get JTAG or CIRCUITPY, not both
  (circuitpython #7992). Attaching after that gives
  `Error: esp_usb_jtag: could not find or open device!`
- **A software reset does not give the PHY back.** Only a power-on reset does.
  So power cycle the port and attach within about 0.6 s.
- **Halting does not drop JTAG.** The controller is hardware and survives a core
  reset. What dies on a breakpoint is the USB serial console, which needs the
  CPU. You lose the console while halted, not the debugger.
- **`cpu1` reporting `Unexpected OCD_ID = 00000000`** is expected when the
  second core is parked. `cpu0` debugs normally.
- **Do not attach an external J-Link.** It corrupted the internal scan and gave
  a garbage IDCODE, `0x00012c25`, with two masters on GPIO39 to 42 at once. The
  S3 also stopped enumerating while that ribbon was attached and recovered when
  it came off. Unplug external probes before using the built-in JTAG.
- **External JTAG on the header reads all ones by design.** The TAP is routed to
  the USB peripheral until an eFuse is burned. So the S3 cannot serve as a
  control for testing an external adapter.
- **Going external costs an irreversible eFuse** (`DIS_USB_JTAG`, or
  `STRAP_JTAG_SEL` with GPIO3 low at reset) **and the microSD slot**, since
  GPIO39 and GPIO42 are the SD clock and MOSI, and GPIO40 and 41 are TX and RX.
  Not worth it.
- **The 1200-baud touch lands in DFU (`303a:0009`) or USB-JTAG (`303a:1001`)**,
  never a drive. esptool talks to both.
- **`303a:1001` on its own is not bricked.** It means no valid app booted.
  esptool recovers it.
- **Its USB ID follows whatever is running:** `239a:0145` CircuitPython,
  `303a:1001` USB-JTAG, `303a:0009` DFU. A PID change is not a board change.
- **In USB-JTAG mode it resists power-off.** It needs `-r 80 -w 300`, about
  24 s, where `-r 30 -w 400` never worked. Running CircuitPython it powers down
  normally. An earlier belief that it was self-powered was wrong: it read `a0`,
  bus-powered.
- **Two hardware breakpoints per core.** Without the fork's flash driver,
  `next` turns into `step` once they run out.
- **After a core reset the strapping pins are not read again**, so it can stay
  in download mode. Use `esptool --after watchdog-reset` or power cycle.
- **Deep sleep powers the JTAG controller down.** Flash encryption or secure
  boot disable JTAG permanently.

## Both ESP32 boards

- **The touch never gives a drive.** Put tinyuf2 on with esptool, then copy the
  UF2. Read `flash_args` from the tinyuf2 zip every time. The S2 and S3 offsets
  differ in three places, and the S2 numbers on an S3 leave it at `303a:1001`
  with nothing to boot.
- **`microcontroller.RunMode.UF2` does nothing on espressif.** The board reboots
  straight back into CircuitPython.
- **Never extract an ESP32 UF2 and write it flat.** It overwrites the bootloader
  region and the board stops enumerating.
- **One esptool command per download-mode entry.** The chip drops back to
  CircuitPython seconds after esptool exits, even with `--after no-reset`. A
  second command then talks to CircuitPython, and its sync bytes can fill the
  serial buffer so every later write blocks. Power cycle the port to boot.
- **Touch and write right away.** A board left idle in ROM download mode makes
  esptool fail at `Connecting...` with rc=1 and no error text.
- **The first run after a firmware change is about 6 s slower** on both.
- **REPL pastes sometimes arrive corrupted.** The sign is a `SyntaxError` at a
  different line each time for the same input. Only these two boards, never the
  ARM ones. Not explained. Script size, line length and the number of
  connect cycles were all ruled out. Rerun, and do not count a single failed
  pass as a result.

## Rig-wide

- **`0x2ba01477` is ambiguous.** The SAMD51, nRF52840 and STM32F405 all report
  it, because the DPIDR identifies the Cortex-M4 debug port, not the chip.
  Power one board at a time to tell them apart.

  | DPIDR | Meaning |
  |---|---|
  | `0x0bc11477` | Cortex-M0+ (SAMD21) |
  | `0x2ba01477` | Cortex-M4: SAMD51, nRF52840 or STM32F405 |
  | `0x0bc12477` | RP2040 |
  | `0x4c013477` | RP2350 |
  | `0x120034e5` | Xtensa JTAG IDCODE (ESP32 family) |
  | silent | unpowered, held by firmware, or not SWD |

- **The Pi Debug Probe is SWD only.** Asked for JTAG it answers
  `CMSIS-DAP: JTAG not supported` before driving a pin. A probe on an ESP32
  header sits silent forever. That is correct, not a wiring fault.
- **All ones vs all zeroes on TDO.** All ones means nothing is driving it, which
  is ambiguous: open wire, unpowered target, reassigned pin. Never chase TDI on
  all ones. All zeroes means something is driving it low: reset, a pin used as
  an output, a short, or a connector rotated 180 degrees.
- **`VTarget` near 3.3 V proves contact, not orientation.** A rotated cable
  still reads about 3.3 V because the reference pin lands on a pulled-up reset
  line. A misaligned cable once read 2.72 V and was caught that way.
- **Put `adapter speed` after `-f target/...`.** All four stock target configs
  used here set their own speed.
- **The probes cannot be powered down remotely.** They are on a hub with no
  per-port switching. That is on purpose: a debugger should outlive the board
  it is debugging.
- **The hub's physical buttons sit upstream of `uhubctl`.** If one is off,
  `uhubctl` still reports success and the port reads `0100 power` while no
  current reaches the board. SWD getting `cannot read IDR` from a board that
  normally answers confirms it. Only a person can fix that.
