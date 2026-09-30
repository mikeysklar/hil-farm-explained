#!/bin/bash
# 8-board parallel CircuitPython install.
# Timing methodology per docs/flashing.md: the clock starts when code.py is
# written and stops when the last board is back with a mounted CIRCUITPY and a
# valid boot_out.txt. Builds and staging are excluded.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/farm-helpers.sh"
S=~/cp-tip-stage
W=~/wippersnapper
rm -f /tmp/f.*

RUN_T0=$(t)

# code.py first: firmware writes do NOT touch the CIRCUITPY filesystem, so the
# sketch survives the flash and the post-flash copy stays off the critical path.
for v in /media/sklarm/*; do
  [ -f "$v/boot_out.txt" ] && cp "$HERE/farm-code.py" "$v/code.py" 2>/dev/null
done
sync

fin() { echo "$1|$(el $2 $(t))|$3" > /tmp/f.$1; }

# ---- UF2-drive boards ----
uf2board() { # name usb hub port image
  local N=$1 U=$2 H=$3 P=$4 IMG=$5 T0=$(t) BV V
  touch1200 $U
  BV=$(vol_boot $U 30)
  [ -n "$BV" ] || { cycle $H $P; BV=$(vol_boot $U 30); }
  [ -n "$BV" ] && { cp "$IMG" "$BV/" 2>/dev/null; sync; }
  V=$(vol_cp $U 45)
  fin "$N" "$T0" "${V:-NOVOL}"
}
( uf2board rp2040 3-3.2     3-3     2 $S/rp2040.uf2 ) &
( uf2board rp2350 3-3.3.4.2 3-3.3.4 2 $S/rp2350.uf2 ) &

# M0 over SWD, not UF2: the UF2 route failed to enumerate twice running, SWD is
# 2/2. `reset halt` wins the race before CircuitPython claims PA31 (SWDIO).
( T0=$(t)
  openocd -f interface/cmsis-dap.cfg -c "adapter serial E6647C74039F6B2D" -c "transport select swd" \
    -c "gdb_port disabled" -c "tcl_port disabled" -c "telnet_port disabled" \
    -f target/at91samdXX.cfg -c "init" -c "adapter speed 2000" -c "reset halt" \
    -c "flash write_image erase $S/m0_0x2000.bin 0x2000 bin" \
    -c "reset run" -c "shutdown" >/dev/null 2>&1
  V=$(vol_cp 3-3.3.2 18)
  if [ -z "$V" ]; then          # signature failure: flashed fine, USB never came up
    openocd -f interface/cmsis-dap.cfg -c "adapter serial E6647C74039F6B2D" -c "transport select swd" \
      -c "gdb_port disabled" -c "tcl_port disabled" -c "telnet_port disabled" \
      -f target/at91samdXX.cfg -c "adapter speed 400" -c "init; reset run; exit" >/dev/null 2>&1
    V=$(vol_cp 3-3.3.2 30)
  fi
  fin m0 "$T0" "${V:-NOVOL}" ) &

# ---- SWD boards ----
( T0=$(t)
  openocd -f interface/cmsis-dap.cfg -c "adapter serial E6647C740349682C" -c "transport select swd" \
    -c "gdb_port disabled" -c "tcl_port disabled" -c "telnet_port disabled" \
    -f target/atsame5x.cfg -c "adapter speed 500" \
    -c "init" -c "adapter speed 2000" -c "halt" \
    -c "program $S/m4_0x4000.bin 0x4000 reset exit" >/dev/null 2>&1
  V=$(vol_cp 3-3.3.1 45); fin m4 "$T0" "${V:-NOVOL}" ) &
( T0=$(t)
  openocd -f interface/cmsis-dap.cfg -c "adapter serial E6647C74034E732F" -c "transport select swd" \
    -c "adapter speed 4000" -c "gdb_port disabled" -c "tcl_port disabled" -c "telnet_port disabled" \
    -f target/nrf52.cfg -c "init" -c "halt" \
    -c "flash write_image erase $S/nrf_0x26000.bin 0x26000 bin" \
    -c "flash write_image erase $S/nrf_0x27000.bin 0x27000 bin" \
    -c "reset run" -c "shutdown" >/dev/null 2>&1
  V=$(vol_cp 3-3.3.3 45); fin nrf "$T0" "${V:-NOVOL}" ) &
( T0=$(t)
  openocd -c "source [find interface/cmsis-dap.cfg]" -c "adapter serial E6647C740327322C" \
    -c "transport select swd" -c "adapter speed 1000" \
    -c "gdb_port disabled" -c "tcl_port disabled" -c "telnet_port disabled" \
    -f target/stm32f4x.cfg -c "init" -c "reset halt" \
    -c "flash write_image erase $S/stm32.bin 0x08000000 bin" \
    -c "reset run" -c "shutdown" >/dev/null 2>&1
  V=$(vol_cp 3-3.3.4.4 45); fin stm32 "$T0" "${V:-NOVOL}" ) &

# ---- ESP32: tinyuf2 (small) then the CP uf2 on the boot drive ----
espboard() { # name usb chip size blofs tufofs tinydir image
  local N=$1 U=$2 CH=$3 SZ=$4 BL=$5 TU=$6 TD=$7 IMG=$8 T0=$(t) BV V
  touch1200 $U
  poll_any $U "0002 0009 1001" 25
  wait_tty $U 12
  ~/esptool-venv/bin/esptool --chip $CH --port "$(bypath $U)" --baud 921600 \
    --before no-reset --after hard-reset \
    write-flash --flash_mode dio --flash_freq 80m --flash_size $SZ \
    $BL $TD/bootloader.bin 0x8000 $TD/partition-table.bin \
    0xe000 $TD/ota_data_initial.bin $TU $TD/tinyuf2.bin >/dev/null 2>&1
  BV=$(vol_boot $U 30)
  [ -n "$BV" ] && { cp "$IMG" "$BV/" 2>/dev/null; sync; }
  V=$(vol_cp $U 45)
  fin "$N" "$T0" "${V:-NOVOL}"
}
( espboard s2 3-3.3.4.1 esp32s2 4MB  0x1000 0x2d0000 $W/tinyuf2-esp32s2 $S/s2.uf2 ) &
( espboard s3 3-3.3.4.3 esp32s3 16MB 0x0    0x410000 $W/tinyuf2-esp32s3 $S/s3.uf2 ) &
wait

TOTAL=$(el $RUN_T0 $(t))

echo "=== per-board ==="
for f in /tmp/f.*; do
  [ -e "$f" ] || continue
  IFS='|' read -r n s v < "$f"
  printf "  %-7s %7ss  %s\n" "$n" "$s" "$v"
done | sort -k2 -n
echo "=== WALL CLOCK: ${TOTAL}s ==="
