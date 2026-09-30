# Debug hardware

Every board has a second way in that does not depend on its own USB stack. That
is what turns a stuck board into a recoverable one.

## What plugs into what

| Board | Debug connector | Adapter | Debugger |
|---|---|---|---|
| Metro RP2040 | 3-pin JST-SH SWD | none, plugs direct | Pi Debug Probe |
| Metro RP2350 | 3-pin JST-SH SWD | none, plugs direct | Pi Debug Probe |
| Metro M0 Express | 2x5 1.27 mm | #1675 cable + #2743 breakout + 3-pin header | Pi Debug Probe |
| Metro M4 AirLift | 2x5 1.27 mm | same | Pi Debug Probe |
| Feather STM32F405 | 2x5 1.27 mm | same | Pi Debug Probe |
| Feather nRF52840 | 2x5 1.27 mm | same | Pi Debug Probe |
| Metro ESP32-S3 | its own USB port | none | built-in USB-JTAG |
| Metro ESP32-S2 | 2x5 1.27 mm JTAG | J-Link or FT2232H | none on this farm, see below |

The dividing line is protocol, not connector shape. The six ARM boards speak
SWD. The two ESP32 boards are Xtensa and speak 4-wire JTAG. A 2x5 header on an
ARM board and a 2x5 header on an ESP32 board look the same and are not
interchangeable.

Six probes for six ARM boards, no spares. So a silent probe is always a real
fault.

## Pi Debug Probe wiring

Use the probe's **D** port. Only three wires matter.

| Wire | Signal |
|---|---|
| Orange | SWCLK |
| Black, middle | GND |
| Yellow | SWDIO |

Nothing crosses over. Clock to clock, data to data. The 3-pin cable has no
reset line, so a remote reset is either an SWD `reset` command or a USB port
power cycle.

SWDIO is bidirectional. A loose yellow pin shows up as an intermittent "target
not found", not a clean failure.

The Pi Debug Probe firmware is SWD only:

```
Info : CMSIS-DAP: SWD supported
Error: CMSIS-DAP: JTAG not supported
```

A probe plugged into an ESP32 JTAG header sits silent forever. That is correct
behaviour. Do not debug it as a wiring fault.

## Which OpenOCD

Stock OpenOCD 0.12.0 does not cover the whole farm. Three builds are in use.

