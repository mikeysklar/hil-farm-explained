#!/usr/bin/env python3
"""Report contiguous address runs in a UF2, and optionally write each run to a .bin.

The nRF52840 image has an erased GAP in it; concatenating blocks blindly produces
a wrong image that still flashes and verifies. Always split on the real runs.

  uf2extract.py <file.uf2>                 # just report the runs
  uf2extract.py <file.uf2> <out-prefix>    # also write <prefix>_0xADDR.bin per run
"""
import struct, sys

MAGIC0, MAGIC1, MAGICEND = 0x0A324655, 0x9E5D5157, 0x0AB16F30

def runs(path):
    blocks = []
    with open(path, "rb") as f:
        blob = f.read()
    for off in range(0, len(blob), 512):
        b = blob[off:off + 512]
        if len(b) < 512:
            break
        m0, m1, flags, addr, size, blkno, nblk, famsize = struct.unpack("<8I", b[:32])
        if m0 != MAGIC0 or m1 != MAGIC1:
            continue
        if struct.unpack("<I", b[508:512])[0] != MAGICEND:
            continue
        if flags & 0x00001000:        # not-main-flash
            continue
        blocks.append((addr, b[32:32 + size]))
    blocks.sort(key=lambda x: x[0])

    out, cur_addr, cur = [], None, bytearray()
    for addr, data in blocks:
        if cur_addr is not None and addr == cur_addr + len(cur):
            cur += data
        else:
            if cur_addr is not None:
                out.append((cur_addr, bytes(cur)))
            cur_addr, cur = addr, bytearray(data)
    if cur_addr is not None:
        out.append((cur_addr, bytes(cur)))
    return out

if __name__ == "__main__":
    path = sys.argv[1]
    prefix = sys.argv[2] if len(sys.argv) > 2 else None
    rs = runs(path)
    print("%s: %d run(s)" % (path, len(rs)))
    for addr, data in rs:
        print("  0x%06x  %d bytes" % (addr, len(data)))
        if prefix:
            name = "%s_0x%x.bin" % (prefix, addr)
            with open(name, "wb") as f:
                f.write(data)
            print("    -> %s" % name)
