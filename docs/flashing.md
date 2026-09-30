# Flashing

How firmware gets onto each board with nobody pressing a button.

## Timings

One 4-core host.

| Job | How | Time | Notes |
|---|---|---|---|
| Flash CircuitPython, 8 boards | parallel | 32.9 s | flash, boot, mounted, `code.py` checksummed |
| Flash WipperSnapper, 4 boards | parallel | 80.7 s | release binaries, includes the verify wait |
| Build CircuitPython, 8 boards | one at a time, `make -j4` | 11 min 42 s | |
| Arduino | | not measured | single sketches only, see below |

Build time per board, from an earlier run than the 11 min 42 s total. These
rows add up to 15 min 41 s:

| Board | Build |
|---|---|
| Metro M0 Express | 41 s |
| Feather STM32F405 | 51 s |
| Feather nRF52840 | 59 s |
| Metro RP2040 | 66 s |
| Metro M4 AirLift | 70 s |
| Metro RP2350 | 70 s |
| Metro ESP32-S3 | 172 s |
| Metro ESP32-S2 | 412 s |

Flash time per board, from [scripts/fastcp.sh](../scripts/fastcp.sh):

| Board | Route | Release images | Built from main |
|---|---|---|---|
| Metro M4 AirLift | SWD at 2000 kHz | 18.6 s | 19.2 s |
| Metro M0 Express | SWD at 2000 kHz | 19.1 s | 19.6 s |
| Metro RP2040 | UF2 drive | 26.5 s | 29.8 s |
| Metro ESP32-S2 | tinyuf2 + UF2 | 26.5 s | 25.0 s |
| Metro RP2350 | UF2 drive | 29.2 s | 26.8 s |
| Feather STM32F405 | SWD, 1000 kHz requested | 29.2 s | 29.5 s |
| Metro ESP32-S3 | tinyuf2 + UF2 | 29.5 s | 26.9 s |
| Feather nRF52840 | SWD, 4000 kHz requested | 30.5 s | 30.2 s |
| **Wall clock** | | **32.9 s** | **32.9 s** |

The clock starts when `code.py` is written and stops when the last board is
back with a mounted drive and a valid `boot_out.txt`. Downloads and image
extraction are done beforehand.

The nRF52840 sets the floor. Its 30 s is flash write at 22 KiB/s. Asking for a
faster adapter clock did not change it, but see the note on speeds below. The first run after a firmware change costs
the two ESP32 boards about 6 s more each.

It took four passes to get here: 294 s, 165 s, 87 s, 32.9 s.

## Which route for which board

| Board | Bootloader entry | Image push |
|---|---|---|
| Metro RP2040 | 1200-baud touch | `cp` the `.uf2` to the boot drive |
| Metro RP2350 | 1200-baud touch | `cp` the `.uf2` to the boot drive |
| Metro ESP32-S2 | 1200-baud touch, lands in ROM `303a:0002` | `esptool` writes tinyuf2, then `cp` the `.uf2` |
| Metro ESP32-S3 | 1200-baud touch, lands in `303a:0009` or `303a:1001` | same |
| Metro M4 AirLift | none | `openocd program` at `0x4000` |
| Metro M0 Express | none | `openocd` at `0x2000` |
| Feather nRF52840 | none | `openocd`, two runs at `0x26000` and `0x27000` |
| Feather STM32F405 | none | `openocd` at `0x08000000`, or `dfu-util` from the ROM bootloader |

Use SWD wherever a probe is wired. It skips bootloader entry, needs no mount,
and is the fastest route on the farm.

## The 1200-baud touch

Open the board's serial port at 1200 baud and close it. The board reboots into
its bootloader. This is the remote version of double-tapping reset.

```sh
touch1200() { local d=$(bypath $1); [ -n "$d" ] || return 1
  python3 -c "import serial,time;s=serial.Serial('$d',1200);time.sleep(0.25);s.close()"; }
touch1200 3-3.3.4.2
```

What it gives you differs by family:

| Family | After the touch |
|---|---|
| RP2040, RP2350 | A UF2 drive |
| SAMD21, SAMD51 | A UF2 drive, but it has gone stale on the M4. Use SWD |
| nRF52840 | PID flips to `239a:002a`, CDC only. No drive ever appears. Use SWD |
| ESP32-S2 | ROM download mode, `303a:0002`. Not a drive |
| ESP32-S3 | DFU `303a:0009` or USB-JTAG `303a:1001`. Not a drive |
| STM32F405 | Nothing. There is no UF2 bootloader. See the DFU section below |

## UF2 drive boards

```sh
source scripts/farm-helpers.sh
touch1200 $USB
BV=$(vol_boot $USB 30)            # has INFO_UF2.TXT and no boot_out.txt
[ -n "$BV" ] && { cp image.uf2 "$BV/"; sync; }
V=$(vol_cp $USB 45)               # the running CIRCUITPY, by USB path
```

