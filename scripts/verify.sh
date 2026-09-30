#!/bin/bash
# Verify every board by USB path: resolve its own volume, read boot_out.txt there,
# and checksum code.py. Never trust a volume label or a successful cp.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF="$HERE/farm-code.py"
RSUM=$(cksum "$REF" | awk '{print $1}')
RLEN=$(stat -c%s "$REF")
echo "reference code.py: cksum $RSUM, $RLEN bytes"
echo
ok=0; bad=0
for s in 3-3.2:RP2040 3-3.3.1:M4-AirLift 3-3.3.2:M0 3-3.3.3:nRF52840 \
         3-3.3.4.1:ESP32-S2 3-3.3.4.2:RP2350 3-3.3.4.3:ESP32-S3 3-3.3.4.4:STM32F405; do
  d=${s%%:*}; nm=${s##*:}
  mp=""
  for b in /sys/bus/usb/devices/$d/*/host*/target*/*/block/*; do
    [ -e "$b" ] || continue
    disk=$(basename "$b")
    mp=$(findmnt -n -o TARGET "/dev/${disk}1" 2>/dev/null | head -1)
    [ -n "$mp" ] && break
  done
  if [ -z "$mp" ]; then
    printf "  %-12s NO VOLUME\n" "$nm"; bad=$((bad+1)); continue
  fi
  ver=$(head -1 "$mp/boot_out.txt" 2>/dev/null)
  csum=$(cksum "$mp/code.py" 2>/dev/null | awk '{print $1}')
  clen=$(stat -c%s "$mp/code.py" 2>/dev/null)
  if [ "$csum" = "$RSUM" ] && [ "$clen" = "$RLEN" ]; then mark="OK"; ok=$((ok+1))
  else mark="CODE.PY MISMATCH"; bad=$((bad+1)); fi
  printf "  %-12s %-4s %-22s %s\n" "$nm" "$mark" "$(basename $mp)" "$ver"
done
echo
echo "  ---- $ok verified, $bad bad ----"
