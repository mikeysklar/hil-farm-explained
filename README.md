# hil-farm-explained

Eight microcontroller boards on a pegboard, wired so they can be flashed,
tested, debugged and reset over SSH with nobody in the room.

This repo is how I use it, what it cost to learn, and the scripts. It is
written so you can point an LLM at it and have it run a farm like this without
repeating my mistakes. Start it at [AGENTS.md](AGENTS.md).

<!-- photo: the farm on the wall -->

**8 boards, 6 MCU families, 1 Linux host. No button presses in normal use.**

## What I use it for

- Reload CircuitPython, Arduino sketches or WipperSnapper on any node, or all
  of them at once.
- Test a change on every MCU family before it goes to review.
- Reset a hung board or put it in its bootloader remotely. The hub switches
  power per port with `uhubctl`, and a 1200-baud touch enters the bootloader.
- Attach a debugger to any board without finding a cable. Every probe stays
  wired.

## The stations

| Board | Family | Debug path |
|---|---|---|
| Metro RP2040 | RP2 | Pi Debug Probe, 3-pin SWD |
| Metro RP2350 | RP2 | Pi Debug Probe, 3-pin SWD |
| Metro M0 Express | SAMD21 | Pi Debug Probe, 2x5 SWD |
| Metro M4 AirLift Lite | SAMD51 | Pi Debug Probe, 2x5 SWD |
| Feather nRF52840 Express | nRF52 | Pi Debug Probe, 2x5 SWD |
| Feather STM32F405 Express | STM32 | Pi Debug Probe, 2x5 SWD |
| Metro ESP32-S3 | ESP32 | Built-in USB-JTAG |
| Metro ESP32-S2 | ESP32 | None working |

Boards are on a USB hub with per-port power switching. Probes are on a second
hub that is always on, so a debugger outlives the board it is debugging.

## How long things take

One 4-core host.

| Job | Boards | How | Time |
|---|---|---|---|
| Flash CircuitPython and verify | 8 | parallel | 32.9 s |
| Flash WipperSnapper and verify | 4 | parallel | 80.7 s |
| Build CircuitPython from source | 8 | one at a time | 11 min 42 s |
| ulab benchmark pass | 8 | one at a time | 61 s |
| Arduino | | | not measured |

The CircuitPython flash started at 294 s. Details in
[docs/flashing.md](docs/flashing.md).

## No button pressing

| Need | How |
|---|---|
| Reset a board | SWD `reset run`, or cut its port power with `uhubctl` |
| Enter the bootloader | 1200-baud touch on its serial port |
| Bootloader when USB is dead (SAMD) | Write the double-tap magic word to RAM over SWD |
| Flash with no bootloader at all | SWD, straight to flash |
| STM32 ROM bootloader | Jump to it over SWD, then `dfu-util` |

Which one works depends on the chip. A power cycle does not reset a SAMD. An
SWD reset does not work on the RP2040 with stock OpenOCD.
[docs/recovery.md](docs/recovery.md) has the order.

Two things still need a person: BOOTSEL on an RP board that ignores everything
else, and the hub's own power button.

## Setup commands

```sh
# power: one port, off needs repeats
uhubctl -S -l 3-3.3.4 -p 2 -a off -r 30 -w 400
uhubctl -S -l 3-3.3.4 -p 2 -a on

# find a board's serial port by USB path, never by ttyACM number
bypath() { ls /dev/serial/by-path/*usb-0:${1#*-}:1.0 2>/dev/null | head -1; }

# bootloader, no button
python3 -c "import serial,time;s=serial.Serial('$(bypath 3-3.3.4.2)',1200);time.sleep(0.25);s.close()"

# SWD reset through a Pi Debug Probe
openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" -f target/atsame5x.cfg \
  -c "adapter speed 500" -c "init; reset run; exit"

# bring the whole farm up, flash all 8, verify
scripts/farm-up.sh
scripts/fastcp.sh
scripts/verify.sh
```

Host setup is in [docs/setup.md](docs/setup.md).

## Debug hardware

- **Pi Debug Probes**, one per ARM board. RP2040 and RP2350 take the 3-pin
  cable directly. Metros and Feathers with a 2x5 header need a small breakout.
- **ESP32-S3** debugs over its own USB cable.
- **OpenOCD, three builds**: stock for SAMD, nRF52 and STM32, the raspberrypi
  fork for `rp2350.cfg`, the Espressif fork for ESP32.

[docs/debug.md](docs/debug.md)

## Board weirdisms

One line each. The rest is in [docs/boards.md](docs/boards.md).

| Board | Weirdism |
|---|---|
| Metro M0 | NeoPixel and SWCLK share a pin. With a probe attached the pixel cannot be used |
| Metro M4 AirLift | SWD only connects at 500 kHz. A power cycle does not reset it |
| Feather nRF52840 | Bootloader shows no drive. Its image has a gap and must be flashed in two pieces |
| Feather STM32F405 | No UF2 bootloader. The `UF2_OFFSET` in its board config is not where the app goes |
| Metro RP2040 | `-a on` does nothing. It needs a full off and on |
| Metro RP2350 | Stock OpenOCD has no config for it |
| Metro ESP32-S3 | JTAG disappears when CircuitPython starts USB |
| Metro ESP32-S2 | The 1200-baud touch lands in ROM mode, not a drive |

## What it found

- A USB audio device that enumerated correctly and sent zero bytes.
- Why the STM32F405 bootloader jump works 5 times in 12.
- A size optimisation that changed the result of integer division.
- A board that passed every check while rebooting every 25 s.

[docs/findings.md](docs/findings.md)

## Mounting

An IKEA SKÅDIS pegboard. Boards sit on printed rails, hubs and probes on
printed hooks. The rail files are in [cad/](cad). The hook and T-nuts are other
people's designs and are linked from [docs/mounting.md](docs/mounting.md).

<!-- photo: rail close-up -->

## Docs

| | |
|---|---|
| [setup.md](docs/setup.md) | Parts, hub test, udev, polkit, toolchains |
| [flashing.md](docs/flashing.md) | Every flash route, timings, Arduino |
| [wippersnapper.md](docs/wippersnapper.md) | WipperSnapper flashing and the nina-fw upgrade |
| [debug.md](docs/debug.md) | Probes, wiring, which OpenOCD |
| [boards.md](docs/boards.md) | Per-board weirdisms |
| [recovery.md](docs/recovery.md) | Power control and the recovery ladder |
| [traps.md](docs/traps.md) | What I got wrong |
| [findings.md](docs/findings.md) | What the farm found |
| [mounting.md](docs/mounting.md) | Pegboard, rails, hooks |
| [scripts/](scripts) | The scripts, with the constants to change |
| [skills/hil-farm/](skills/hil-farm/SKILL.md) | A Claude Code skill for driving the farm |

## Limits

The scripts have my USB paths and probe serial numbers in them. They are
examples to adapt, not a tool to install. Several things are still unexplained
and are listed at the end of [docs/traps.md](docs/traps.md).
