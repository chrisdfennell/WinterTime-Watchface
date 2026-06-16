#!/usr/bin/env python
"""
Generate Snowfall store / promotional art into assets/, matching the format set used
by the sibling summer-watchface project:

    hero_image.png      1440x720  -- wide banner: "WINTERTIME" title + watch on a scene
    cover_image.png     500x500   -- square cover: the watch on a winter scene
    cover_image.jpg     500x500   -- JPEG twin of the cover
    app_icon_24bit.png  128x128   -- circular store icon (snowflake badge)
    app_icon_64color.png 128x128  -- same icon (separate file kept for parity)

The scene is composed from the watch face's own winter palette (twilight sky, aurora,
stars, moon, snow drifts, pines, falling snow) so the art stays on-brand, with the
real watch render (assets/screen_active.png) dropped into a drawn watch body.

Run:  python tools/gen_promo.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
RENDER = os.path.join(ASSETS, "screen_active.png")  # 454x454 round RGBA
BOLD_FONT = "C:/Windows/Fonts/segoeuib.ttf"

SS = 2  # supersample factor for the big pieces

# --- winter palette (mirrors SnowfallView's twilight gradient) ----------------
SKY = [
    (0.00, (20, 17, 52)),     # deep indigo zenith
    (0.30, (46, 42, 92)),
    (0.55, (92, 86, 140)),    # periwinkle
    (0.70, (150, 150, 188)),  # pale horizon glow
    (0.80, (210, 216, 234)),  # haze just above snow
    (0.86, (236, 242, 250)),  # snow begins
    (1.00, (250, 252, 255)),  # bright snow foreground
]
SNOW_TOP = 0.84  # fraction of height where the snow ground starts


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def grad_color(stops, t):
    t = max(0.0, min(1.0, t))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        if p0 <= t <= p1:
            return lerp(c0, c1, (t - p0) / (p1 - p0) if p1 > p0 else 0)
    return stops[-1][1]


def vgrad(w, h, stops):
    col = Image.new("RGB", (1, h))
    for y in range(h):
        col.putpixel((0, y), grad_color(stops, y / (h - 1)))
    return col.resize((w, h))


def draw_pine(d, cx, base_y, h, w, fill, snow=(244, 248, 255)):
    """A tiered evergreen with snow caps, point at top."""
    tiers = 4
    top = base_y - h
    for i in range(tiers):
        ty = top + (h * 0.78) * i / tiers
        by = top + (h * 0.78) * (i + 1.6) / tiers
        half = w * (0.30 + 0.70 * (i + 1) / tiers) / 2
        d.polygon([(cx, ty), (cx - half, by), (cx + half, by)], fill=fill)
        # snow cap on each tier
        d.polygon([(cx, ty), (cx - half * 0.5, ty + (by - ty) * 0.42),
                   (cx, ty + (by - ty) * 0.30), (cx + half * 0.5, ty + (by - ty) * 0.42)],
                  fill=snow)
    # trunk
    tw = max(2, int(w * 0.06))
    d.rectangle([cx - tw, base_y - h * 0.04, cx + tw, base_y + h * 0.02], fill=(70, 54, 40))


def build_scene(w, h):
    """Return an RGB winter scene sized (w, h)."""
    rnd = random.Random(7)
    img = vgrad(w, h, SKY)
    d = ImageDraw.Draw(img, "RGBA")
    snow_y = int(h * SNOW_TOP)

    # stars (upper sky only)
    for _ in range(int(w * h / 5500)):
        x = rnd.randint(0, w - 1)
        y = rnd.randint(0, int(snow_y * 0.62))
        r = rnd.choice([1, 1, 1, 2])
        a = rnd.randint(120, 235)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))

    # aurora ribbons (translucent, blurred)
    aur = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ad = ImageDraw.Draw(aur)
    bands = [((90, 220, 150), 0.20), ((90, 200, 220), 0.27), ((150, 130, 220), 0.34)]
    for color, yc in bands:
        pts = []
        for xi in range(0, w + 1, max(2, w // 220)):
            t = xi / w
            yy = h * yc + math.sin(t * math.pi * 2.2 + yc * 9) * h * 0.035
            pts.append((xi, yy))
        for thick, alpha in [(int(h * 0.05), 46), (int(h * 0.025), 70)]:
            ad.line(pts, fill=color + (alpha,), width=max(2, thick), joint="curve")
    aur = aur.filter(ImageFilter.GaussianBlur(h * 0.02))
    img.paste(aur, (0, 0), aur)

    # moon with glow (upper left-ish)
    mr = int(min(w, h) * 0.05)
    mx, my = int(w * 0.16), int(snow_y * 0.34)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([mx - mr * 2.6, my - mr * 2.6, mx + mr * 2.6, my + mr * 2.6],
               fill=(220, 228, 255, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(mr))
    img.paste(glow, (0, 0), glow)
    d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(238, 242, 255))
    d.ellipse([mx - mr + mr * 0.7, my - mr, mx + mr + mr * 0.7, my + mr],
              fill=grad_color(SKY, my / (h - 1)))  # crescent bite

    # rolling snow ground (two soft drift layers)
    for layer, (off, col) in enumerate([(0, (228, 236, 248)), (int(h * 0.04), (250, 252, 255))]):
        pts = [(0, h)]
        for xi in range(0, w + 1, max(2, w // 90)):
            yy = snow_y + off + math.sin(xi / w * math.pi * 3 + layer) * h * 0.012
            pts.append((xi, yy))
        pts.append((w, h))
        d.polygon(pts, fill=col)

    # pines near the lower-right (and a small one lower-left)
    draw_pine(d, int(w * 0.86), int(snow_y + h * 0.05), int(h * 0.30), int(w * 0.11),
              fill=(28, 70, 52))
    draw_pine(d, int(w * 0.93), int(snow_y + h * 0.09), int(h * 0.20), int(w * 0.075),
              fill=(34, 80, 60))
    draw_pine(d, int(w * 0.08), int(snow_y + h * 0.07), int(h * 0.17), int(w * 0.065),
              fill=(30, 74, 55))

    # falling snow
    snow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(snow)
    for _ in range(int(w * h / 2600)):
        x = rnd.randint(0, w - 1)
        y = rnd.randint(0, h - 1)
        r = rnd.choice([1, 1, 2, 2, 3])
        a = rnd.randint(120, 230)
        sd.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))
    snow = snow.filter(ImageFilter.GaussianBlur(0.6))
    img.paste(snow, (0, 0), snow)
    return img


def paste_watch(scene, cx, cy, screen_d):
    """Draw a watch body and drop the real round render onto it, centred at (cx, cy)."""
    w, h = scene.size
    render = Image.open(RENDER).convert("RGBA").resize((screen_d, screen_d), Image.LANCZOS)
    case_d = int(screen_d * 1.13)
    band_w = int(case_d * 0.46)

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # contact shadow on the snow
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([cx - case_d * 0.55, cy + case_d * 0.30,
                                cx + case_d * 0.55, cy + case_d * 0.62],
                               fill=(10, 14, 30, 120))
    sh = sh.filter(ImageFilter.GaussianBlur(case_d * 0.04))
    scene.paste(sh, (0, 0), sh)

    # band (top + bottom), dark with a slight taper
    for sign in (-1, 1):
        y0 = cy + sign * case_d * 0.30
        y1 = cy + sign * case_d * 0.95
        top, bot = (y0, y1) if sign < 0 else (y1, y0)
        d.polygon([(cx - band_w / 2, cy), (cx + band_w / 2, cy),
                   (cx + band_w * 0.40, bot if sign > 0 else top),
                   (cx - band_w * 0.40, bot if sign > 0 else top)],
                  fill=(34, 36, 42, 255))
    # case
    d.ellipse([cx - case_d / 2, cy - case_d / 2, cx + case_d / 2, cy + case_d / 2],
              fill=(24, 25, 29, 255))
    # bezel ring
    bz = int(screen_d * 1.05)
    d.ellipse([cx - bz / 2, cy - bz / 2, cx + bz / 2, cy + bz / 2],
              outline=(70, 74, 82, 255), width=max(2, int(screen_d * 0.012)))
    scene.paste(layer, (0, 0), layer)

    # metallic sheen arc on the case (top-left)
    sheen = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).arc([cx - case_d / 2, cy - case_d / 2, cx + case_d / 2, cy + case_d / 2],
                              start=160, end=250, fill=(180, 190, 210, 150),
                              width=max(2, int(case_d * 0.02)))
    sheen = sheen.filter(ImageFilter.GaussianBlur(case_d * 0.01))
    scene.paste(sheen, (0, 0), sheen)

    # the actual round render (its own alpha makes it a clean circle)
    scene.paste(render, (cx - screen_d // 2, cy - screen_d // 2), render)


def draw_title(scene, text, cx, cy, px):
    """Centred, letter-spaced bold title with shadow + cool glow."""
    font = ImageFont.truetype(BOLD_FONT, px)
    track = int(px * 0.10)
    widths = [font.getbbox(ch)[2] - font.getbbox(ch)[0] for ch in text]
    total = sum(widths) + track * (len(text) - 1)
    asc, desc = font.getmetrics()

    glow = Image.new("RGBA", scene.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    x = cx - total / 2
    y = cy - (asc + desc) / 2
    for ch, wch in zip(text, widths):
        gd.text((x, y), ch, font=font, fill=(150, 210, 255, 255))
        x += wch + track
    glow = glow.filter(ImageFilter.GaussianBlur(px * 0.10))
    scene.paste(glow, (0, 0), glow)

    d = ImageDraw.Draw(scene)
    x = cx - total / 2
    for ch, wch in zip(text, widths):
        d.text((x + px * 0.03, y + px * 0.03), ch, font=font, fill=(20, 24, 48))  # shadow
        d.text((x, y), ch, font=font, fill=(233, 244, 255))                       # face
        x += wch + track


def snowflake(size):
    """A clean 6-armed snowflake badge -> RGBA (size x size)."""
    S = size * 4
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # circular gradient badge
    badge = vgrad(S, S, [(0.0, (40, 38, 92)), (0.55, (58, 70, 140)),
                         (1.0, (120, 150, 210))]).convert("RGBA")
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([S * 0.02, S * 0.02, S * 0.98, S * 0.98], fill=255)
    img.paste(badge, (0, 0), mask)
    d.ellipse([S * 0.02, S * 0.02, S * 0.98, S * 0.98], outline=(225, 236, 255, 230),
              width=max(2, int(S * 0.025)))

    cx = cy = S / 2
    arm = S * 0.36
    lw = max(2, int(S * 0.028))
    col = (236, 246, 255, 255)
    for k in range(6):
        a = math.radians(60 * k)
        ex, ey = cx + math.cos(a) * arm, cy + math.sin(a) * arm
        d.line([(cx, cy), (ex, ey)], fill=col, width=lw)
        # side branches
        for f in (0.45, 0.70):
            bx, by = cx + math.cos(a) * arm * f, cy + math.sin(a) * arm * f
            blen = arm * 0.26 * (1.1 - f)
            for da in (-50, 50):
                a2 = a + math.radians(da)
                d.line([(bx, by), (bx + math.cos(a2) * blen, by + math.sin(a2) * blen)],
                       fill=col, width=lw)
    d.ellipse([cx - S * 0.04, cy - S * 0.04, cx + S * 0.04, cy + S * 0.04], fill=col)
    return img.resize((size, size), Image.LANCZOS)


def build_hero():
    W, H = 1440 * SS, 720 * SS
    scene = build_scene(W, H)
    paste_watch(scene, int(W * 0.50), int(H * 0.55), int(H * 0.60))
    draw_title(scene, "WINTERTIME", int(W * 0.50), int(H * 0.135), int(H * 0.115))
    return scene.resize((1440, 720), Image.LANCZOS)


def build_cover():
    W = H = 500 * SS
    scene = build_scene(W, H)
    paste_watch(scene, W // 2, int(H * 0.50), int(H * 0.66))
    return scene.resize((500, 500), Image.LANCZOS)


if __name__ == "__main__":
    hero = build_hero()
    hero.save(os.path.join(ASSETS, "hero_image.png"))
    print("hero_image.png      1440x720")

    cover = build_cover()
    cover.save(os.path.join(ASSETS, "cover_image.png"))
    cover.convert("RGB").save(os.path.join(ASSETS, "cover_image.jpg"), quality=90)
    print("cover_image.png/.jpg 500x500")

    icon = snowflake(128)
    icon.convert("RGB").save(os.path.join(ASSETS, "app_icon_24bit.png"))
    icon.convert("RGB").save(os.path.join(ASSETS, "app_icon_64color.png"))
    print("app_icon_*.png      128x128")
    print("Done.")
