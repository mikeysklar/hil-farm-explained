# WipperSnapper

[WipperSnapper](https://github.com/adafruit/Adafruit_Wippersnapper_Arduino) is
Arduino-based firmware that replaces CircuitPython on the board. Four of the
eight stations have a build.

| Board | Build used | Notes |
|---|---|---|
| Metro ESP32-S2 | `1.0.0-beta.131` | UF2 via tinyuf2 |
| Metro ESP32-S3 | `1.0.0-beta.131` | UF2 via tinyuf2 |
| Metro M4 AirLift Lite | `1.0.0-beta.131` | SWD. Needs nina-fw 1.7.7 or newer, see below. The timings here were taken on `beta.85`, before that upgrade |
| Metro RP2350 | `1.0.0-offline-beta.5` | Offline only, logs to SD |
| M0, RP2040, nRF52840, STM32F405 | none | No build ships for these |

Do not flash the AirLift UF2 onto a plain Metro M4 Express. Pins 36, 37 and 38
differ, so it drives A0, A1 and AREF as ESP32 control lines.

## Timings

Four boards in parallel, release binaries, seconds per stage.

| Stage | ESP32-S2 | ESP32-S3 | M4 AirLift | RP2350 |
|---|---|---|---|---|
| Bootloader entry | 1.3 | 1.3 | none | 5.6 |
| Bootloader flash | 3.3 | 2.5 | none | none |
| Firmware flash | 8.4 | 8.9 | 16.2 | 8.3 |
| First boot | 1.8 | 0.7 | 4.3 | 2.7 |
| Write `secrets.json` | 0.4 | 0.3 | 0.4 | 0.4 |
| Verify | 28.3 | 28.7 | 22.2 | 35.7 |
| **Total** | **43.7** | **43.8** | **43.2** | **52.7** |

Wall clock for all four: **80.7 s**. The first attempt took 130.7 s.

Flashing itself is 14 to 21 s per board. The verify stage is about 11 s of
power-cycle dwell, then the board joining WiFi and registering with Adafruit
IO. The RP2350 build is offline and is checked from its log file instead.

| Phase | S2 | S3 |
|---|---|---|
| Boot and WiFi scan | 6.5 | 6.5 |
| WiFi association | 5.6 | 5.6 |
| MQTT connect | 2.2 | 2.7 |
| Registration | 0.8 | 1.0 |
| First PING | 1.7 | 1.7 |
| **Power-on to PING** | **16.8** | **17.5** |

What each fix was worth:

| Board | First run | Final | Fix |
|---|---|---|---|
| ESP32-S2 | 65 | 43.7 | Wait for the tty before calling esptool |
| ESP32-S3 | 68 | 43.8 | Poll all PIDs in one loop: entry 30.3 s to 2.0 s |
| M4 AirLift | 70 | 43.2 | Console read that reconnects |
| RP2350 | 60 | 52.7 | Boot-volume check |

## Steps

| Stage | ESP32-S2 / S3 | M4 AirLift | RP2350 |
|---|---|---|---|
| Enter bootloader | 1200-baud touch | not needed | 1200-baud touch |
| Install bootloader | `esptool` writes tinyuf2 | not needed | not needed |
| Copy image | `cp` to `METROS2BOOT` / `METROS3BOOT` | `openocd program ... 0x4000` | `cp` to `RP2350` |
| Reset | `uhubctl` cycle under a lock | `openocd init; reset run` | `uhubctl` cycle under a lock |
| Credentials | `secrets.json` on the volume | same | same |
| Verify | console: `MQTT PING: SUCCESS` | console: `Registration and configuration complete` | `wipper_boot_out.txt` clean |

The ESP32 and RP2350 steps are the same as in [flashing.md](flashing.md) with
the WipperSnapper `.uf2` in place of CircuitPython. Use `vol_boot` with a check
that `wipper_boot_out.txt` is absent.

M4 AirLift, one command:

```sh
openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" -f target/atsame5x.cfg -c "adapter speed 500" \
  -c "program m4_wipper_0x4000.bin 0x4000 verify reset exit"
```

Run the four as plain shell jobs:

```sh
( flash_s2 ) > /tmp/r.s2 2>&1 &
( flash_s3 ) > /tmp/r.s3 2>&1 &
( flash_rp ) > /tmp/r.rp 2>&1 &
( flash_m4 ) > /tmp/r.m4 2>&1 &
wait
```

## secrets.json

```json
{
  "io_username": "YOUR_IO_USERNAME",
  "io_key": "YOUR_IO_KEY",
  "network_type_wifi": {
    "network_ssid": "YOUR_SSID",
    "network_password": "YOUR_PASS"
  },
  "status_pixel_brightness": 0.5
}
```

Write it after first boot, never before. Installing over CircuitPython
reformats the volume and wipes anything staged early. Check the board ID right
before the write:

```python
assert bid in open(v + "/wipper_boot_out.txt").read(), "WRONG BOARD"
```

A WipperSnapper over WipperSnapper reflash does not reformat. So a missing
`Please edit the secrets.json file` line proves nothing.

Keep the key out of shell history and out of any log an LLM can read.

## Verify on the console

Only the serial console proves a cloud board is up. Open the port in a loop
that survives the board resetting:

```python
while time.time() < deadline:
    if s is None:
        try: s = serial.Serial(dev, 115200, timeout=0.5)
        except Exception: time.sleep(0.5); continue
    try: l = s.readline().decode("utf-8", "replace").strip()
    except Exception: s = None; continue
    if l and pat.search(l): print(l); sys.exit(0)
```

Allow 90 s for first registration. A 40 s window reports a healthy board as
failed.

## The M4 AirLift and nina-fw

WipperSnapper `beta.131` needs nina-fw 1.7.7 or newer on the AirLift's ESP32
co-processor. This board shipped with 1.7.5. It refused to associate and the
watchdog rebooted it every 25 s.

Every static check was green the whole time: board ID, firmware version,
`secrets.json`, no ERROR in `wipper_boot_out.txt`, correct USB ID. Only the
console showed the loop.

Upgrade to `NINA_ADAFRUIT-esp32-3.3.0.bin` from
[adafruit/nina-fw](https://github.com/adafruit/nina-fw/releases). The version
check is numeric, so 3.x passes. The `fruitjam_c6` file is for a different chip.

### Recipe

Put a serial passthrough on the SAMD51, then run esptool through it. About
3 minutes.

```cpp
unsigned long baud = 115200;
void setup() {
  Serial.begin(baud);
  SerialNina.begin(baud);
  pinMode(NINA_GPIO0, OUTPUT);
  pinMode(NINA_RESETN, OUTPUT);
  digitalWrite(NINA_GPIO0, LOW);      // GPIO0 low = ROM download mode
  digitalWrite(NINA_RESETN, LOW);
  delay(100);
  digitalWrite(NINA_RESETN, HIGH);    // release reset with GPIO0 still low
  delay(100);
}
void loop() {
  if (Serial.baud() != baud) {        // follow the host when esptool raises baud
    baud = Serial.baud();
    SerialNina.begin(baud);
  }
  while (Serial.available())     SerialNina.write(Serial.read());
  while (SerialNina.available()) Serial.write(SerialNina.read());
}
```

```sh
# 1. build. No library needed, the names come from the variant header.
arduino-cli compile --fqbn adafruit:samd:adafruit_metro_m4_airliftlite \
  --output-dir ./build SerialNINAPassthrough

# 2. flash over SWD at the SAMD51 app base
openocd -f interface/cmsis-dap.cfg -c "adapter serial $PROBE" \
  -c "transport select swd" -f target/atsame5x.cfg -c "adapter speed 500" \
  -c "program build/SerialNINAPassthrough.ino.bin 0x4000 verify reset exit"

# 3. check the bridge first. A working one uploads a stub and reports flash size.
esptool --chip esp32 --port "$(bypath 3-3.3.1)" --baud 115200 \
  --before no-reset --after no-reset flash-id

# 4. write nina-fw
esptool --chip esp32 --port "$(bypath 3-3.3.1)" --baud 115200 \
  --before no-reset --after no-reset write-flash 0x0 NINA_ADAFRUIT-esp32-3.3.0.bin

# 5. put WipperSnapper back over SWD, write secrets.json after first boot
```

Use the Arduino sketch, not a CircuitPython bridge. A CircuitPython `busio.UART`
on `board.ESP_TX` and `board.ESP_RX` received the ESP32 banner but never
transmitted: 1610 bytes host to ESP, 0 back. That produced a wrong "hardware
fault" verdict. The Arduino sketch drove the same pin and worked first try.

nina-fw 1.7.x also reports the MAC byte-reversed. 3.3.0 matches what esptool
reads.

## RP2350 offline build

The offline build drops off the USB bus about every 18 s on its own. Give
volume lookups a budget longer than that. The MAC reads `00:00:00:00:00:00` by
design and there is no MQTT to check. Not investigated further.
