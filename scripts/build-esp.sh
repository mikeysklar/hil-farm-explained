#!/bin/bash
# Build the two espressif farm boards at tip of main in the clean worktree.
set -u
cd ~/cp-tip || exit 1
LOG=~/cp-tip-logs
mkdir -p "$LOG"

source ports/espressif/esp-idf/export.sh >/dev/null 2>&1 || { echo "export.sh failed"; exit 1; }
echo "IDF: $(idf.py --version 2>&1 | head -1)"

for b in adafruit_metro_esp32s2 adafruit_metro_esp32s3; do
    echo "=== build espressif / $b ==="
    start=$(date +%s)
    if make -C ports/espressif BOARD="$b" -j4 >"$LOG/build-$b.log" 2>&1; then
        echo "    OK  $(( $(date +%s) - start ))s"
    else
        echo "    FAILED after $(( $(date +%s) - start ))s - tail:"
        tail -20 "$LOG/build-$b.log" | sed 's/^/      /'
    fi
done

echo "=== artifacts ==="
for b in adafruit_metro_esp32s2 adafruit_metro_esp32s3; do
    d=ports/espressif/build-$b
    for f in firmware.uf2 firmware.bin; do
        [ -f "$d/$f" ] && echo "  $(stat -c%s "$d/$f")  $d/$f"
    done
done
echo "=== DONE ==="
