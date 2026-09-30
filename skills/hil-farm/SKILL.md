---
name: hil-farm
description: Drive a hardware-in-the-loop microcontroller board farm over SSH. Use whenever work involves flashing, testing or debugging on real boards, mentions the farm, uhubctl, a debug probe, OpenOCD, or a specific Metro or Feather board.
---

# HIL farm

Eight boards on a pegboard, one Linux host, per-port USB power control, a debug
probe per ARM board. Assume nothing about state: read it.

This skill is the short form. The long form is the `docs/` directory of
https://github.com/mikeysklar/hil-farm-explained. Read `docs/traps.md` and the
section of `docs/boards.md` for the board you are touching when this page is
not enough.

Edit the Access and Port map sections for your own farm.

## Access

`ssh <farm-host>`.

`sudo` needs a password, so anything root is an attended step and cannot go in
a script. Do not try to work around it, and never ask the user to hand over
credentials.

## The addressing rule, which matters more than anything else here

**Resolve every board from its USB path, at the moment of use.** Never cache a
`ttyACM` number, a `/dev/sd?`, or a `CIRCUITPY<n>` label. All three are
assigned in enumeration order and shuffle on every reflash, power cycle and
bootloader round trip.

```sh
P=3-3.3.4.2                       # the board's hub port path
blk=$(ls -d /sys/bus/usb/devices/$P/$P:1.*/host*/target*/*/block/* | head -1)
dev=/dev/$(basename "$blk")1
mnt=$(findmnt -n -o TARGET "$dev")
grep -q adafruit_metro_rp2350 "$mnt/boot_out.txt" || { echo "wrong board"; exit 1; }
```

Serial ports the same way. The by-path name drops the leading `3-`:

```sh
bypath() { ls /dev/serial/by-path/*usb-0:${1#*-}:1.0 2>/dev/null | head -1; }
TTY=$(bypath $P)
```

Confirm identity from `boot_out.txt` before writing anything. This has bitten
twice: a cached `ttyACM20` soft-reset the wrong board, and a `CIRCUITPY6` that
had become a different board between two commands.

## Port map

Trust the live bus over any table, including this one.

| Board | Port | Probe | What bites |
|---|---|---|---|
| Metro RP2040 | `3-3.2` | `E6647C740359092F` | Needs a full VBUS cycle, `-a on` is a no-op. `rp2040.cfg` will not attach even when a DPIDR sweep succeeds: SWD diagnoses power here, it does not reset |
| Metro M4 AirLift | `3-3.3.1` | `E6647C740349682C` | Connect at 500 kHz; at 2000 it reports `cannot read IDR`. The same error at 500 means something is holding SWDIO: reset, then attach. VBUS cycling does nothing. App base `0x4000` |
| Metro M0 Express | `3-3.3.2` | `E6647C74039F6B2D` | SWDIO and SWCLK are LED pins, so a cold attach fails on a healthy board and succeeds on a broken one. Use `reset halt`. No `binascii`, no `zlib`, no `ulab`. `microcontroller.reset()` is hazardous |
| Feather nRF52840 | `3-3.3.3` | `E6647C74034E732F` | Bootloader is CDC only: the 1200-baud touch flips the PID but no boot volume appears. Flash over SWD in two runs. Never `nrf5 mass_erase` |
| Metro ESP32-S2 | `3-3.3.4.1` | none | No working JTAG. Debug UART is `GPIO43/44` = `board.DEBUG_TX/RX`. Wedges easily, needs a long power-off |
| Metro RP2350 | `3-3.3.4.2` | `E6614103E7687D25` | Stock openocd has no `rp2350.cfg`, so no SWD reset path. BOOTSEL is the last rung, not more VBUS cycling |
| Metro ESP32-S3 | `3-3.3.4.3` | built-in USB-JTAG | JTAG is unusable while CircuitPython runs, and that survives a soft reset. Do not attach an external J-Link. Needs `-r 80 -w 300` to power off in USB-JTAG mode |
| Feather STM32F405 | `3-3.3.4.4` | `E6647C740327322C` | No UF2 bootloader, but the ST ROM DFU is always at `0x1FFF0000`. `adapter speed 1000`, `reset halt`, write at `0x08000000`. Must be settled before flashing |

Probes live on a hub with no per-port switching. They are always on.

## Power control

