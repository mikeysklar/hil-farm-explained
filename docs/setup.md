# Setup

What to buy, and what to install on the host.

## Bill of materials

| Qty | Item | Notes |
|---|---|---|
| 8 | Boards, one per MCU family you care about | Coverage beats count. This farm: 6 Metros, 2 Feathers |
| 6 | [Raspberry Pi Debug Probe](https://www.adafruit.com/product/5699) | One per ARM board. CMSIS-DAP, SWD only |
| 4 | [SWD 2x5 1.27 mm breakout, #2743](https://www.adafruit.com/product/2743) | For boards with a 2x5 header |
| 4 | [2x5 1.27 mm IDC cable, #1675](https://www.adafruit.com/product/1675) | Board header to breakout |
| 4 | 0.1" right-angle header, 3 pins | Soldered to the breakout: SWCLK, SWDIO, GND |
| 1 | Powered USB hub with real per-port power switching | For the boards. See below |
| 1 | Any powered USB hub | For the probes. Should not be switchable |
| 1 | IKEA SKÅDIS pegboard, 56 x 56 cm | See [mounting.md](mounting.md) |
| 1 | [M2.5 nylon screw and standoff set, #3299](https://www.adafruit.com/product/3299) | Non-conductive |
| 1 | Linux host | Ubuntu 24.04, 4 cores here |
| 14 | Short USB cables | Bad cables were the most common fault during bring-up |

The two ESP32 boards need no probe. See [debug.md](debug.md).

## The hub

The whole farm depends on one thing: the hub must cut VBUS to a single port
when asked. Test this before building anything.

```sh
uhubctl                     # the hub line must say "ppps", not "ganged"
```

`ppps` is only what the hub claims. Some hubs update the status bit and leave
the power on. The real test is that a device comes back with a new device
number:

```sh
P=3-3.3.4.1                               # a board's USB path
cat /sys/bus/usb/devices/$P/devnum        # note it
uhubctl -l 3-3.3.4 -p 1 -a off -r 30 -w 400
ls /sys/bus/usb/devices/$P 2>/dev/null    # must be gone
uhubctl -l 3-3.3.4 -p 1 -a on ; sleep 10
cat /sys/bus/usb/devices/$P/devnum        # must be higher
```

Same number means the hub only dropped the data lines. That hub is no use here.

Two things that apply to any hub:

- A USB 3 hub shows up twice, once on a USB 2 bus and once on a USB 3 bus.
  Only ever pass the USB 2 location to `uhubctl`.
- A cascaded hub spends one port per tier on the uplink to the next tier.
  Find those ports and never switch them. Cutting one drops every board below
  it and looks like a successful power-off.

Put the probes on a separate hub that stays on. A debugger should outlive the
board it is debugging.

## uhubctl without sudo

A test runner cannot type a password. Give your user access to the hub by
vendor ID:

```
# /etc/udev/rules.d/52-uhubctl.rules
SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", MODE="0664", GROUP="plugdev"
```

```sh
sudo udevadm control --reload && sudo udevadm trigger --attr-match=subsystem=usb
```

Change `0bda` to your hub's vendor. Your user must be in `plugdev`.

Never run `sudo -n uhubctl` from a script. When sudo wants a password both
halves fail silently with rc=1, the port is never cut, and it looks like a
board that refuses to reset.

## Mounting drives over SSH

`udisksctl mount` fails over SSH with `NotAuthorizedCanObtain`. An SSH session
has no seat, so udisks2 checks `filesystem-mount-other-seat`, not
`filesystem-mount`. A rule that grants only the second one looks right and
mounts nothing.

Test it without touching a board:

```sh
pkcheck --action-id org.freedesktop.udisks2.filesystem-mount-other-seat \
        --process $$ && echo AUTHORIZED
```

The working rule is [scripts/50-udisks-ssh.rules](../scripts/50-udisks-ssh.rules).
It grants the whole `org.freedesktop.udisks2.` prefix to one user.

```sh
sudo install -m 644 -o root -g root scripts/50-udisks-ssh.rules \
    /etc/polkit-1/rules.d/50-udisks-ssh.rules
sudo systemctl restart polkit
```

You cannot check the rule with `ls`. `/etc/polkit-1/rules.d` is mode 0750, so
`ls` says permission denied whether the file is there or not. Use `pkcheck`.

Without this rule, UF2 drives only mount while a desktop session is logged in.
When you cannot mount, check boards over the serial REPL instead. See
[recovery.md](recovery.md).

## Toolchains

| Need | Where on this farm | Trap |
|---|---|---|
| ARM GCC 14 or newer | `~/arm-toolchain/bin` | GCC 13 fails with a pragma error, not a version message |
| `hexmerge.py` | `~/.local/bin` | Without it the nordic build fails at `firmware.combined.hex`, after it already wrote a good `.uf2` |
| ESP-IDF | `source ports/espressif/esp-idf/export.sh` | |
| esptool v5 | `~/esptool-venv/bin/esptool` | v5 syntax is `write-flash`, not `write_flash` |
| arduino-cli 1.5.1 | `~/bin/arduino-cli` | The `/releases/latest/download/` URL 404s. The asset name carries the version |
| pyserial | system python | Used for the 1200-baud touch and the REPL |
| dfu-util | system | For the STM32 ROM bootloader |
| OpenOCD, three builds | see [debug.md](debug.md) | Stock 0.12.0 has no `rp2350.cfg` and cannot flash ESP32 |

```sh
export PATH=$HOME/arm-toolchain/bin:$HOME/.local/bin:$PATH
```

## Building CircuitPython

Build in a git worktree, not your working tree:

```sh
cd ~/circuitpython
git fetch origin main
git worktree add -b farm-tip-$(date +%F) ~/cp-tip origin/main
```

Then [scripts/maintip-build.sh](../scripts/maintip-build.sh).

- Do not fetch submodules while a build is running. It flipped one board's
  version string to `-dirty` off a clean commit.
- Changing a feature flag needs `rm -rf` of the build directory. Otherwise you
  get `MP_QSTR_... undeclared` errors that point nowhere useful.
- Read the firmware version from `boot_out.txt` on the board. Do not run
  `strings` on a binary. On ESP32 that finds the ESP-IDF version instead.
