#!/usr/bin/env python3
"""Render the Movie Preflight macOS icon and build its ICNS."""
from __future__ import annotations
import math, os, shutil, struct, subprocess, zlib

SIZE = 1024
SCALE = 4
HI = SIZE * SCALE
BG = (0x16, 0x16, 0x16, 255)
OFF_WHITE = (0xF4, 0xF4, 0xF0, 255)
RED = (0xE0, 0x3A, 0x2E, 255)

def canvas():
    return bytearray(bytes((0, 0, 0, 0)) * (HI * HI))

def polygon(buf, points, color):
    pts = [(round(x * SCALE), round(y * SCALE)) for x, y in points]
    min_y = max(0, min(y for _, y in pts)); max_y = min(HI - 1, max(y for _, y in pts))
    for y in range(min_y, max_y + 1):
        scan = y + 0.5; xs = []
        for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
            if (y1 <= scan < y2) or (y2 <= scan < y1):
                xs.append(x1 + (scan - y1) * (x2 - x1) / (y2 - y1))
        xs.sort()
        for a, b in zip(xs[::2], xs[1::2]):
            for x in range(max(0, math.ceil(a)), min(HI - 1, math.floor(b)) + 1):
                i = (y * HI + x) * 4; buf[i:i + 4] = bytes(color)

def superellipse(buf, box, exponent, color, steps=720):
    """Dolly's continuous-curvature macOS squircle."""
    x0, y0, x1, y1 = box; cx, cy = (x0+x1)/2, (y0+y1)/2; rx, ry = (x1-x0)/2, (y1-y0)/2
    pts = []
    for i in range(steps):
        a = 2 * math.pi * i / steps; ca, sa = math.cos(a), math.sin(a)
        pts.append((cx + rx * math.copysign(abs(ca)**(2/exponent), ca),
                    cy + ry * math.copysign(abs(sa)**(2/exponent), sa)))
    polygon(buf, pts, color)

def half_disc(buf, cx, cy, radius, color):
    """Fill the right half of a true circle using a distance test."""
    x0 = max(0, math.floor((cx - radius) * SCALE))
    x1 = min(HI - 1, math.ceil((cx + radius) * SCALE))
    y0 = max(0, math.floor((cy - radius) * SCALE))
    y1 = min(HI - 1, math.ceil((cy + radius) * SCALE))
    r2 = (radius * SCALE) ** 2
    cx_hi, cy_hi = cx * SCALE, cy * SCALE
    ink = bytes(color)
    for y in range(y0, y1 + 1):
        for x in range(max(x0, math.ceil(cx_hi)), x1 + 1):
            dx = x + 0.5 - cx_hi; dy = y + 0.5 - cy_hi
            if dx * dx + dy * dy <= r2:
                i = (y * HI + x) * 4; buf[i:i + 4] = ink

def mitered_polyline(points, width):
    """Return one flat-ended, miter-joined stroke polygon."""
    h = width / 2
    (ax, ay), (bx, by), (cx, cy) = points
    def unit_normal(x1, y1, x2, y2):
        dx, dy = x2 - x1, y2 - y1; length = math.hypot(dx, dy)
        return -dy / length, dx / length
    n1x, n1y = unit_normal(ax, ay, bx, by)
    n2x, n2y = unit_normal(bx, by, cx, cy)
    def intersection(p, v, q, w):
        cross = v[0] * w[1] - v[1] * w[0]
        t = ((q[0] - p[0]) * w[1] - (q[1] - p[1]) * w[0]) / cross
        return p[0] + t * v[0], p[1] + t * v[1]
    left = intersection((bx + n1x*h, by + n1y*h), (bx-ax, by-ay),
                        (bx + n2x*h, by + n2y*h), (cx-bx, cy-by))
    right = intersection((bx - n1x*h, by - n1y*h), (bx-ax, by-ay),
                         (bx - n2x*h, by - n2y*h), (cx-bx, cy-by))
    return [(ax + n1x*h, ay + n1y*h), left,
            (cx + n2x*h, cy + n2y*h), (cx - n2x*h, cy - n2y*h),
            right, (ax - n1x*h, ay - n1y*h)]

def lanczos(x, a=3):
    if x == 0: return 1.0
    if abs(x) >= a: return 0.0
    p = math.pi*x; return (math.sin(p)/p) * (math.sin(p/a)/(p/a))

def resize_lanczos(buf, src_w, src_h, dst_w, dst_h):
    tmp = bytearray(dst_w * src_h * 4)
    for y in range(src_h):
        for x in range(dst_w):
            pos = (x+.5)*src_w/dst_w-.5
            ws = [(sx, lanczos(pos-sx)) for sx in range(math.floor(pos-3), math.ceil(pos+3)+1) if 0 <= sx < src_w]
            total = sum(w for _, w in ws)
            for c in range(4): tmp[(y*dst_w+x)*4+c] = max(0, min(255, round(sum(buf[(y*src_w+sx)*4+c]*w for sx,w in ws)/total)))
    out = bytearray(dst_w * dst_h * 4)
    for y in range(dst_h):
        pos = (y+.5)*src_h/dst_h-.5
        ws = [(sy, lanczos(pos-sy)) for sy in range(math.floor(pos-3), math.ceil(pos+3)+1) if 0 <= sy < src_h]
        total = sum(w for _, w in ws)
        for x in range(dst_w):
            for c in range(4): out[(y*dst_w+x)*4+c] = max(0, min(255, round(sum(tmp[(sy*dst_w+x)*4+c]*w for sy,w in ws)/total)))
    return out

def render_hi():
    b = canvas(); superellipse(b, (100, 100, 924, 924), 5.0, BG)
    # Capital P: 130 px stem, closed bowl, and stem continuing below the bowl.
    polygon(b, [(315,277), (445,277), (445,747), (315,747)], OFF_WHITE)
    half_disc(b, 445, 462, 185, OFF_WHITE)
    half_disc(b, 445, 462, 55, BG)
    polygon(b, mitered_polyline([(727,250), (767,290), (845,202)], 30), RED)
    return b

def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind+data) & 0xffffffff)

def write_png(path, rgba, width, height):
    rows = b"".join(b"\x00" + bytes(rgba[y*width*4:(y+1)*width*4]) for y in range(height))
    png = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width,height,8,6,0,0,0)) + png_chunk(b"IDAT", zlib.compress(rows,9)) + png_chunk(b"IEND", b"")
    with open(path, "wb") as f: f.write(png)

def make_icns(root, full):
    iconset = os.path.join(root, "MoviePreflight.iconset")
    if os.path.exists(iconset): shutil.rmtree(iconset)
    os.makedirs(iconset)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = size*scale; suffix = "@2x" if scale == 2 else ""
            destination = os.path.join(iconset, f"icon_{size}x{size}{suffix}.png")
            source = os.path.join(root, "MoviePreflight-1024.png")
            subprocess.run(["sips", "-z", str(px), str(px), source, "--out", destination],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sips", "-z", "48", "48", source, "--out",
                    os.path.join(iconset, "icon_48x48.png")],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(root, "MoviePreflight.icns")], capture_output=True, text=True)
    if result.returncode:
        print(result.stderr, end=""); raise SystemExit(result.returncode)

if __name__ == "__main__":
    root = os.path.dirname(os.path.abspath(__file__)); hi = render_hi()
    write_png(os.path.join(root, "MoviePreflight-1024.png"), resize_lanczos(hi, HI, HI, SIZE, SIZE), SIZE, SIZE)
    print("Wrote MoviePreflight-1024.png")