| Build | Install path here | Use for |
|---|---|---|
| Stock 0.12.0 | `/usr/bin/openocd` | SAMD21, SAMD51, nRF52, STM32F4. Has `rp2040.cfg`. No `rp2350.cfg`. Cannot flash ESP32 |
| [raspberrypi fork](https://github.com/raspberrypi/openocd) | `~/.local/openocd-rp2350/bin/openocd` | The only one with `rp2350.cfg` |
| [Espressif fork](https://github.com/espressif/openocd-esp32) | `~/esp-openocd/openocd-esp32/bin/openocd` | ESP32 flash driver, flash breakpoints, `board/esp32s3-builtin.cfg` |

ESP-IDF and the Zephyr SDK each bundle more copies. Seven OpenOCD binaries
ended up on this host. Always call the one you mean by full path.

### RP2350

Stock OpenOCD has no target config for it. Under another config the probe
reports `Could not find MEM-AP to control the core`.

The raspberrypi fork is built and installed on this farm. It has not yet been
used to reset or flash the RP2350 station, so there is no verified command
here. Until then the RP2350 has no SWD reset path and recovers by VBUS cycle or
BOOTSEL. A raw DPIDR sweep (below) does work with stock OpenOCD and tells you
whether the chip has power.

### RP2040

`target/rp2040.cfg` in stock 0.12.0 fails with `Failed to connect multidrop
rp2040.dap0`, even when a DPIDR sweep on the same probe works a second earlier.
Not explained. On this board, use SWD to answer "does it have power", not to
reset it.

### ESP32 with the Espressif fork

Install, no root needed:

```sh
mkdir -p ~/esp-openocd && cd ~/esp-openocd
URL=$(curl -sS https://api.github.com/repos/espressif/openocd-esp32/releases/latest \
      | grep -oE 'https://[^"]*linux-amd64[^"]*\.tar\.gz' | head -1)
curl -sSL -o oocd.tar.gz "$URL" && tar xzf oocd.tar.gz
```

| Capability | Stock 0.12.0 | Espressif fork |
|---|---|---|
| Halt, step, registers, memory | yes | yes |
| Flash over JTAG | no | yes |
| Flash breakpoints beyond the 2 hardware ones | no | yes |
| `board/esp32s3-builtin.cfg` | no | yes |

## ESP32-S3: built-in USB-JTAG

The S3 has a USB-Serial-JTAG controller in the chip. Its own USB cable is the
debugger. It shows up as `303a:1001`.

The catch: the S3 has one USB PHY. When CircuitPython starts TinyUSB, the PHY
switches over and the JTAG device leaves the bus. You get JTAG or a CIRCUITPY
drive, not both
([circuitpython#7992](https://github.com/adafruit/circuitpython/issues/7992)).
A software reset does not give the PHY back. Only a power-on reset does.

So power cycle, then attach inside the boot window:

```sh
uhubctl -l 3-3.3.4 -p 3 -a cycle ; sleep 0.6
~/esp-openocd/openocd-esp32/bin/openocd \
  -s ~/esp-openocd/openocd-esp32/share/openocd/scripts \
  -f board/esp32s3-builtin.cfg
```

Verified result:

```
Info : [esp32s3.cpu0] Target halted, PC=0x4038D426, debug_reason=00000001
Info : Auto-detected flash bank 'esp32s3.cpu1.flash' size 16384 KB
```

Things to know:

- Halting does not drop JTAG. It drops the USB serial console, which needs the
  CPU.
- `cpu1` reporting `Unexpected OCD_ID = 00000000` is normal when the second
  core is parked.
- Two hardware breakpoints per core.
- Do not connect an external J-Link to the S3's header at the same time. It
  corrupted the internal scan and gave a garbage IDCODE.
- External JTAG on the S3 header reads all ones until an eFuse is burned. That
  is irreversible and costs the microSD pins. Not worth it.
- A board sitting at `303a:1001` is not bricked. It means no valid app booted.

## ESP32-S2: no debugger

The S2 has no USB-JTAG. It needs an external JTAG adapter on its 2x5 header,
which has to be soldered on.

What was proven: a J-Link PLUS and a J-Link EDU Mini both reached the TAP
(`0x120034e5`), halted the core and read PC, using OpenOCD's generic `jlink`
driver with `target/esp32s2.cfg`. The board must be in ROM download mode first,
because a running sketch can drive TDO.

What happened next: this board's TAP stopped answering two days later, after a
solder short while building an FT232H adapter. The board still runs normally.
It just has no JTAG. The station now has no debugger.

Its fallback is a CP2102 USB serial cable for the ROM and bootloader console.
The console pins are `GPIO43` and `GPIO44`, which are `board.DEBUG_TX` and
`board.DEBUG_RX`. `board.TX` and `board.RX` are different pins. Open the port
with `--dtr 0 --rts 0`. The notes disagree on whether this cable is still
connected to the board, so check before relying on it.

An FT232H breakout as a JTAG adapter was tried and dropped. Two facts worth
keeping: on the Adafruit breakout the I2C switch ties D1 to D2, which is TDI to
TDO, so turn it off for JTAG. And a TCK to TDO loopback is not a valid self
test.

## Finding out what a probe is connected to

This reads the DPIDR through one probe without knowing the target:

```sh
openocd -c "source [find interface/cmsis-dap.cfg]" \
        -c "adapter serial <SERIAL>" \
        -c "transport select swd" -c "adapter speed 1000" \
        -c "swd newdap c cpu -expected-id 0" \
        -c "dap create c.dap -chain-position c.cpu" \
        -c "init" -c "shutdown"
```

| DPIDR | Meaning |
|---|---|
| `0x0bc11477` | Cortex-M0+ (SAMD21) |
| `0x2ba01477` | Cortex-M4: SAMD51, nRF52840 and STM32F405 all read this |
| `0x0bc12477` | RP2040 |
| `0x4c013477` | RP2350 |
| `0x120034e5` | Xtensa JTAG IDCODE (ESP32 family) |
| silent | unpowered, held by firmware, or not SWD |

To map probes to boards, power one board down and see which probe goes silent.
Do this yourself. Do not trust a written map, including this one. Three serials
in the original notes were stale after probes were swapped.

## Reading JTAG failures

| Scan result | Meaning |
|---|---|
| all ones | Nothing is driving TDO. Open wire, unpowered target, pin reassigned. Ambiguous |
| all zeroes | Something is driving TDO low. Chip in reset, pin used as an output, short to ground, or a connector rotated 180 degrees |

Always get a positive result from a known-good target before you record a
negative one. A full day of "this adapter never works" was measured against a
dead board, and a dead board returns all ones to any adapter.

On a J-Link, `VTarget` near 3.3 V proves contact. It does not prove orientation.

## Faults found at bring-up

None of these were wiring mistakes, and they all looked the same from the host.

- One #2743 breakout was faulty. Swapping it fixed the station.
- Four bad USB cables. The sign: the board has power and answers SWD, but the
  host sees nothing.
- One hub slot. Two different boards failed the same way in it.
