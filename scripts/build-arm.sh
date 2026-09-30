#!/bin/bash
# Build the six ARM-port farm boards at tip of main, in the clean worktree.
# Logs per board; never touches ~/circuitpython.
set -u
cd ~/cp-tip || exit 1

export PATH=$HOME/arm-toolchain/bin:$HOME/.local/bin:$PATH   # GCC 14 + hexmerge.py
LOG=~/cp-tip-logs
mkdir -p "$LOG"

echo "gcc: $(arm-none-eabi-gcc --version | head -1)"
echo "hexmerge: $(command -v hexmerge.py)"

# port:board
BOARDS="atmel-samd:metro_m0_express
atmel-samd:metro_m4_airlift_lite
raspberrypi:adafruit_metro_rp2040
raspberrypi:adafruit_metro_rp2350
nordic:feather_nrf52840_express
stm:feather_stm32f405_express"

# one submodule fetch per port, not per board
for p in atmel-samd raspberrypi nordic stm; do
    echo "=== fetch-port-submodules: $p ==="
    make -C "ports/$p" fetch-port-submodules >"$LOG/submod-$p.log" 2>&1 \
        && echo "    ok" || echo "    FAILED (see $LOG/submod-$p.log)"
done

for entry in $BOARDS; do
    p=${entry%%:*}; b=${entry##*:}
    echo "=== build $p / $b ==="
    start=$(date +%s)
    if make -C "ports/$p" BOARD="$b" -j4 >"$LOG/build-$b.log" 2>&1; then
        echo "    OK  $(( $(date +%s) - start ))s"
    else
        echo "    FAILED after $(( $(date +%s) - start ))s - tail:"
        tail -15 "$LOG/build-$b.log" | sed 's/^/      /'
    fi
done

echo "=== artifacts ==="
find ports/atmel-samd/build-* ports/raspberrypi/build-* ports/nordic/build-* \
     ports/stm/build-* -maxdepth 1 \( -name "firmware.uf2" -o -name "firmware.bin" \) \
     2>/dev/null | while read -r f; do
    echo "  $(ls -l "$f" | awk '{print $5}')  $f"
done
echo "=== DONE ==="
