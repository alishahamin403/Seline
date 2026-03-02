from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path

W, H = 1400, 2200
BG = "#f4f1eb"
SURFACE = "#fcfbf8"
INNER = "#f0ede7"
TEXT = "#111111"
MUTED = "#6f6a61"
BORDER = "#d9d2c8"
ORANGE = (250, 163, 105)
ORANGE_SOFT = (252, 228, 206)
GREEN = "#1d8f5f"
RED = "#cb4f4f"
CHIP = "#ece7df"
WHITE = "#ffffff"

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)


def font(size, bold=False):
    candidates = []
    if bold:
        candidates = [
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/Library/Fonts/Arial Bold.ttf",
            "/System/Library/Fonts/SFNS.ttf",
        ]
    else:
        candidates = [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/Library/Fonts/Arial.ttf",
            "/System/Library/Fonts/SFNS.ttf",
        ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()

FONT_TITLE = font(66, bold=True)
FONT_SECTION = font(24, bold=True)
FONT_BODY = font(28, bold=False)
FONT_BODY_BOLD = font(28, bold=True)
FONT_BIG = font(76, bold=True)
FONT_MED = font(36, bold=True)
FONT_SMALL = font(22, bold=False)
FONT_SMALL_BOLD = font(22, bold=True)
FONT_TINY = font(18, bold=False)
FONT_TINY_BOLD = font(18, bold=True)


def rounded_box(xy, radius=28, fill=SURFACE, outline=BORDER, width=2):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def text(xy, s, f, fill=TEXT, anchor=None):
    draw.text(xy, s, font=f, fill=fill, anchor=anchor)


def orange_wash(xy, radius=30):
    x1, y1, x2, y2 = xy
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(xy, radius=radius, fill=255)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((x1 - 120, y1 - 80, x1 + 420, y1 + 280), fill=(ORANGE[0], ORANGE[1], ORANGE[2], 50))
    gd.ellipse((x2 - 420, y1 + 120, x2 + 40, y2 + 120), fill=(ORANGE[0], ORANGE[1], ORANGE[2], 26))
    glow.putalpha(mask)
    return glow


def chip(x, y, w, h, label, bold=False, fill=CHIP, fg=TEXT, border=None):
    draw.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=fill, outline=border)
    bbox = draw.textbbox((0, 0), label, font=FONT_TINY_BOLD if bold else FONT_TINY)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    text((x + w / 2 - tw / 2, y + (h - th) / 2 - 2), label, FONT_TINY_BOLD if bold else FONT_TINY, fill=fg)


def metric_tile(x, y, w, h, label, value, accent=None):
    rounded_box((x, y, x + w, y + h), radius=24, fill=INNER, outline=None, width=0)
    text((x + 24, y + 18), label, FONT_TINY_BOLD, fill=MUTED)
    text((x + 24, y + 56), value, FONT_MED, fill=accent or TEXT)


def mini_card(x, y, w, h, title1, title2=None, meta=None, active=False, icon=False):
    fill = "#efe7dd" if active else INNER
    rounded_box((x, y, x + w, y + h), radius=24, fill=fill, outline=None, width=0)
    if icon:
        draw.rounded_rectangle((x + 16, y + 16, x + 56, y + 56), radius=14, fill=(242, 235, 227), outline=None)
        text((x + 28, y + 22), "$", FONT_SMALL_BOLD, fill=TEXT)
        tx = x + 72
    else:
        tx = x + 18
    if active:
        draw.ellipse((x + w - 26, y + 18, x + w - 14, y + 30), fill=GREEN)
    text((tx, y + 16), title1, FONT_SMALL_BOLD, fill=TEXT)
    if title2:
        text((tx, y + 48), title2, FONT_SMALL, fill=MUTED)
    if meta:
        text((tx, y + h - 38), meta, FONT_TINY_BOLD, fill=MUTED)


# Header
text((96, 88), "Home Widget Redesign", FONT_TITLE, fill=TEXT)
text((98, 170), "Spend and location cards brought into the same sleek hero language as People, Notes, and Locations.", FONT_BODY, fill=MUTED)

phone_x1, phone_y1, phone_x2, phone_y2 = 120, 250, 1280, 2100
draw.rounded_rectangle((phone_x1, phone_y1, phone_x2, phone_y2), radius=64, fill="#f7f4ef", outline="#d9d3ca", width=3)
draw.rounded_rectangle((560, 272, 840, 314), radius=20, fill="#161616")
text((190, 340), "9:41", FONT_BODY_BOLD, fill=TEXT)
text((190, 430), "Home", FONT_TITLE, fill=TEXT)
text((192, 500), "Redesigned widgets keep the Home page compact, but use the same premium surfaces and orange accent.", FONT_BODY, fill=MUTED)

