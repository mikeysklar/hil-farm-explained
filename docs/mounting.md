# Mounting

Everything hangs on one IKEA SKÅDIS pegboard, 56 x 56 cm. The slots are
5 x 15 mm on a 40 mm grid and the panel is 5 mm thick.

<!-- photo: whole farm on the wall -->

## Layout

Boards mount flat, facing out. Standing them on edge like books would fit more,
but flat means every LED, button and connector can be seen and reached. Each
board idles with its NeoPixel breathing in its own colour, so you can tell the
stations apart from across the room.

## Parts

| Part | Source | Files here |
|---|---|---|
| PCB rail, Metro, with inserts, rear mount | this repo | [`skadis-pcb-rail-metro-inserts-rear-mount.3mf`](../cad/skadis-pcb-rail-metro-inserts-rear-mount.3mf) |
| PCB rail, Feather, left and right | this repo | [`left`](../cad/skadis-pcb-rail-feather-left-inserts.3mf), [`right`](../cad/skadis-pcb-rail-feather-right-inserts.3mf) |
| PCB rail, no inserts | this repo | [`skadis-pcb-rail-no-inserts.3mf`](../cad/skadis-pcb-rail-no-inserts.3mf) |
| FreeCAD source for the rails | this repo | [`skadis-pcb-rail.fcstd`](../cad/skadis-pcb-rail.fcstd) |
| T-nuts, M2.5 | [Printables #228663](https://www.printables.com/model/228663-skadis-t-nuts-mounting-system-for-ikea-skadis-pegb) | not included, get them from the author |
| Parametric hook | [Printables #1450485](https://www.printables.com/model/1450485-ikea-skadis-parametric-hook-freecad-file/files) | not included, get it from the author |
| M2.5 nylon screws and standoffs | [Adafruit #3299](https://www.adafruit.com/product/3299) | |

<!-- photo: rail close-up with a Metro on it -->

## Boards

A Metro uses the Uno hole pattern with 3.2 mm holes. A Feather has 2.5 mm
holes. The T-nut is a quarter-turn part that locks behind the panel as the
screw tightens. Print the M2.5 version. It fits the #3299 nylon standoffs.

Nylon hardware cannot short anything on the back of a board.

## Hubs, probes and everything else

The hubs, debug probes and other boxes hang from the parametric hook linked
above. It is a FreeCAD file with a spreadsheet. The only change made here was
to the sizes in that spreadsheet:

| Device | `Parametric_Hook_Width` | `Parametric_Hook_Height` |
|---|---|---|
| 10-port USB hub, 211 x 61.5 x 17.5 mm, 4 hooks | 18 mm | 45 mm |
| Raspberry Pi Debug Probe | 10.5 mm | |
| Manhattan USB hub | 22 mm | |

All three were test printed and fit. The same hook was also sized for an
ESP32 dev kit and a Netgear ethernet switch.

<!-- photo: hub on its hooks -->
<!-- photo: debug probes -->

## Wiring

- Keep USB cables short, 0.3 to 0.5 m.
- Boards go on the switchable hub. Probes go on a hub that is always on.
- A board's USB path is its name in every script, and it is set by which hub
  port its cable is in. Do not move cables between ports.
