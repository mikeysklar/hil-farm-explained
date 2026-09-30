# What the farm found

Four jobs, each of which came back with something that reading the code would
not have shown.

## usb_audio stereo: a device that enumerates and sends nothing

[adafruit/circuitpython#11102](https://github.com/adafruit/circuitpython/pull/11102)
added stereo support to `usb_audio`. All 8 boards built it and flashed it.
Building proved nothing.

On the nRF52840, turning on microphone and speaker together gave a device with
correct descriptors that transferred zero bytes.

| Config | Endpoints | Result |
|---|---|---|
| mic only | `0x88` | works |
| speaker only | `0x08` | works |
| mic + speaker | `0x87`, `0x06` | enumerates, no data |

The nRF52 does isochronous transfer only on endpoint 8. The combined config
fell back to other endpoint numbers. A comment in the source said this could
not be fixed because the chip has "only one ISO-capable endpoint". It is one
endpoint number, not one direction. `0x08` and `0x88` run together. The fix was
two lines and an `if`
([relic-se/circuitpython#2](https://github.com/relic-se/circuitpython/pull/2)).
The PR merged with it.

How it was measured: a different tone in each channel, captured on the host.
96,000 frames at 48 kHz, 1 kHz on the left and 3 kHz on the right. One tone
cannot tell stereo from mono copied twice. Stop the board and check the host
captures silence, then start it and check the tones come back.

## STM32F405: why the bootloader jump is a coin flip

Question: can a Feather STM32F405 get into its bootloader with no button and no
debugger?

| Variant | Reaches DFU |
|---|---|
| Over SWD | every time |
| Stock CircuitPython 10.3.0-rc.0, one attempt | 5 / 12 |
| Firmware retry loop, one user trigger | 12 / 12 |
| Arduino sketch, one 1200-baud touch | 1 / 8 |
| Arduino, host retries the touch | 6 / 6 |

The jump into ST's ROM always works. Halting the core mid-jump showed the
program counter inside the ROM with no fault. Then, more often than not, the
ROM runs for about 1.5 s and resets the chip.

ST's AN2606 has it in the flowchart for this chip: after "USB cable detected",
the next box is "HSE detected", and its "no" branch is "Generate System reset".
The ROM measures the crystal against the internal oscillator, which is only
about 1% accurate, and the note says low crystal frequencies are detected
better. This board has a 12 MHz crystal. The board the original code was tested
on takes 8 MHz.

Nothing in firmware can change a measurement made in mask ROM. So the fix is to
retry. The failure is a clean reset, so retrying is safe.

- [adafruit/circuitpython#11270](https://github.com/adafruit/circuitpython/pull/11270), merged.
- [stm32duino/Arduino_Core_STM32#3063](https://github.com/stm32duino/Arduino_Core_STM32/pull/3063), open.

The first diagnosis was wrong. Two trials showed no DFU and the code was
written off as dead. Twelve trials showed 5 successes. A fix had already been
built for a bug that was not there.

## ulab: a size change that changed integer division

[adafruit/circuitpython#11403](https://github.com/adafruit/circuitpython/pull/11403)
shrinks nearly full builds by switching ulab to function pointers. Tested on
the Metro M4 AirLift.

Speed, microseconds per call, 1024 elements:

| Operation | main | PR | Ratio |
|---|---|---|---|
| add, multiply, compare | same | same | 1.00 |
| float / float | 976 | 1202 | 1.23 |
| float ** float | 4333 | 4583 | 1.06 |
| int16 / int16 | 952 | 1239 | 1.30 |
| uint8 / 2 | 946 | 1232 | 1.31 |

Only divide and power got slower, not float arithmetic in general.

It also changed results on the boards that get the flag:

| Expression | main | PR |
|---|---|---|
| uint8 `[1,2,3] / 2` | `[0.0, 1.0, 1.0]` | `[0.5, 1.0, 1.5]` |
| int16 `[1,-1,0] / 0` | `[0.0, 0.0, 0.0]` | `[inf, -inf, nan]` |

ulab's own tests only divide float arrays, so CI cannot see this.

The benchmark set is in [scripts/ulab_bench](../scripts/ulab_bench). One pass
over all 8 boards takes about a minute. Scores, higher is faster:

| Board | FFT | DOT | INV | VECTOR |
|---|---|---|---|---|
| Metro RP2040 | 10670 | 512967 | 264059 | 43414 |
| Metro M4 AirLift | 116111 | 2506109 | 3632474 | 125512 |
| Metro M0 | no ulab | | | |
| Feather nRF52840 | 77436 | 1546726 | 1268596 | 54697 |
| Metro ESP32-S2 | 32708 | 1476037 | 921902 | 54614 |
| Metro RP2350 | 168339 | 4479754 | 5390282 | 204065 |
| Metro ESP32-S3 | about 200000 | about 5427000 | about 5800000 | 250157 |
| Feather STM32F405 | 199728 | 4048831 | 3355727 | 149770 |

One pass only, so this is not a baseline. The ESP32-S3 row is from reruns. Its
first pass failed three benches because the script arrived corrupted over the
REPL.

## nina-fw: green checks on a dead board

The Metro M4 AirLift running WipperSnapper was reported healthy on the strength
of its board ID, firmware version, credentials and log file. It was rebooting
every 25 s. The serial console showed the co-processor firmware was too old.

The first attempt to upgrade it, through a CircuitPython serial bridge, could
receive but not send, and ended with "hardware fault". An Arduino sketch on the
same pins worked first try. See [wippersnapper.md](wippersnapper.md).

## What the farm cannot do

- Physical changes need a person. When a board was swapped, its debug cable
  left with it, and a working probe was diagnosed as unplugged for a while.
- Some failures pass every static check.
- Eight boards catch family-specific breakage. They do not catch what no test
  measures.
- Build, boot and behave are three different bars. Most of the value is in the
  third, and it only works with a signal you can capture.
