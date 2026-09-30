# Traps and corrections

Each line here is a belief that was held with confidence and turned out wrong,
or a mistake that cost real time. This is the part worth reading twice.

## The one rule

**Resolve every board from its USB path, at the moment you use it.**

`ttyACM` numbers, `/dev/sd` letters and `CIRCUITPY` labels are handed out in
the order things appear. They change on every reflash, power cycle and
bootloader round trip.

```sh
P=3-3.3.4.2                                   # the board's hub port path

# serial. The by-path name drops the leading "3-".
bypath() { ls /dev/serial/by-path/*usb-0:${1#*-}:1.0 2>/dev/null | head -1; }
TTY=$(bypath $P)

# identity
cat /sys/bus/usb/devices/$P/idVendor /sys/bus/usb/devices/$P/idProduct

# drive
blk=$(ls -d /sys/bus/usb/devices/$P/$P:1.*/host*/target*/*/block/* | head -1)
mnt=$(findmnt -n -o TARGET /dev/$(basename "$blk")1)
grep -q adafruit_metro_rp2350 "$mnt/boot_out.txt" || { echo "wrong board"; exit 1; }
```

What happened without it:

- A cached `ttyACM20` soft-reset a different board.
- A `CIRCUITPY6` became a different board between two commands.
- A run reported two boards as `CIRCUITPY5` and looked green. One board had
  never come up.
- Getting the `3-` prefix wrong returned an empty port, and esptool ran with
  `--port ""`.

Confirm identity from `boot_out.txt` before writing anything.

## Wrong beliefs, and what overturned them

| Believed | Actually | How it was found |
|---|---|---|
| A flash run that prints 8 green flashed 8 boards | Volume labels shuffle mid-run | Verifying by USB path afterwards |
| The M4 AirLift was healthy and online | It was in a 25 s watchdog reboot loop | Every static check was green. Only the serial console showed it |
| STM32F405 has no bootloader | No UF2 bootloader. ST's ROM DFU bootloader is always at `0x1FFF0000` | A `dfu-util` round trip |
| CircuitPython's STM32 bootloader jump is dead code | It works 5 times in 12 | The first claim rested on 2 trials |
| Metro RP2040's port cannot be brought up remotely | It needs a full off and on, not `-a on` | SWD showed the chip alive while off the bus |
| The polkit rule was lost in a reboot | The rule was wrong. SSH needs the `other-seat` action | `pkcheck` |
| ESP32-S3 will not power off because it is self-powered | It was bus-powered and needed more repeats | `bmAttributes` read `a0` |
| A J-Link EDU Mini cannot do the ESP32-S2 | It can | The whole sweep had been run against a dead board |
| The ESP32-S3's JTAG is faulty | An external J-Link on its header was corrupting the scan | Correct IDCODE with the probe removed |
| OpenOCD cannot cold-connect to the Metro M0 | True only for a healthy board | It connected first try to a hung one |
| A speed sweep found the M0's working SWD speed | A J-Link had already halted the core | Speed made no difference on a running board |
| The M0 gives up its NeoPixel by design | It is the debugger-present bit, set by the probe being plugged in | Reading `Pin.c` |
| The M4's ESP32 TX line is broken | CircuitPython did not drive the pin. An Arduino sketch did, first try | Byte counts both ways |
| The nRF52 can only do one audio direction | One endpoint number, both directions | Reading the USB stack, then testing |
| The STM32 is unflashable | It needed to settle after a port cycle | The documented recipe worked unchanged |
| An ESP32-S2 build had the wrong version | `strings` found the ESP-IDF version | `boot_out.txt` |

## Traps

**Measurement**

- Two trials is not a measurement. A 42% effect comes up empty twice in a row
  34% of the time. Ten or more, with a control.
- Get a positive result from a known-good target before recording a negative.
- Green static checks are not evidence of life. Watch the console.
- Re-run the exact thing you publish. A snippet trimmed for an upstream issue
  dropped one line and hung the board 10 times out of 10.
- A one-shot breadcrumb is overwritten by the next boot. Use an append-only log.
- Run test suites one board at a time. Eight in parallel on 4 cores produced
  failures that vanished on a serial rerun.

**Host**

- `lsusb | grep` is not a device check. Read sysfs at the board's path.
- A port reading `power` does not mean the board has power.
- Never `sudo -n uhubctl`.
- `pkill -f` over ssh with a pattern that is also in the remote command kills
  the ssh session.
- Quotes inside `ssh '...'` get eaten. Send a file.

**REPL**

- The first keystroke is eaten. Wait for `>>> `.
- Keep lines short.
- `os.uname().machine` is not the board ID. Use `board.board_id`.

**Flashing**

- Check the destination before every write. Refuse, do not fall back.
- An install does not always reformat the drive.
- The first write after a mount can fail. Retry once.
- Put `adapter speed` after `-f target/...`.
- `verify_image` passing does not mean the board will boot.
- Extract SWD images from each new UF2. Do not reuse old offsets.

**Working with an LLM**

- Check every source citation an agent gives you against the tree you actually
  build. Two scans cited a library's main branch and named functions that are
  stubs in the pinned version.
- The model makes its own mistakes and they belong in the same log as the
  hardware bugs. It was the model that copied an image onto the wrong volume.
- Do not use agents to run parallel flashes. Shell jobs start in milliseconds.
  Agents took over two minutes to start.
- Edit shared files in one place and push from there. A change made on the
  host was overwritten by a later copy from the workstation.

## Method

- Measure the thing, not a proxy for it.
- Read the source before naming a root cause.
- Controls, not single observations.
- Test the test. A monitor that has only ever printed PASS is untested.
- Say "unknown" rather than guess.

## Still unexplained

- REPL paste corruption on the two ESP32 boards.
- `target/rp2040.cfg` failing to attach in stock OpenOCD 0.12.0.
- The RP2350 WipperSnapper offline build dropping off the bus every 18 s.
- ESP32-S3 and STM32F405 showing no audio interfaces with `usb_audio` enabled.
- Whether the Metro M0's NeoPixel works with the probe unplugged. Expected yes,
  not tested.
