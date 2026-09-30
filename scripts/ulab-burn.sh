#!/bin/bash
# Farm ulab burn: the four ulab_bench benches on every board, serially.
# A sibling of burn.sh, not an addition to it. Same board table, same N/M.
#
# Output per board is the score (column 3 of run-perfbench, 1e6*norm/us)
# for each bench. "-" is SKIP (the M0 has no ulab and M=15 is below every
# param row), FAIL is a wrong answer or a crash; see the log.
#
# Serial on purpose: parallel runs on this 4-core host fabricate failures.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd ~/cp-tip/tests || exit 1
BENCH="$HERE/ulab_bench"
AVG=${AVG:-4}                         # run-perfbench -a; 8 is the harness default
OUT=~/ulab-burn-results; rm -rf $OUT; mkdir -p $OUT

# name:hub-port:MHz:heap_kB:board_id
BOARDS="RP2040:3.2:125:143:adafruit_metro_rp2040
M4-AirLift:3.3.1:120:135:metro_m4_airlift_lite
M0:3.3.2:48:15:metro_m0_express
nRF52840:3.3.3:64:119:feather_nrf52840_express
ESP32-S2:3.3.4.1:240:2023:adafruit_metro_esp32s2
RP2350:3.3.4.2:150:399:adafruit_metro_rp2350
ESP32-S3:3.3.4.3:240:8071:adafruit_metro_esp32s3
STM32F405:3.3.4.4:168:95:feather_stm32f405_express"

score() {  # $1 log, $2 bench name -> score, "-" for skip, FAIL otherwise
    local l; l=$(grep -E "/$2\.py: " "$1" | head -1)
    case "$l" in
        *": SKIP"*) echo "-" ;;
        *": "[0-9]*) echo "$l" | awk '{printf "%.0f", $4}' ;;
        *) echo "FAIL" ;;
    esac
}

printf "%-12s %-6s %-7s %9s %9s %9s %9s  %s\n" BOARD BUS REPL FFT DOT INV VECTOR NOTE
for e in $BOARDS; do
    IFS=: read -r nm p N M want <<< "$e"
    usb="3-${p}"
    bus="down"; [ -e "/sys/bus/usb/devices/$usb" ] && bus="up"
    dev=$(ls /dev/serial/by-path/*usb-0:"$p":1.0 2>/dev/null | head -1)
    if [ -z "$dev" ]; then
        printf "%-12s %-6s %-7s %9s %9s %9s %9s  %s\n" "$nm" "$bus" "-" - - - - "no serial port"
        continue
    fi
    dev=$(readlink -f "$dev")

    # identity gate: resolve by path, confirm by board_id, never trust the tty number
    id=$(timeout 30 python3 - "$dev" <<'PY' 2>/dev/null
import sys; import os; sys.path.insert(0, os.path.expanduser("~/cp-tip/tools"))
import pyboard
pyb = pyboard.Pyboard(sys.argv[1], 115200); pyb.enter_raw_repl()
print(pyb.exec_("import board; print(board.board_id)").decode().strip())
pyb.exit_raw_repl(); pyb.close()
PY
)
    if [ -z "$id" ]; then
        printf "%-12s %-6s %-7s %9s %9s %9s %9s  %s\n" "$nm" "$bus" "FAIL" - - - - "no REPL"
        continue
    fi
    if [ "$id" != "$want" ]; then
        printf "%-12s %-6s %-7s %9s %9s %9s %9s  %s\n" "$nm" "$bus" "ok" - - - - "WRONG BOARD: $id on $usb"
        continue
    fi

    timeout -k 10 600 python3 -u ./run-perfbench.py -t "$dev" -a "$AVG" "$N" "$M" \
        $BENCH/bm_ulab_*.py > "$OUT/$nm.log" 2>&1
    fft=$(score "$OUT/$nm.log" bm_ulab_fft)
    dot=$(score "$OUT/$nm.log" bm_ulab_dot)
    inv=$(score "$OUT/$nm.log" bm_ulab_inv)
    vec=$(score "$OUT/$nm.log" bm_ulab_vector)
    note=""
    [ "$fft$dot$inv$vec" = "----" ] && note="all SKIP (no ulab or M too small)"
    case "$fft$dot$inv$vec" in *FAIL*) note="see $OUT/$nm.log" ;; esac

    printf "%-12s %-6s %-7s %9s %9s %9s %9s  %s\n" "$nm" "$bus" "ok" "$fft" "$dot" "$inv" "$vec" "$note"
done
echo
echo "score = 1e6 * norm / us, higher is faster; -a $AVG averages per bench. logs in $OUT"