Check the destination before every copy. A boot drive has `INFO_UF2.TXT` and no
`boot_out.txt`. If the check fails, stop. Do not fall back to another volume.
A wrong lookup once copied an 899 KB image onto a 492 KB live filesystem and
corrupted it.

## SWD boards

```sh
Q='-c "gdb_port disabled" -c "tcl_port disabled" -c "telnet_port disabled"'

# Metro M4 AirLift (SAMD51). Connect at 500, raise to 2000 after init.
openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" $Q -f target/atsame5x.cfg \
  -c "adapter speed 500" -c "init" -c "adapter speed 2000" -c "halt" \
  -c "program m4_0x4000.bin 0x4000 reset exit"

# Metro M0 Express (SAMD21). App base 0x2000. reset halt, not halt.
openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" $Q -f target/at91samdXX.cfg \
  -c "init" -c "adapter speed 2000" -c "reset halt" \
  -c "flash write_image erase m0_0x2000.bin 0x2000 bin" -c "reset run" -c "shutdown"

# Feather nRF52840. Two runs, the image has a gap.
openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" -c "adapter speed 4000" $Q -f target/nrf52.cfg \
  -c "init" -c "halt" \
  -c "flash write_image erase nrf_0x26000.bin 0x26000 bin" \
  -c "flash write_image erase nrf_0x27000.bin 0x27000 bin" \
  -c "reset run" -c "shutdown"

# Feather STM32F405. 1000 kHz, reset halt, 0x08000000.
openocd -c "source [find interface/cmsis-dap.cfg]" -c "adapter serial $PROBE" \
  -c "transport select swd" -c "adapter speed 1000" $Q -f target/stm32f4x.cfg \
  -c "init" -c "reset halt" \
  -c "flash write_image erase stm32.bin 0x08000000 bin" -c "reset run" -c "shutdown"
```

Each value here was learned by breaking something:

| Board | Rule | What happens otherwise |
|---|---|---|
| M4 AirLift | Connect at 500 kHz | At 2000: `cannot read IDR`, same as an unplugged cable |
| M0 | `reset halt` | A cold attach to a healthy board fails. See [boards.md](boards.md) |
| nRF52840 | Never `nrf5 mass_erase` | It erases the UF2 bootloader at `0xF4000` |
| nRF52840 | Split the image at its gap | A blind concatenation puts the second run at the wrong address |
| STM32F405 | 1000 kHz, not 4000 | `failed erasing sectors 4 to 9` with nothing pointing at speed |
| STM32F405 | Write at `0x08000000` | `UF2_OFFSET = 0x8010000` in `mpconfigboard.mk` is for a different variant. Writing there verifies cleanly and bricks the app |
| STM32F405 | Let it settle after a port cycle | Flashing 2 s after a cycle failed three times |
| all | Put `adapter speed` after `-f target/...` | The target config sets its own speed and silently overrides yours |
| all | Disable gdb, tcl and telnet ports | Parallel openocd runs collide on port 3333 |
| all | `adapter serial <SN>` | `cmsis-dap serial` is not valid in 0.12.0 |

Verify by the board enumerating, not by `verify_image`. The bad STM32 offset
verified perfectly.

**The speeds above are what was typed, not always what ran.** Stock OpenOCD
0.12.0 target configs set their own speed: `nrf52.cfg` 1000, `stm32f4x.cfg`
2000 (and again on every reset), `at91samdXX.cfg` 400, `atsame5x.cfg` 2000.
The nRF52840 and STM32F405 commands here, and in `fastcp.sh`, put the flag
before the target config, so by the rule in the table they most likely ran at
1000 and 2000. That would explain why 8000 was no faster than 4000 on the nRF.
The commands are left as they were run, because those are the ones that were
timed. Moving the flag after the config on the nRF52840 has not been tried and
might lower the 30 s floor.

### Getting `.bin` files out of a UF2

```
$ python3 scripts/uf2extract.py firmware.uf2 nrf
firmware.uf2: 2 run(s)
  0x026000  256 bytes
    -> nrf_0x26000.bin
  0x027000  655104 bytes
    -> nrf_0x27000.bin
```

Run it on every new build. Never extract an ESP32 UF2 and write it flat. That
overwrites the bootloader region.

## ESP32-S2 and ESP32-S3

A touch never gives these boards a UF2 drive. So write the small tinyuf2
bootloader with esptool, let it reset into the boot drive, then copy the UF2.

```sh
touch1200 $USB
poll_any $USB "0002 0009 1001" 25     # all acceptable PIDs in one loop
wait_tty $USB 12                      # the tty appears after the PID flips
esptool --chip esp32s2 --port "$(bypath $USB)" --baud 921600 \
  --before no-reset --after hard-reset \
  write-flash --flash_mode dio --flash_freq 80m --flash_size 4MB \
  0x1000 bootloader.bin 0x8000 partition-table.bin \
  0xe000 ota_data_initial.bin 0x2d0000 tinyuf2.bin
BV=$(vol_boot $USB 30)
cp circuitpython.uf2 "$BV/" && sync
```

