#!/bin/bash
# FARM-SPECIFIC, change for your rig: PROBE_M4 and PROBE_M0 serials, STATIONS,
# BOARDS and PORTS (USB paths and hub:port pairs), and the uplink ports named below.
# Bring the HIL farm up. Counterpart to the shutdown in docs/recovery.md.
# Safe to re-run: powering an already-on port is a no-op.
#
# Order matters and is mostly automatic: the six Pi Debug Probes hang off a
# Terminus 7-port hub with no per-port power switching, so they are always
# energised before any board. That is by design - a debugger should outlive the
# board it is debugging.

set -u
PROBE_M4=E6647C740349682C     # Metro M4 AirLift  (atsame5x)
PROBE_M0=E6647C74039F6B2D     # Metro M0 Express  (at91samdXX)
Q='-c gdb_port\ disabled -c tcl_port\ disabled -c telnet_port\ disabled'

# station ports only. NEVER touch 3-3 p3 (uplink to 3-3.3), 3-3.3 p4 (uplink to
# 3-3.3.4) or 3-3 p4 (the Terminus probe hub).
STATIONS="3-3:1 3-3:2 3-3.3:1 3-3.3:2 3-3.3:3 3-3.3.4:1 3-3.3.4:2 3-3.3.4:3 3-3.3.4:4"

BOARDS="3-3.2:RP2040 3-3.3.1:M4-AirLift 3-3.3.2:M0 3-3.3.3:nRF52840
        3-3.3.4.1:ESP32-S2 3-3.3.4.2:RP2350 3-3.3.4.3:ESP32-S3 3-3.3.4.4:STM32F405"

# device path -> the hub:port that feeds it, for the VBUS-cycle fallback below.
PORTS="3-3.2:3-3:2 3-3.3.1:3-3.3:1 3-3.3.2:3-3.3:2 3-3.3.3:3-3.3:3
       3-3.3.4.1:3-3.3.4:1 3-3.3.4.2:3-3.3.4:2 3-3.3.4.3:3-3.3.4:3 3-3.3.4.4:3-3.3.4:4"

up_count() { local n=0 s
  for s in $BOARDS; do
    [ -n "$(cat /sys/bus/usb/devices/${s%%:*}/idProduct 2>/dev/null)" ] && n=$((n+1))
  done; echo $n; }

swd_reset() {  # probe, target cfg, speed
  openocd -f interface/cmsis-dap.cfg -c "adapter serial $1" -c "transport select swd" \
    -c "gdb_port disabled" -c "tcl_port disabled" -c "telnet_port disabled" \
    -f "target/$2" -c "adapter speed $3" -c "init; reset run; exit" >/dev/null 2>&1
}

echo "== powering station ports on =="
for s in $STATIONS; do
  uhubctl -S -l "${s%%:*}" -p "${s##*:}" -a on >/dev/null 2>&1
done

echo "== waiting for enumeration =="
for i in $(seq 1 30); do
  sleep 2
  n=$(up_count); [ "$n" -ge 8 ] && break
done
echo "   $n/8 up after $((i*2))s"

# The two SAMD boards routinely do not re-enumerate after a VBUS cut: the port
# reads "0100 power" with no connect while SWD still sees a running core.
# Cutting VBUS does not reliably reset a SAMD. Three for three across sessions.
if [ -z "$(cat /sys/bus/usb/devices/3-3.3.1/idProduct 2>/dev/null)" ]; then
  echo "== M4 AirLift did not enumerate, SWD reset =="
  swd_reset "$PROBE_M4" atsame5x.cfg 500
fi
if [ -z "$(cat /sys/bus/usb/devices/3-3.3.2/idProduct 2>/dev/null)" ]; then
  echo "== M0 did not enumerate, SWD reset =="
  swd_reset "$PROBE_M0" at91samdXX.cfg 400
fi
sleep 12

# Anything still absent gets a VBUS cycle. A port left at "0100 power" with no
# connect is not necessarily unpowered - the Metro RP2040 on 2026-08-22 was
# powered and answering SWD (DPIDR 0x0bc12477) while off the bus, so "-a on" was
# a no-op and only an off/on brought it back. This is the opposite of the SAMD
# case above, where a cycle does nothing and SWD is the fix, so do both in order.
cycled=0
for m in $PORTS; do
  d=${m%%:*}; rest=${m#*:}; hub=${rest%:*}; port=${rest##*:}
  [ -n "$(cat /sys/bus/usb/devices/$d/idProduct 2>/dev/null)" ] && continue
  echo "== $d still down, VBUS cycle $hub p$port =="
  uhubctl -S -l "$hub" -p "$port" -a off -r 30 -w 400 >/dev/null 2>&1
  sleep 5
  uhubctl -S -l "$hub" -p "$port" -a on >/dev/null 2>&1
  cycled=1
done
[ "$cycled" = 1 ] && sleep 20

echo "== final state =="
for s in $BOARDS; do
  d=${s%%:*}; nm=${s##*:}
  printf "   %-12s %-10s %s\n" "$nm" \
    "$(cat /sys/bus/usb/devices/$d/idProduct 2>/dev/null || echo DOWN)" \
    "$(cat /sys/bus/usb/devices/$d/product 2>/dev/null)"
done
# Terminus probes (3-3.4.*) and the dev-hub probe on 3-6.1 are counted apart -
# lumping them together used to print a confusing "probes 7/6".
nt=$(ls -d /sys/bus/usb/devices/3-3.4.* 2>/dev/null | while read -r d; do
       [ "$(cat $d/idVendor 2>/dev/null)" = "2e8a" ] && echo x; done | wc -l)
nd=$(for d in /sys/bus/usb/devices/*; do [ "$(cat $d/idVendor 2>/dev/null)" = "2e8a" ] && echo x; done | wc -l)
echo "   ---- boards $(up_count)/8, probes $nt/6 on the Terminus, $nd total ----"
