# For an LLM operating a board farm

You are being asked to flash, test, debug or recover real microcontroller
boards over SSH. This repo records how one such farm works and what went wrong
learning it. Use it as knowledge, not as a tool to run blind.

## Read in this order

1. This file.
2. [docs/traps.md](docs/traps.md). Every line is a mistake already made once.
3. [docs/boards.md](docs/boards.md) for the board you are touching.
4. The doc for the task: [flashing](docs/flashing.md),
   [recovery](docs/recovery.md), [debug](docs/debug.md),
   [wippersnapper](docs/wippersnapper.md), [setup](docs/setup.md).
5. [scripts/README.md](scripts/README.md) before running any script.

## Hard rules

1. **Address boards by USB path, resolved at the moment of use.** Never cache a
   `ttyACM` number, a `/dev/sd` letter or a `CIRCUITPY` label.
2. **Confirm identity before writing.** Read `boot_out.txt` or `board.board_id`
   and check it names the board you mean.
3. **Check the destination before every copy.** A boot drive has `INFO_UF2.TXT`
   and no `boot_out.txt`. If the check fails, stop. Do not fall back.
4. **Verify by presence, not by status.** A port that reads `power` and a
   command that returned 0 are not evidence. The device at the expected USB
   path with the expected ID is.
5. **Watch the console before saying a board is healthy.** Correct IDs and
   clean log files have been seen on a board in a reboot loop.
6. **Never switch an uplink port or the probe hub.**
7. **Never use sudo in a script.** If something needs root, stop and tell the
   user. Do not ask for credentials.
8. **Wait for the `>>> ` prompt** before sending anything to a REPL.
9. **Back up a board's drive before you write to it.** Restore and compare by
   checksum when you are done.
10. **Ten trials, not two.** State the count with every rate you report.
11. **Get a positive control before recording a negative.**
12. **Say "unknown".** Do not fill a gap with a guess, and mark what you did not
    test.

## What in this repo is specific to one farm

Replace these before anything works on another rig.

| Thing | Here | How to find yours |
|---|---|---|
| Station USB paths | `3-3.2` ... `3-3.3.4.4` | `ls /sys/bus/usb/devices/`, plug boards in one at a time |
| Hub location and port per station | `-l 3-3.3.4 -p 2` | `uhubctl` with no arguments |
| Uplink ports | `3-3` p3, `3-3.3` p4 | ports whose device is another hub |
| Probe serials | `E6647C74...` | `cat /sys/bus/usb/devices/*/serial`, then power one board down and see which probe goes silent |
| Host paths | `~/cp-tip`, `~/arm-toolchain` | [docs/setup.md](docs/setup.md) |
| Mount root | `/media/sklarm/` | `findmnt` |

## What transfers to any farm

- The addressing rule and the helpers in `scripts/farm-helpers.sh`.
- The recovery order per MCU family.
- The per-chip flash offsets, adapter speeds and OpenOCD target configs.
- The measurement rules.

## What this repo does not know

Do not present these as established.

- Whether the raspberrypi OpenOCD fork resets and flashes the RP2350 station.
  It is installed and untested.
- Whether the Metro M0's NeoPixel works with the probe unplugged.
- Any Arduino build or flash timing across the farm.
- Why REPL pastes to the ESP32 boards sometimes arrive corrupted.
- Whether the ESP32-S2's serial console cable is still connected.

## Before you act

Read the live state. Do not trust a table, including the ones here.

```sh
for p in 3-3.2 3-3.3.1 3-3.3.2 3-3.3.3 3-3.3.4.1 3-3.3.4.2 3-3.3.4.3 3-3.3.4.4; do
  printf "%-10s %s:%s  %s\n" $p \
    "$(cat /sys/bus/usb/devices/$p/idVendor 2>/dev/null)" \
    "$(cat /sys/bus/usb/devices/$p/idProduct 2>/dev/null)" \
    "$(cat /sys/bus/usb/devices/$p/product 2>/dev/null)"
done
```

Expected on this farm when everything runs CircuitPython:

| Path | ID | Board |
|---|---|---|
| `3-3.2` | `239a:813e` | Metro RP2040 |
| `3-3.3.1` | `239a:8038` | Metro M4 AirLift Lite |
| `3-3.3.2` | `239a:8014` | Metro M0 Express |
| `3-3.3.3` | `239a:802a` | Feather nRF52840 Express |
| `3-3.3.4.1` | `239a:80e0` | Metro ESP32-S2 |
| `3-3.3.4.2` | `239a:814e` | Metro RP2350 |
| `3-3.3.4.3` | `239a:0145` | Metro ESP32-S3 |
| `3-3.3.4.4` | `239a:805a` | Feather STM32F405 Express |

## Reporting

- Lead with what you ran and what you ran it on. Versions read back off the
  board, not versions you think you flashed.
- A small table of numbers beats a paragraph.
- Separate what you measured from what you infer.
- Log your own mistakes next to the hardware's.

A Claude Code skill version of this is in
[skills/hil-farm/SKILL.md](skills/hil-farm/SKILL.md). Copy that directory into
`~/.claude/skills/` and edit the host and port map.