`uhubctl` works unprivileged via a udev rule. **Never `sudo -n uhubctl`**: sudo
prompts, both halves return rc=1 silently, the port is never cut, and it looks
like a board that refuses to reset.

```sh
uhubctl -S -l 3-3.3.4 -p 3 -a off -r 30 -w 400     # one port only
uhubctl -S -l 3-3.3.4 -p 3 -a on
```

Then wait 10 to 12 seconds after re-enumeration. Retrying at 2 s fails.

Never switch an uplink port. If a port stays at `0100 power` after off, the off
did not take: use longer repeats. If it reaches `0000 off` and the device is
still there, the board has its own power supply.

## Flashing

**UF2 boards (RP2040, RP2350).** 1200-baud touch, wait for the boot volume,
check it has `INFO_UF2.TXT` and no `boot_out.txt`, copy.

```sh
python3 -c "import serial,time; s=serial.Serial('$TTY',1200); time.sleep(0.25); s.close()"
```

**SWD boards (M0, M4, nRF52840, STM32F405).** No bootloader step. Extract
`.bin` runs from the UF2 with `scripts/uf2extract.py`, then `openocd`. Offsets
and speeds are in `docs/flashing.md`.

**ESP32.** The touch lands in ROM or DFU mode, never a drive. Write tinyuf2
with esptool, then copy the UF2. If the touch fails, from the REPL:

```python
import microcontroller as m; m.on_next_reset(m.RunMode.BOOTLOADER)
m.reset()
```

S3 becomes `303a:0009`, S2 `303a:0002`, same USB path.

One esptool invocation per download-mode entry. The chip falls back to
CircuitPython within seconds of esptool exiting, and a second command then
talks to CircuitPython instead of the ROM. Power cycle the port to boot
afterwards.

Always pass `write_timeout=5` to `serial.Serial` on these ttys, or a wedged
port hangs the helper instead of raising.

## Recovery

| Symptom | Fix |
|---|---|
| Drive gone, tty alive | `import microcontroller; microcontroller.reset()` |
| `code.py` disabled the drive and reruns every boot | `microcontroller.on_next_reset(m.RunMode.SAFE_MODE)` then reset |
| Host and Python both see read-only | Same: safe mode |
| Serial accepts a connection but the first write blocks | Power cycle that port, wait 10 to 12 s |
| SAMD board missing after bring-up | SWD `init; reset run; exit` |
| RP board missing after bring-up | Full VBUS off and on |
| SAMD wedged, USB dead | RAM poke: `mww 0x20007ffc 0xf01669ef` on SAMD21, `0x2002fffc` on SAMD51, then `reset run` |
| SWD says `cannot read IDR` at 500 kHz | Something owns SWDIO. Reset and attach again. Do not conclude the cable is bad |
| Boot volume has a label but will not mount | Its size reads 0. The bootloader's drive went stale. Re-enter the bootloader |
| Every port powered, nothing connected, SWD dead | The hub's physical power button is off. Needs a person |

## Traps that have already cost real time

- **The REPL eats the first keystroke.** At "Press any key to enter the REPL"
  the first character is consumed. Sync on the `>>> ` prompt first.
- **Two trials is not a measurement.** A 42% effect comes up empty twice in a
  row 34% of the time. Ten or more, with a control.
- **Volume labels lie.** A run reported two boards as `CIRCUITPY5` and looked
  green while one board had never come up.
- **`bmAttributes` does not tell you the power topology.** It follows whichever
  USB stack is running.
- **A CircuitPython UART that will not transmit is not a hardware fault.** An
  Arduino sketch drove the same pin first try.
- **Static checks all green does not mean alive.** A board was reported healthy
  while in a 25 s watchdog reboot loop. Only the serial console showed it.
- **Verify agent citations against the actual tree.** Scans have cited a
  library's main branch and named functions that are stubs in the pinned
  version.
- **Do not judge firmware version from `strings` on a binary.** Read
  `boot_out.txt`.
- **Run tests one board at a time.** Parallel test runs on a small host
  fabricate failures.

## Working on the farm

Back up a board's drive before you write, restore after, and verify by checksum
against the backup.

Build in a git worktree, not the main checkout.

## Method

- Measure the thing, not a proxy for it.
- Read the source before claiming a root cause; name the mechanism.
- Controls, not single observations.
- Test the test: a monitor that has only ever printed PASS is untested.
- Say "unknown" out loud rather than guessing.
