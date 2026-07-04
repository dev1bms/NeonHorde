#!/usr/bin/env python3
"""Slice an AI-generated collage sheet into ArtDrop assets (AMENDMENT v3).

- Regions are fractional boxes measured off the owner's collage layout.
- Transparency: flood-fill from region borders across desaturated-gray pixels
  (the fake checkerboard + canvas gray), so sprite-internal grays survive.
- Frames: column-projection segmentation, recomposed into uniform cells with
  bottom-center anchoring (feet alignment) — exactly the layout ArtLibrary
  slices back out. Falls back to equal-split when counts don't match.

Usage: python3 tools/slice_artdrop.py <collage.png> [standalone_idle.png]
Writes into ArtDrop/ and prints a REPORT line per asset.
"""
import sys
import numpy as np
from PIL import Image

OUT = "/Users/devbms/Games/NeonHorde/ArtDrop"

# name: (x0, y0, x1, y1, frames, kind)  kind: sheet|opaque|grid2x4|whole
# Tops sit BELOW each label line (v2: measured against the first-pass review).
REGIONS = {
    "player_idle":   (0.000, 0.030, 0.400, 0.170, 4, "sheet"),
    "player_run":    (0.000, 0.200, 0.405, 0.315, 6, "sheet"),
    "player_attack": (0.000, 0.345, 0.370, 0.480, 6, "sheet"),
    "player_death":  (0.000, 0.505, 0.375, 0.640, 6, "sheet"),
    "monster_wolf":  (0.400, 0.030, 0.690, 0.165, 3, "sheet"),
    "monster_troll": (0.400, 0.215, 0.660, 0.325, 3, "sheet"),
    "monster_slime": (0.400, 0.372, 0.650, 0.470, 3, "sheet"),
    "monster_wraith":(0.400, 0.512, 0.640, 0.615, 3, "sheet"),
    "monster_shaman":(0.400, 0.655, 0.630, 0.725, 3, "sheet"),
    "boss_prime":    (0.700, 0.535, 1.000, 0.715, 3, "sheet"),
    "ground_stage1": (0.003, 0.755, 0.158, 0.995, 0, "opaque"),
    "ground_stage2": (0.178, 0.755, 0.333, 0.995, 0, "opaque"),
    "ground_stage3": (0.353, 0.755, 0.508, 0.995, 0, "opaque"),
    "props_sheet":   (0.522, 0.750, 0.703, 0.998, 8, "grid2x4"),
    "ui_kit":        (0.715, 0.752, 0.998, 0.998, 0, "whole"),
}

# Per-region bg-detection overrides: (spread, lum_lo, lum_hi).
# The wraith's glow blurs the fake checker → needs a looser net.
BG_OVERRIDES = {
    "monster_wraith": (26, 45, 235),
    "player_idle": (16, 35, 232),   # standalone sheet uses a darker checker
}
BG_DEFAULT = (16, 60, 232)


def bg_candidate(rgb, params=BG_DEFAULT):
    """Desaturated mid-grays: canvas + both checker shades, not sprite colors."""
    max_spread, lum_lo, lum_hi = params
    r = rgb[..., 0].astype(np.int16)
    g = rgb[..., 1].astype(np.int16)
    b = rgb[..., 2].astype(np.int16)
    spread = np.maximum(np.maximum(abs(r - g), abs(g - b)), abs(r - b))
    lum = (r + g + b) / 3
    return (spread < max_spread) & (lum > lum_lo) & (lum < lum_hi)


def flood_from_border(candidate):
    """Reachable-from-border flood across the candidate mask (numpy dilation)."""
    reach = np.zeros_like(candidate, bool)
    reach[0, :] = candidate[0, :]
    reach[-1, :] = candidate[-1, :]
    reach[:, 0] = candidate[:, 0]
    reach[:, -1] = candidate[:, -1]
    while True:
        grown = reach.copy()
        grown[1:, :] |= reach[:-1, :]
        grown[:-1, :] |= reach[1:, :]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= candidate
        if (grown == reach).all():
            return reach
        reach = grown


def extract_alpha(region, params=BG_DEFAULT):
    """RGBA with background made transparent via border flood, plus a label
    scrub: white text remnants live in the top/bottom bands of every region
    (neighbouring rows' captions) — kill near-white desaturated pixels there."""
    rgb = region[..., :3]
    bg = flood_from_border(bg_candidate(rgb, params))

    r = rgb[..., 0].astype(np.int16)
    g = rgb[..., 1].astype(np.int16)
    b = rgb[..., 2].astype(np.int16)
    spread = np.maximum(np.maximum(abs(r - g), abs(g - b)), abs(r - b))
    lum = (r + g + b) / 3
    textish = (lum > 195) & (spread < 30)
    h = region.shape[0]
    band = np.zeros(bg.shape, bool)
    band[: int(h * 0.18)] = True
    band[int(h * 0.82):] = True
    bg |= textish & band

    out = np.dstack([rgb, np.where(bg, 0, 255).astype(np.uint8)])
    return out


def components(alpha, min_area=400):
    """2D connected components via repeated restricted flood (no scipy)."""
    content = alpha > 0
    visited = np.zeros_like(content, bool)
    comps = []
    ys, xs = np.where(content)
    order = np.argsort(ys * content.shape[1] + xs)
    idx = 0
    while idx < len(order):
        y, x = ys[order[idx]], xs[order[idx]]
        idx += 1
        if visited[y, x]:
            continue
        seed = np.zeros_like(content, bool)
        seed[y, x] = True
        while True:
            grown = seed.copy()
            grown[1:, :] |= seed[:-1, :]
            grown[:-1, :] |= seed[1:, :]
            grown[:, 1:] |= seed[:, :-1]
            grown[:, :-1] |= seed[:, 1:]
            grown &= content
            if (grown == seed).all():
                break
            seed = grown
        visited |= seed
        if seed.sum() >= min_area:
            cys, cxs = np.where(seed)
            comps.append((seed.sum(), cys.min(), cys.max(), cxs.min(), cxs.max()))
    return comps


