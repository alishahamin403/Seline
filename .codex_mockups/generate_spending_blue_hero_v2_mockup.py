from PIL import Image, ImageDraw, ImageFont

W, H = 1700, 980
img = Image.new('RGB', (W, H), (10, 12, 16))
d = ImageDraw.Draw(img)

panel = (16, 19, 25)
card = (22, 26, 33)
card2 = (28, 33, 42)
border = (49, 57, 70)
text = (236, 240, 247)
muted = (150, 160, 176)
subtle = (182, 194, 211)
hero = (32, 58, 80)
hero2 = (25, 47, 66)
green = (68, 216, 116)


def f(size, bold=False):
    options = [
        '/System/Library/Fonts/SFNSDisplay.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf' if bold else '/System/Library/Fonts/Supplemental/Arial.ttf'
    ]
    for p in options:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            pass
    return ImageFont.load_default()

ft = f(44, True)
fs = f(21)
fh = f(34, True)
fb = f(20, True)
fm = f(16)
fxs = f(12)


def rr(xy, r=18, fill=None, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


d.text((40, 28), 'Spending Card Mockup (Blue Hero with Month + Today + MoM)', fill=text, font=ft)
d.text((40, 84), 'Requested: put This Month amount, Today amount, and MoM % inside the blue box', fill=muted, font=fs)

# phone frame
x0, y0, pw, ph = 120, 130, 560, 820
rr((x0, y0, x0 + pw, y0 + ph), r=42, fill=panel, outline=(40, 48, 62), width=2)
rr((x0 + 208, y0 + 18, x0 + 352, y0 + 34), r=8, fill=(6, 8, 11))

# card shell
cx, cy, cw, ch = x0 + 26, y0 + 72, 508, 720
rr((cx, cy, cx + cw, cy + ch), r=28, fill=card, outline=border, width=1)

# blue hero box taller to include mini metrics
hx, hy, hw, hh = cx + 14, cy + 14, cw - 28, 268
for i in range(8):
    inset = i * 2
    rr((hx + inset, hy + inset, hx + hw - inset, hy + hh - inset), r=max(16, 18 - i), fill=(hero[0] - i, hero[1] - i, hero[2] - i), outline=None)
rr((hx, hy, hx + hw, hy + hh), r=18, fill=None, outline=(73, 97, 122), width=1)

# top row in hero
rr((hx + hw - 42, hy + 14, hx + hw - 12, hy + 44), r=15, fill=(37, 53, 71), outline=(88, 112, 138), width=1)
d.text((hx + hw - 27, hy + 29), '+', fill=text, font=fb, anchor='mm')

d.text((hx + 14, hy + 16), 'SPENDING', fill=subtle, font=fxs)

d.text((hx + 14, hy + 48), 'This Month', fill=text, font=fh)
d.text((hx + 14, hy + 100), '$1,438', fill=text, font=f(42, True))

# mini stats inside hero
def mini_metric(x, title, value, color=text):
    rr((x, hy + 182, x + 148, hy + 246), r=12, fill=(38, 57, 77), outline=(82, 103, 126), width=1)
    d.text((x + 12, hy + 197), title, fill=subtle, font=fxs)
    d.text((x + 12, hy + 220), value, fill=color, font=fb)

mini_metric(hx + 14, 'Month', '$1,438')
mini_metric(hx + 172, 'Today', '$0')
mini_metric(hx + 330, 'MoM', '↓ 35%', color=green)

# insights kept below hero
d.text((cx + 20, cy + 300), 'INSIGHTS', fill=(170, 182, 201), font=fxs)
insights = [
    ('5 month streak', "You've visited Tim Hortons 5 months in a row"),
    ('Coffee ↑ 13%', '+$8 vs last month'),
    ('Food trend stable', 'Only +2% this month')
]
ix = cx + 20
iy = cy + 322
for title, subtitle in insights:
    w = 292 if 'streak' in title else 216
    rr((ix, iy, ix + w, iy + 96), r=16, fill=card2, outline=border, width=1)
    d.text((ix + 14, iy + 18), title, fill=text, font=fb)
    d.text((ix + 14, iy + 52), subtitle, fill=muted, font=fm)
    ix += w + 10

# notes panel
nx, ny, nw, nh = 760, 200, 860, 640
rr((nx, ny, nx + nw, ny + nh), r=22, fill=card, outline=border, width=1)
d.text((nx + 24, ny + 24), 'Applied Request', fill=text, font=f(33, True))
notes = [
    '1. This Month label + amount are in the blue hero.',
    '2. Today amount is moved inside the blue hero.',
    '3. MoM % is moved inside the blue hero.',
    '4. Existing insights row remains below, unchanged.',
    '5. If you approve, I can implement this exact layout in code.'
]
by = ny + 90
for line in notes:
    d.text((nx + 30, by), line, fill=muted, font=fm)
    by += 40

# mini comparison swatches
swatches = [
    ('Balanced Blue', (32, 58, 80)),
    ('Darker Blue', (26, 47, 66)),
    ('Lighter Blue', (44, 70, 95)),
]
ox = nx + 24
d.text((nx + 24, ny + 320), 'Hero Tone Options', fill=text, font=fb)
for name, col in swatches:
    rr((ox, ny + 352, ox + 250, ny + 480), r=14, fill=col, outline=(76, 99, 121), width=1)
    d.text((ox + 12, ny + 370), name, fill=(224, 234, 248), font=fm)
    d.text((ox + 12, ny + 446), f'RGB {col}', fill=(188, 203, 221), font=fxs)
    ox += 270

rr((40, 934, 1660, 968), r=12, fill=(16, 20, 27), outline=(44, 54, 67), width=1)
d.text((56, 944), 'If this matches what you want, say "implement this version" and I\'ll patch SpendingAndETAWidget.swift.', fill=(171, 188, 208), font=fm)

out = '/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/spending_card_blue_hero_v2_mockup.png'
img.save(out)
print(out)
