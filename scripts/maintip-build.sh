#!/bin/bash
# All 8 farm boards at pure tip of main, no local modifications.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd ~/cp-tip || exit 1
echo "### $(git log --oneline -1)  branch=$(git branch --show-current)"
echo "### diff vs origin/main: $(git diff origin/main --stat | wc -l) lines (0 = pure main)"
rm -rf ports/atmel-samd/build-* ports/raspberrypi/build-* ports/nordic/build-* \
       ports/stm/build-* ports/espressif/build-adafruit_metro_esp32s*
echo "### cleaned, starting $(date -Is)"
bash "$HERE/build-arm.sh"
echo
bash "$HERE/build-esp.sh"
echo "### finished $(date -Is)"
echo "### ALLDONE"
