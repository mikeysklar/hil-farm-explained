#!/bin/bash
# Farm burn test: light, serial, and designed so a clean pass is genuinely clean.
#
# The test set is the intersection of what passed on ALL 8 boards, so the
# expected result is 40/40 everywhere. Any red is a real signal, not the known
# CircuitPython-vs-MicroPython divergence that makes a full basics run noisy.
#
# Serial on purpose: 8-way concurrency on this 4-core host fabricates failures.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd ~/cp-tip/tests || exit 1
OUT=~/burn-results; rm -rf $OUT; mkdir -p $OUT
TESTS=$(tr '\n' ' ' < "$HERE/burnset.txt")
NTESTS=$(wc -l < "$HERE/burnset.txt")

BOARDS="RP2040:3.2:125:143
M4-AirLift:3.3.1:120:135
M0:3.3.2:48:15
nRF52840:3.3.3:64:119
ESP32-S2:3.3.4.1:240:2023
RP2350:3.3.4.2:150:399
ESP32-S3:3.3.4.3:240:8071
STM32F405:3.3.4.4:168:95"

printf "%-12s %-6s %-7s %-9s %8s %10s  %s\n" BOARD BUS REPL BURN HEAP_kB PIDIGITS NOTE
for e in $BOARDS; do
    nm=${e%%:*}; r=${e#*:}; p=${r%%:*}; r2=${r#*:}; N=${r2%%:*}; M=${r2#*:}
    usb="3-${p}"
    bus="down"; [ -e "/sys/bus/usb/devices/$usb" ] && bus="up"
    dev=$(ls /dev/serial/by-path/*usb-0:"$p":1.0 2>/dev/null | head -1)
    if [ -z "$dev" ]; then
        printf "%-12s %-6s %-7s %-9s %8s %10s  %s\n" "$nm" "$bus" "-" "-" "-" "-" "no serial port"
        continue
    fi
    dev=$(readlink -f "$dev")

    # heap, as a cheap liveness + health probe
    heap=$(python3 - "$dev" <<'PY' 2>/dev/null
import sys; import os; sys.path.insert(0, os.path.expanduser("~/cp-tip/tools"))
import pyboard
pyb = pyboard.Pyboard(sys.argv[1], 115200); pyb.enter_raw_repl()
pyb.exec_("import gc"); pyb.exec_("gc.collect()")
print(pyb.exec_("print(gc.mem_free()//1024)").decode().strip())
pyb.exit_raw_repl(); pyb.close()
PY
)
    repl="ok"; [ -z "$heap" ] && { repl="FAIL"; heap="-"; }

    timeout -k 10 900 python3 -u ./run-tests.py -t "$dev" -r "$OUT/res-$nm" \
        $TESTS > "$OUT/$nm.log" 2>&1
    ok=$(grep -oE "^[0-9]+ tests passed" "$OUT/$nm.log" | grep -oE "^[0-9]+")
    bad=$(grep -oE "^[0-9]+ tests failed" "$OUT/$nm.log" | grep -oE "^[0-9]+")
    burn="${ok:-0}/$NTESTS"
    note=""
    [ "${ok:-0}" != "$NTESTS" ] && note="${bad:-?} failed"

    # one benchmark as a performance heartbeat: passed on all 8, tiny variance
    timeout -k 10 300 python3 -u ./run-perfbench.py -t "$dev" -r "$OUT/perf-$nm" \
        "$N" "$M" perf_bench/bm_pidigits.py > "$OUT/perf-$nm.log" 2>&1
    pid=$(grep -oE "^perf_bench/bm_pidigits.py: [0-9.]+ [0-9.]+ [0-9.]+" "$OUT/perf-$nm.log" | awk '{print $4}')

    printf "%-12s %-6s %-7s %-9s %8s %10s  %s\n" \
        "$nm" "$bus" "$repl" "$burn" "$heap" "${pid:--}" "$note"
done
echo
echo "expected: BUS=up REPL=ok BURN=$NTESTS/$NTESTS on every board"
echo "logs in $OUT"
