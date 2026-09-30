# shared primitives - source this
# FARM-SPECIFIC: nothing here is hardcoded to one farm, but bypath assumes one
# USB host controller (it matches any by-path entry ending in the port chain).
t() { date +%s%3N; }
el() { awk "BEGIN{printf \"%.1f\", ($2-$1)/1000}"; }
bypath() { ls /dev/serial/by-path/*usb-0:${1#*-}:1.0 2>/dev/null | head -1; }
poll_any() { local end=$((SECONDS+${3:-40})) cur
  while [ $SECONDS -lt $end ]; do
    cur=$(cat /sys/bus/usb/devices/$1/idProduct 2>/dev/null)
    for w in $2; do [ "$cur" = "$w" ] && return 0; done
    sleep 0.2
  done; return 1; }
wait_tty() { local end=$((SECONDS+${2:-15})) d
  while [ $SECONDS -lt $end ]; do
    d=$(bypath $1); [ -n "$d" ] && [ -e "$d" ] && return 0; sleep 0.2
  done; return 1; }
touch1200() { local d=$(bypath $1); [ -n "$d" ] || return 1
  python3 -c "import serial,time;s=serial.Serial('$d',1200);time.sleep(0.25);s.close()" 2>/dev/null; return 0; }
# any mounted volume under this USB path matching a marker file.
# udisks automounts via the polkit rule, so poll cheap filesystem checks and only
# fall back to udisksctl occasionally, serialised - 8 concurrent loops hammering
# the udisks D-Bus daemon was the single biggest source of contention.
_vol() { local usb=$1 marker=$2 anti=$3 end=$((SECONDS+${4:-40})) disk dev mp tries=0 settled=0
  while [ $SECONDS -lt $end ]; do
    for b in /sys/bus/usb/devices/$usb/*/host*/target*/*/block/*; do
      [ -e "$b" ] || continue; disk=$(basename "$b")
      for dev in "${disk}1" "$disk"; do
        [ -b "/dev/$dev" ] || continue
        [ "$(lsblk -bno SIZE /dev/$dev 2>/dev/null|head -1)" -gt 0 ] 2>/dev/null || continue
        mp=$(findmnt -n -o TARGET "/dev/$dev" 2>/dev/null|head -1)      # cheap, no D-Bus
        if [ -z "$mp" ]; then
          [ $settled -eq 0 ] && { udevadm settle --timeout=2 >/dev/null 2>&1; settled=1; }
          if [ $tries -lt 6 ]; then                                      # bounded, serialised
            flock -w 8 /tmp/udisks.lock udisksctl mount -b "/dev/$dev" >/dev/null 2>&1
            tries=$((tries+1))
            mp=$(findmnt -n -o TARGET "/dev/$dev" 2>/dev/null|head -1)
          fi
        fi
        [ -n "$mp" ] || continue
        if [ -f "$mp/$marker" ]; then
          if [ -n "$anti" ] && [ -f "$mp/$anti" ]; then :; else echo "$mp"; return 0; fi
        fi
      done
    done
    sleep 0.3
  done; return 1; }
vol_boot() { _vol "$1" INFO_UF2.TXT boot_out.txt "${2:-40}"; }   # a UF2 bootloader drive
vol_cp()   { _vol "$1" boot_out.txt "" "${2:-40}"; }             # a running CIRCUITPY
cycle() { flock /tmp/uhubctl.lock -c "uhubctl -S -l $1 -p $2 -a off -r 20 -w 250 >/dev/null 2>&1; uhubctl -S -l $1 -p $2 -a on >/dev/null 2>&1"; }