| | ESP32-S2 | ESP32-S3 |
|---|---|---|
| `--chip` | `esp32s2` | `esp32s3` |
| `--flash_size` | `4MB` | `16MB` |
| `bootloader.bin` | `0x1000` | `0x0` |
| `partition-table.bin` | `0x8000` | `0x8000` |
| `ota_data_initial.bin` | `0xe000` | `0xe000` |
| `tinyuf2.bin` | `0x2d0000` | `0x410000` |

Read `flash_args` out of the tinyuf2 zip every time. Using the S2 offsets on
the S3 leaves it at `303a:1001` with no bootable app. Bootloaders come from
[adafruit/tinyuf2](https://github.com/adafruit/tinyuf2/releases).

More ESP32 rules:

- Touch and write right away. A board left idle in ROM download mode makes
  esptool fail at `Connecting...` with no error text.
- One esptool command per download-mode entry. The chip drops back to
  CircuitPython seconds after esptool exits, and a second command then talks to
  CircuitPython instead of the ROM.
- `microcontroller.RunMode.UF2` does nothing on espressif. The board reboots
  straight back into CircuitPython.
- When the touch does not work, enter ROM mode from the REPL. It must be a
  software reset. A power cycle clears the flag.

```python
import microcontroller as m
m.on_next_reset(m.RunMode.BOOTLOADER)
m.reset()
```

## STM32F405 ROM DFU bootloader

The Feather STM32F405 has no UF2 bootloader. It does have ST's ROM bootloader
at `0x1FFF0000`, which speaks DFU as `0483:df11`.

Over SWD it works every time:

```sh
openocd $Q -c "source [find interface/cmsis-dap.cfg]" -c "adapter serial $PROBE" \
  -c "transport select swd" -c "adapter speed 1000" -f target/stm32f4x.cfg \
  -c "init" -c "reset halt" \
  -c "mww 0x40023844 0x00004000" \
  -c "mww 0x40013800 0x00000001" \
  -c "reg sp 0x20001d80" -c "reg pc 0x1fff3da0" \
  -c "resume" -c "shutdown"
dfu-util -a 0 -s 0x08000000:leave -D firmware.bin
```

The first `mww` clocks SYSCFG. Without it the second write, the memory remap,
is silently dropped. Read `sp` and `pc` from `0x1FFF0000` and `0x1FFF0004` on
your own part and clear the thumb bit on `pc`.

Over USB alone it is a coin flip:

| Variant | Reaches DFU |
|---|---|
| Stock CircuitPython 10.3.0-rc.0, one attempt | 5 / 12 |
| Firmware retry loop, one user trigger | 12 / 12 |
| Arduino sketch, one 1200-baud touch | 1 / 8, then 2 / 8 on a second run |
| Arduino, host retries the touch | 6 / 6, in 1 to 12 touches |

The cause is in ST's mask ROM. See [findings.md](findings.md). The fix is to
retry.

## Arduino

Arduino sketches go on the same way as any other image. Build with
`arduino-cli`, then push the `.bin` over SWD at the board's app base.

```sh
arduino-cli config set board_manager.additional_urls \
  https://adafruit.github.io/arduino-board-index/package_adafruit_index.json
arduino-cli core update-index
arduino-cli core install adafruit:samd

arduino-cli compile --fqbn adafruit:samd:adafruit_metro_m4_airliftlite \
  --output-dir ./build MySketch

openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" -f target/atsame5x.cfg -c "adapter speed 500" \
  -c "program build/MySketch.ino.bin 0x4000 verify reset exit"
```

Cores installed on this farm: `adafruit:samd` and `STMicroelectronics:stm32`
3.0.0. What has been done with them: a serial passthrough sketch on the M4
AirLift, and 1200-baud bootloader tests on the STM32F405. A parallel Arduino
build and flash of all 8 boards has not been done, so there is no timing for it.

Going back to CircuitPython is the same SWD command with the CircuitPython
image.

## Rules for a correct run

- Address every board by USB path. See [traps.md](traps.md).
- Write `code.py` before flashing. A firmware write does not touch the
  filesystem, so the sketch survives.
- Use shell background jobs and `wait`. Eight LLM agents took 159.8 s just to
  start. There is nothing for an agent to decide here.
- Do not stagger the starts.
- Do not poll `udisksctl` in a loop. Eight loops contend on the udisks daemon
  and the boards waiting on a mount become the slowest. Poll `findmnt`, and
  call `udisksctl` a few times behind a lock. `_vol` in `farm-helpers.sh` does
  this.
- Poll for events, not fixed sleeps. Poll every acceptable state in one loop.
  Polling them one after another cost the S3 28 s.
- A board that reports 0.4 s in a `fastcp.sh` run was not flashed. It found a
  stale mount.
- The first write after a mount can fail with `Input/output error`. Retry once.
- An install does not always reformat. Clear old files first. An ESP32-S2 once
  kept a 958 KB file on a 941 KB filesystem and `code.py` could not be written.
- Run [scripts/verify.sh](../scripts/verify.sh) afterwards. Volume names printed
  during the run are progress output, not proof.
