# scripts

These are the scripts that run on the farm host, copied from `~/farm-tools`.
They are not a framework. They are worked examples with one farm's constants
baked in. Read them, then change the constants for your own rig.

The only edits made for this repo: references to sibling files now resolve
relative to the script, instead of `/tmp` and `~/farm-tools`, and each script
has a `FARM-SPECIFIC` comment at the top naming what to change. Temp files and
locks still live in `/tmp`. The edited copies pass `bash -n` but have not been
run on the farm since the edit.

| File | What it does |
|---|---|
| `farm-helpers.sh` | Source this first. `bypath`, `poll_any`, `wait_tty`, `touch1200`, `vol_boot`, `vol_cp`, `cycle`, millisecond timing |
| `farm-up.sh` | Bring-up: power station ports on, wait, SWD reset the two SAMD boards, VBUS cycle whatever is still missing, report |
| `fastcp.sh` | Flash CircuitPython onto all 8 boards at once. 32.9 s measured |
| `verify.sh` | Resolve each board's volume by USB path, read `boot_out.txt`, checksum `code.py` |
| `uf2extract.py` | Split a UF2 into contiguous address runs, one `.bin` per run, for SWD flashing |
| `build-arm.sh`, `build-esp.sh`, `maintip-build.sh` | Build all 8 boards from a clean CircuitPython worktree |
| `burn.sh`, `burnset.txt` | Serial smoke test: 40 basics tests plus one benchmark per board |
| `ulab-burn.sh`, `ulab_bench/` | ulab benchmarks in `tests/perf_bench` format |
| `farm-code.py` | The idle sketch every board runs as `code.py` |
| `50-udisks-ssh.rules` | polkit rule that lets an SSH session mount drives. See [docs/setup.md](../docs/setup.md) |

## Constants you must change

| Constant | Where | This farm |
|---|---|---|
| USB paths of the stations | every script | `3-3.2`, `3-3.3.1` ... `3-3.3.4.4` |
| Hub location and port per station | `farm-up.sh`, `fastcp.sh` | `3-3:2`, `3-3.3:1` ... |
| Uplink ports that must never be switched | `farm-up.sh` comment | `3-3` p3, `3-3.3` p4, `3-3` p4 |
| Probe serial numbers | `farm-up.sh`, `fastcp.sh` | `E6647C74...`, one per ARM board |
| Image stage directory | `fastcp.sh` | `~/cp-tip-stage` |
| tinyuf2 bootloader directories | `fastcp.sh` | `~/wippersnapper/tinyuf2-esp32s2`, `-esp32s3` |
| CircuitPython worktree | build and burn scripts | `~/cp-tip` |
| Toolchain paths | `build-arm.sh` | `~/arm-toolchain/bin`, `~/.local/bin` |
| esptool | `fastcp.sh` | `~/esptool-venv/bin/esptool` |
| Mount root | `fastcp.sh` | `/media/sklarm/` |
| CPU MHz and heap kB per board | `burn.sh`, `ulab-burn.sh` | the `BOARDS` table |
| User name | `50-udisks-ssh.rules` | `sklarm` |

## What `fastcp.sh` expects in the stage directory

```
rp2040.uf2  rp2350.uf2  s2.uf2  s3.uf2      UF2 images
m0_0x2000.bin                               SAMD21 app, from uf2extract.py
m4_0x4000.bin                               SAMD51 app
nrf_0x26000.bin  nrf_0x27000.bin            nRF52840, two runs, the image has a gap
stm32.bin                                   written at 0x08000000
```

Make the `.bin` files with `uf2extract.py firmware.uf2 prefix` on every new
build. Do not reuse offsets from a previous release without checking.

## Known gaps

- `farm-up.sh` runs SWD reset, then VBUS cycle, then reports. A board that needs
  a second SWD reset after the cycle is reported DOWN. Run the SWD reset again
  by hand.
- There is no WipperSnapper script. The steps are snippets in
  [docs/wippersnapper.md](../docs/wippersnapper.md).
- `burn.sh` and `ulab-burn.sh` run boards one at a time on purpose. Eight
  parallel test runs on a 4-core host produced failures that were not real.
