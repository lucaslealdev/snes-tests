#!/usr/bin/env python3
"""Generates the graphics assets of the harness: font, UI tiles, palette, cursor sprite and the HDMA gradient.

Usage: make_assets.py [output_dir]      (default output_dir: ../build)

The ASCII glyph shapes come from font-base.bin (8x8, 1 bit per pixel in the first bit plane of 2bpp tiles,
inherited from the legacy ROMs). All the UI glyphs (checkboxes, arrows, progress bar) are drawn here.

Outputs: font4.bin (4bpp tiles, for BG1), font2.bin (2bpp tiles, for BG3), obj.bin (4bpp sprite tiles),
palette.bin (CGRAM, 512 bytes), hdma.bin (background gradient) and assets.inc (the .incbin lines).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Extra tiles after the 128 ASCII glyphs. Each is 8 rows of 8 pixels ('#' = set).
EXTRA = {
    128: ['........', '.######.', '.#....#.', '.#....#.', '.#....#.', '.#....#.', '.######.', '........'],  # [ ]
    129: ['........', '.######.', '.#....#.', '.#.##.#.', '.#.##.#.', '.#....#.', '.######.', '........'],  # [x]
    130: ['..#.....', '..##....', '..###...', '..####..', '..###...', '..##....', '..#.....', '........'],  # pointer
    131: ['........', '.######.', '..####..', '...##...', '........', '........', '........', '........'],  # expanded
    132: ['..#.....', '..##....', '..###...', '..##....', '..#.....', '........', '........', '........'],  # collapsed
    133: ['........', '........', '........', '........', '........', '........', '........', '........'],  # blank
}
BAR_FIRST = 134  # 134 = empty track, 135..142 = 1..8 pixels filled
TILE_COUNT = 143


def bar_tile(fill):
    rows = []
    for y in range(8):
        if y in (2, 5):
            # top and bottom borders of the bar (always drawn)
            row = '########'
        elif 2 < y < 5:
            row = '#' * fill + '.' * (8 - fill)
        else:
            row = '........'
        rows.append(row)
    return rows


def glyphs():
    base = open(os.path.join(HERE, 'font-base.bin'), 'rb').read()
    tiles = []
    for c in range(128):
        rows = []
        for y in range(8):
            b = base[c * 16 + y * 2]
            rows.append(''.join('#' if b & (0x80 >> x) else '.' for x in range(8)))
        tiles.append(rows)
    for i in range(128, TILE_COUNT):
        if i in EXTRA:
            tiles.append(EXTRA[i])
        elif i >= BAR_FIRST:
            fill = i - BAR_FIRST
            rows = bar_tile(fill if fill else 0)
            if fill == 0:
                rows = ['........', '........', '########', '........', '........', '########', '........', '........']
                rows = ['........', '........', '........', '........', '........', '........', '........', '........']
                rows[2] = '########'
                rows[5] = '########'
                rows[3] = rows[4] = '#......#'
            else:
                rows[3] = rows[4] = '#' * fill + '.' * (8 - fill)
                rows[3] = rows[4] = ('#' * fill + '.' * (8 - fill))
            tiles.append(rows)
        else:
            tiles.append(['........'] * 8)
    return tiles


def encode(tile, bpp, plane_value=1):
    """Tile pixels all use color index `plane_value` (1) where set."""
    planes = [[0] * 8 for _ in range(bpp)]
    for y, row in enumerate(tile):
        for x, ch in enumerate(row):
            if ch == '#':
                for p in range(bpp):
                    if (plane_value >> p) & 1:
                        planes[p][y] |= 0x80 >> x
    out = bytearray()
    for pair in range(0, bpp, 2):
        for y in range(8):
            out.append(planes[pair][y])
            out.append(planes[pair + 1][y])
    return bytes(out)


def rgb(r, g, b):
    return (b >> 3) << 10 | (g >> 3) << 5 | (r >> 3)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'build')
    os.makedirs(outdir, exist_ok=True)
    tiles = glyphs()
    font4 = b''.join(encode(t, 4) for t in tiles)
    font2 = b''.join(encode(t, 2) for t in tiles)

    # Cursor sprite: an arrow. Two tiles: normal, shifted by one pixel (animation)
    arrow = ['..#.....', '..##....', '..###...', '..####..', '..###...', '..##....', '..#.....', '........']
    arrow2 = [(' ' + r)[:8].replace(' ', '.') for r in arrow]
    obj = encode(arrow, 4) + encode(arrow2, 4)

    # CGRAM. Color 0 is the backdrop, replaced by the HDMA gradient. BG1 uses palettes 1..7 (16 colors each, only
    # color 1 is used by the font). BG3 (2bpp) uses palette 0 (colors 1..3): header text.
    pal = [0] * 256
    text_colors = {
        1: rgb(232, 236, 248),   # normal text
        2: rgb(112, 120, 144),   # dim / disabled
        3: rgb(96, 208, 248),    # accent (selection, headers)
        4: rgb(104, 224, 128),   # pass
        5: rgb(248, 104, 96),    # fail
        6: rgb(248, 208, 96),    # warning
        7: rgb(176, 160, 248),   # category
    }
    for p, c in text_colors.items():
        pal[p * 16 + 1] = c
    # BG3 (2bpp) palettes 0..3 use CGRAM 1, 5, 9, 13: normal, accent (cursor), dim, warning (harness/text.asm)
    pal[1], pal[5], pal[9], pal[13] = text_colors[1], text_colors[3], text_colors[2], text_colors[6]
    pal[128 + 1] = rgb(248, 224, 96)  # cursor sprite
    palette = b''.join(c.to_bytes(2, 'little') for c in pal)

    # HDMA gradient for color 0: entries of [count, CGADD, CGADD, lo, hi] (mode 3 to $2121/$2122), 8 scanlines each
    hdma = bytearray()
    bands = 28
    for i in range(bands):
        t = i / (bands - 1)
        r = int(10 + 22 * t)
        g = int(14 + 6 * t)
        b = int(40 - 10 * t)
        c = rgb(r, g, b)
        hdma += bytes([8, 0, 0, c & 0xFF, c >> 8])
    hdma += bytes([0])

    for name, data in (('font4.bin', font4), ('font2.bin', font2), ('obj.bin', obj), ('palette.bin', palette),
                       ('hdma.bin', bytes(hdma))):
        with open(os.path.join(outdir, name), 'wb') as f:
            f.write(data)
    with open(os.path.join(outdir, 'assets.inc'), 'w') as f:
        f.write('; Auto-generated by assets/make_assets.py\n')
        f.write(f'FONT_TILES = {len(tiles)}\n.export FONT_TILES\n')
        f.write('.segment "GFX"\n')
        for sym, name in (('gfx_font4', 'font4.bin'), ('gfx_font2', 'font2.bin'), ('gfx_obj', 'obj.bin'),
                          ('gfx_palette', 'palette.bin')):
            f.write(f'{sym}: .incbin "{name}"\n{sym}_end:\n.export {sym}, {sym}_end\n')
        f.write('.segment "RODATA"\ngfx_hdma: .incbin "hdma.bin"\n.export gfx_hdma\n')


main()
