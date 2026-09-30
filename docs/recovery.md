# Power control and recovery

No failure should need a person to walk over and press something. This is how
close the farm gets.

## The ladder

Try these in order. The order is different per family.

| Rung | What | Works for | Does not work for |
|---|---|---|---|
| 1 | Reset over the REPL | any board with a live serial port | a board that is off the bus |
| 2 | SWD `reset run` | SAMD21, SAMD51, nRF52840, STM32F405 | RP2040, RP2350 (no usable target config in stock OpenOCD) |
| 3 | VBUS cycle with `uhubctl` | RP2040, RP2350, ESP32-S2, ESP32-S3 | SAMD boards: cutting VBUS does not reliably reset them |
| 4 | Force the bootloader: RAM poke over SWD, or 1200-baud touch | SAMD (poke), anything with a live tty (touch) | |
| 5 | A person: BOOTSEL, or the hub's power button | everything | |

SWD first for the two SAMD boards, VBUS cycle for whatever is left. The other
way round wastes 12 s a port and looks like a hardware fault.
[scripts/farm-up.sh](../scripts/farm-up.sh) does it in that order.

## Rung 1: over the REPL

| Symptom | Fix |
|---|---|
| Drive gone, tty alive | `import microcontroller; microcontroller.reset()` |
| `code.py` breaks the drive on every boot | `microcontroller.on_next_reset(microcontroller.RunMode.SAFE_MODE)` then reset. Safe mode skips `code.py` |
| Host and Python both see the drive read-only | same, safe mode |

Avoid `microcontroller.reset()` on the Metro M0. See [board-weirdisms.md](board-weirdisms.md).

## Rung 2: SWD reset

```sh
# Metro M4 AirLift (SAMD51). 500 kHz matters.
openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" -f target/atsame5x.cfg \
  -c "adapter speed 500" -c "init; reset run; exit"

# Metro M0 Express (SAMD21)
openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" -f target/at91samdXX.cfg \
  -c "adapter speed 400" -c "init; reset run; exit"
```

Back in 1 to 2 s.

## Rung 3: VBUS cycle

```sh
uhubctl -S -l 3-3 -p 2 -a off -r 30 -w 400 ; sleep 5 ; uhubctl -S -l 3-3 -p 2 -a on
```

Then wait 10 to 12 s. The device is back on the bus well before it is usable.
A retry at 2 s fails.

A port that reads powered with no device is not always unpowered. The Metro
RP2040 sat in that state while SWD showed the chip alive. `-a on` did nothing.
A full off and on fixed it.

## Rung 4: forcing the bootloader

**RAM poke, the remote double-tap.** For a SAMD board with dead USB. No
firmware is written. It sets the magic word the UF2 bootloader looks for, then
resets.

```sh
# SAMD21 (Metro M0)
openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" -f target/at91samdXX.cfg -c "adapter speed 400" \
  -c "init" -c "halt" -c "mww 0x20007ffc 0xf01669ef" -c "reset run" -c "exit"
```

The Metro M0 came up as `239a:0013`, the UF2 bootloader, in about 1 s. That
also proves the USB hardware is good. A plain `reset run` afterwards returns to
CircuitPython. This recovered a board that six VBUS cycles and an SWD reset had
not.

On the SAMD51 the address is `0x2002fffc`.

**1200-baud touch.** See [flashing.md](flashing.md).

## Rung 5: a person

**BOOTSEL.** Hold BOOT, tap RESET, release BOOT. The RP2350 needed this once.
A board that enumerates in BOOTSEL has proven its cable, data lines and USB
hardware in one step.

**The hub's power button.** If every station port reads powered with nothing
connected, and the hub itself still enumerates, the hub's physical switch is
off. `uhubctl` still reports success. To confirm: SWD on a board that normally
answers gives `cannot read IDR`, so no power is reaching it. There is no remote
fix.

## Power control rules

**Off needs repeats.**

```sh
uhubctl -S -l <hub> -p <port> -a off -r 30 -w 400
```

`uhubctl` clears the port power bit. The kernel, still handling the disconnect
it just saw, finds an unpowered port and turns it back on. `-r 30 -w 400`
repeats the off for 12 s and outlasts that. Less than about 10 s of repeats is
unreliable.

- One port at a time. The whole-hub form is worse, and a different port
  bounces back each try.
- `-r` and `-w` only apply to off. If `-a on` does not take, run it again.
- `-a cycle` ends with the port on. Do not use it to shut down.
- Some boards need more: an ESP32-S3 in USB-JTAG mode needs `-r 80 -w 300`.
- `-S` skips the sysfs attempt, which fails without root and only prints noise.

**Run cycles one at a time.** Powering one port on can re-assert power across
the whole hub, so one board's cycle can undo another's. Use a lock:

```sh
cycle() { flock /tmp/uhubctl.lock -c \
  "uhubctl -S -l $1 -p $2 -a off -r 20 -w 250 >/dev/null 2>&1; uhubctl -S -l $1 -p $2 -a on >/dev/null 2>&1"; }
```

**Never switch an uplink port.** A healthy uplink reads
`0503 power highspeed enable connect`. An uplink at `0000 off` means you
switched the wrong port.

**Verify by device, not by port status.** A port reading `power` proves
nothing. Count devices:

```sh
for d in /sys/bus/usb/devices/*; do
  [ "$(cat $d/idVendor 2>/dev/null)" = "239a" ] && echo "$(basename $d) $(cat $d/product)"
done
```

**Self-powered or just stubborn?** If the port reaches `0000 off` and the device
is still there, the board has its own supply. If the port stays at `0100 power`,
the off did not take and needs more repeats. Do not decide from `bmAttributes`.
It follows whichever USB stack is running and has flipped between sessions.

**Probes stay on.** They hang off a hub with no power switching. Only pulling
that hub's power adapter turns them off.

## Shutting down and starting up

Down, deepest hub tier first:

```sh
for dev in $(mount | grep -i circuitpy | awk '{print $1}'); do udisksctl unmount -b "$dev"; done
off() { uhubctl -S -l "$1" -p "$2" -a off -r 30 -w 400 >/dev/null 2>&1; }
off 3-3.3.4 1; off 3-3.3.4 2; off 3-3.3.4 3; off 3-3.3.4 4
off 3-3.3 1;   off 3-3.3 2;   off 3-3.3 3
off 3-3 2
```

About 12 s a port, two minutes for the farm. Then check that no board is left
on the bus.

Up: [scripts/farm-up.sh](../scripts/farm-up.sh). Expect 6 of 8 boards to come
up on their own in about 48 s. The two SAMD boards usually need the SWD reset.

## When you cannot mount

Every board answers on its serial port. Resolve it by USB path, send Ctrl-C,
wait for `>>> `, then send short lines.

- Wait for the `>>> ` prompt before sending. At "Press any key to enter the
  REPL" the first character is eaten, so `import x` arrives as `mport x`.
- Keep lines short. A 110-character line came back as `SyntaxError` on all
  eight boards.
- Put the script in a file and `scp` it. Quotes inside an `ssh '...'` command
  get eaten and change the code the board receives.
- Pass `write_timeout=5` to `serial.Serial`. A wedged port otherwise hangs the
  script instead of raising.
- To iterate, write `code.py` and let auto-reload run it. USB stays up. An SWD
  reset re-enumerates and kills your console.