def content_spans(alpha, axis, min_ratio=0.01, min_gap=6, min_span=14):
    proj = (alpha > 0).mean(axis=axis)
    on = proj > min_ratio
    spans = []
    start = None
    for i, v in enumerate(on):
        if v and start is None:
            start = i
        elif not v and start is not None:
            spans.append([start, i])
            start = None
    if start is not None:
        spans.append([start, len(on)])
    # merge close spans (sword swoosh gaps) and drop dust
    merged = []
    for s in spans:
        if merged and s[0] - merged[-1][1] < min_gap:
            merged[-1][1] = s[1]
        else:
            merged.append(s)
    return [s for s in merged if s[1] - s[0] >= min_span]


def compose_cells(frames, pad=10):
    cw = max(f.shape[1] for f in frames) + pad * 2
    ch = max(f.shape[0] for f in frames) + pad * 2
    sheet = np.zeros((ch, cw * len(frames), 4), np.uint8)
    for i, f in enumerate(frames):
        x = i * cw + (cw - f.shape[1]) // 2
        y = ch - pad - f.shape[0]          # bottom anchor = feet aligned
        sheet[y:y + f.shape[0], x:x + f.shape[1]] = f
    return sheet


def trim(rgba):
    a = rgba[..., 3]
    ys, xs = np.where(a > 0)
    if len(xs) == 0:
        return rgba
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def slice_sheet(rgba, n):
    """Use detected spans when plausible (±2 of expected) — intact swooshes
    beat exact counts; ArtLibrary cell-detects dynamically. Otherwise split
    the trimmed strip into exactly n equal cells."""
    spans = content_spans(rgba[..., 3], axis=0)
    if len(spans) >= 2 and abs(len(spans) - n) <= 2:
        frames = [trim(rgba[:, s0:s1]) for s0, s1 in spans]
        note = f"{len(spans)} spans detected (expected {n})"
    else:
        body = trim(rgba)
        w = body.shape[1] // n
        frames = [trim(body[:, i * w:(i + 1) * w]) for i in range(n)]
        note = f"equal-split fallback (found {len(spans)} spans)"
    return compose_cells(frames), note


def process(img, name, box):
    x0, y0, x1, y1, n, kind = box
    H, W = img.shape[:2]
    region = img[int(y0 * H):int(y1 * H), int(x0 * W):int(x1 * W)]

    if kind == "opaque":
        h, w = region.shape[:2]
        inset = region[int(h * 0.04):int(h * 0.96), int(w * 0.04):int(w * 0.96), :3]
        Image.fromarray(inset).save(f"{OUT}/{name}.png")
        return f"{inset.shape[1]}x{inset.shape[0]} opaque"

    rgba = extract_alpha(region, BG_OVERRIDES.get(name, BG_DEFAULT))
    if kind == "whole":
        result = trim(rgba)
        Image.fromarray(result).save(f"{OUT}/{name}.png")
        tp = round(float((result[..., 3] < 10).mean()), 2)
        return f"{result.shape[1]}x{result.shape[0]} whole transparent={tp}"

    if kind == "grid2x4":
        # True 2D component isolation (props are irregularly arranged).
        comps = components(rgba[..., 3])
        comps.sort(key=lambda c: -c[0])
        cells = [rgba[y0:y1 + 1, x0:x1 + 1] for _, y0, y1, x0, x1 in comps[:8]]
        if not cells:
            return "NO COMPONENTS — skipped"
        while len(cells) < 8:
            cells.append(cells[len(cells) % max(1, len(cells) - 1)])
        cw = max(c.shape[1] for c in cells) + 16
        ch = max(c.shape[0] for c in cells) + 16
        sheet = np.zeros((ch * 2, cw * 4, 4), np.uint8)
        for i, c in enumerate(cells):
            row, col = divmod(i, 4)
            x = col * cw + (cw - c.shape[1]) // 2
            y = row * ch + ch - 8 - c.shape[0]
            sheet[y:y + c.shape[0], x:x + c.shape[1]] = c
        Image.fromarray(sheet).save(f"{OUT}/{name}.png")
        return f"{sheet.shape[1]}x{sheet.shape[0]} grid 4x2 ({len(comps)} components found)"

    sheet, note = slice_sheet(rgba, n)
    Image.fromarray(sheet).save(f"{OUT}/{name}.png")
    tp = round(float((sheet[..., 3] < 10).mean()), 2)
    return f"{sheet.shape[1]}x{sheet.shape[0]} {note} transparent={tp}"


def main():
    collage = np.array(Image.open(sys.argv[1]).convert("RGBA"))
    standalone_idle = sys.argv[2] if len(sys.argv) > 2 else None

    for name, box in REGIONS.items():
        if name == "player_idle" and standalone_idle:
            img = np.array(Image.open(standalone_idle).convert("RGBA"))
            rgba = extract_alpha(img, BG_OVERRIDES.get(name, BG_DEFAULT))
            sheet, note = slice_sheet(rgba, 4)
            Image.fromarray(sheet).save(f"{OUT}/{name}.png")
            tp = round(float((sheet[..., 3] < 10).mean()), 2)
            print(f"REPORT {name}: {sheet.shape[1]}x{sheet.shape[0]} "
                  f"[standalone hi-res] {note} transparent={tp}")
            continue
        print(f"REPORT {name}: {process(collage, name, box)}")


if __name__ == "__main__":
    main()