# Spending card
sx1, sy1, sx2, sy2 = 170, 610, 1230, 1210
rounded_box((sx1, sy1, sx2, sy2), radius=42, fill=SURFACE, outline=BORDER, width=2)
img = Image.alpha_composite(img.convert("RGBA"), orange_wash((sx1, sy1, sx2, sy2), radius=42)).convert("RGB")
draw = ImageDraw.Draw(img)
text((sx1 + 42, sy1 + 34), "Spending", FONT_MED, fill=TEXT)
text((sx1 + 42, sy1 + 86), "Month snapshot with compact metrics and useful signals inside one card.", FONT_SMALL, fill=MUTED)
draw.ellipse((sx2 - 100, sy1 + 32, sx2 - 32, sy1 + 100), fill=ORANGE)
text((sx2 - 75, sy1 + 42), "+", FONT_MED, fill="#111111")
text((sx1 + 42, sy1 + 156), "$842", FONT_BIG, fill=TEXT)
text((sx1 + 42, sy1 + 244), "This month", FONT_SMALL_BOLD, fill=MUTED)
metric_tile(sx1 + 42, sy1 + 298, 300, 120, "Today", "$41")
metric_tile(sx1 + 360, sy1 + 298, 300, 120, "MoM", "+12%", accent=RED)
metric_tile(sx1 + 678, sy1 + 298, 300, 120, "Top", "Food")
text((sx1 + 42, sy1 + 454), "Signals", FONT_SMALL_BOLD, fill=TEXT)
mini_card(sx1 + 42, sy1 + 500, 280, 128, "Food", "+18% vs last month", "$302 total", icon=True)
mini_card(sx1 + 338, sy1 + 500, 280, 128, "Coffee runs", "3 stops this week", "$18 total", icon=True)
mini_card(sx1 + 634, sy1 + 500, 346, 128, "Target spike", "Largest purchase this week", "$124 yesterday", icon=True)
chip(sx1 + 42, sy2 - 78, 214, 42, "Open receipts", bold=True, fill=ORANGE_SOFT)
chip(sx1 + 272, sy2 - 78, 170, 42, "Camera", fill=CHIP)
chip(sx1 + 454, sy2 - 78, 174, 42, "Gallery", fill=CHIP)

# Location card
lx1, ly1, lx2, ly2 = 170, 1270, 1230, 1890
rounded_box((lx1, ly1, lx2, ly2), radius=42, fill=SURFACE, outline=BORDER, width=2)
img = Image.alpha_composite(img.convert("RGBA"), orange_wash((lx1, ly1, lx2, ly2), radius=42)).convert("RGB")
draw = ImageDraw.Draw(img)
text((lx1 + 42, ly1 + 34), "Current Location", FONT_MED, fill=TEXT)
chip(lx2 - 170, ly1 + 38, 120, 40, "Active", bold=True, fill="#ece7df")
text((lx1 + 42, ly1 + 116), "Whole Foods", FONT_BIG, fill=TEXT)
text((lx1 + 42, ly1 + 204), "42m here now", FONT_SMALL_BOLD, fill=MUTED)
metric_tile(lx1 + 42, ly1 + 258, 300, 120, "Visits", "4")
metric_tile(lx1 + 360, ly1 + 258, 300, 120, "Nearest", "0.2 km")
metric_tile(lx1 + 678, ly1 + 258, 300, 120, "Leave for home", "11m")
text((lx1 + 42, ly1 + 420), "Today", FONT_SMALL_BOLD, fill=TEXT)
mini_card(lx1 + 42, ly1 + 468, 220, 132, "Whole Foods", "42m", "Active", active=True)
mini_card(lx1 + 278, ly1 + 468, 220, 132, "Home", "2h 14m", "Morning")
mini_card(lx1 + 514, ly1 + 468, 220, 132, "Equinox", "58m", "Afternoon")
mini_card(lx1 + 750, ly1 + 468, 230, 132, "Chipotle", "23m", "Lunch")
chip(lx1 + 42, ly2 - 76, 200, 42, "Open details", bold=True, fill=ORANGE_SOFT)
chip(lx1 + 258, ly2 - 76, 204, 42, "Saved places", fill=CHIP)
chip(lx1 + 478, ly2 - 76, 170, 42, "Directions", fill=CHIP)

# Captions under phone
text((172, 1940), "Proposed direction", FONT_SECTION, fill=TEXT)
text((172, 1984), "Both widgets become single hero cards: one strong header, three metrics, and embedded horizontal context instead of disconnected sections.", FONT_BODY, fill=MUTED)

out = Path('/Users/alishahamin/Desktop/Vibecode/Seline/home-widget-redesign-mockup.png')
img.save(out)
print(out)
