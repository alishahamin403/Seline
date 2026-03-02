from PIL import Image, ImageDraw, ImageFont

W, H = 1700, 980
img = Image.new('RGB', (W, H), (10, 12, 16))
d = ImageDraw.Draw(img)

# palette
panel = (16, 19, 25)
card = (22, 26, 33)
card2 = (28, 33, 42)
border = (49, 57, 70)
text = (236, 240, 247)
muted = (150, 160, 176)
accent_blue = (112, 196, 248)
hero_bg = (31, 55, 76)
green = (68, 216, 116)
red = (236, 98, 98)


def font(size, bold=False):
    candidates = [
        '/System/Library/Fonts/SFNSDisplay.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf' if bold else '/System/Library/Fonts/Supplemental/Arial.ttf',
    ]
    for p in candidates:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            pass
    return ImageFont.load_default()

f_title = font(44, True)
f_sub = font(21)
f_h = font(34, True)
f_b = font(20, True)
f_sm = font(16)
f_xs = font(12)


def rr(xy, r=18, fill=None, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def draw_stat_pill(x, y, w, title, value, value_color=text):
    rr((x, y, x + w, y + 76), r=14, fill=card2, outline=border, width=1)
    d.text((x + 14, y + 14), title, fill=muted, font=f_sm)
    d.text((x + 14, y + 42), value, fill=value_color, font=f_b)


d.text((40, 28), 'Spending Card Redesign (Blue Hero Variant)', fill=text, font=f_title)
d.text((40, 84), 'Concept: bring Location-card blue hero treatment to Spending while keeping all existing content blocks', fill=muted, font=f_sub)

# phone frame
x0, y0, pw, ph = 120, 130, 560, 820
rr((x0, y0, x0 + pw, y0 + ph), r=42, fill=panel, outline=(40, 48, 62), width=2)
rr((x0 + 208, y0 + 18, x0 + 352, y0 + 34), r=8, fill=(6, 8, 11))

# spending card
cx, cy, cw, ch = x0 + 26, y0 + 72, 508, 720
rr((cx, cy, cx + cw, cy + ch), r=28, fill=card, outline=border, width=1)

# hero box (blue gradient feel by layered fills)
for i in range(7):
    inset = i * 2
    r = max(16, 18 - i)
    tone = (hero_bg[0] + i * 2, hero_bg[1] + i, hero_bg[2] - i)
    rr((cx + 14 + inset, cy + 14 + inset, cx + cw - 14 - inset, cy + 216 - inset), r=r, fill=tone)

# hero content
rr((cx + cw - 64, cy + 28, cx + cw - 26, cy + 66), r=19, fill=(35, 44, 57), outline=(75, 90, 110), width=1)
d.text((cx + cw - 45, cy + 47), '+', fill=text, font=f_b, anchor='mm')

d.text((cx + 28, cy + 32), 'SPENDING', fill=(176, 188, 206), font=f_xs)
d.text((cx + 28, cy + 68), 'This Month', fill=text, font=f_h)
d.text((cx + 28, cy + 122), '$1,438', fill=text, font=font(40, True))
d.text((cx + 28, cy + 172), 'Updated 10:52 PM', fill=(208, 218, 230), font=f_sm)

# stat row (kept)
pill_y = cy + 236
gap = 10
pill_w = int((cw - 36 - gap * 2) / 3)
draw_stat_pill(cx + 18, pill_y, pill_w, 'Month', '$1,438')
draw_stat_pill(cx + 18 + pill_w + gap, pill_y, pill_w, 'Today', '$0')
draw_stat_pill(cx + 18 + (pill_w + gap) * 2, pill_y, pill_w, 'MoM', '↓ 35%', value_color=green)

# insights chips (kept)
d.text((cx + 20, cy + 336), 'INSIGHTS', fill=(170, 182, 201), font=f_xs)

insights = [
    ('5 month streak', "You've visited Tim Hortons 5 months in a row"),
    ('Coffee ↑ 13%', '+$8 vs last month'),
    ('Food trend stable', 'Only +2% this month')
]
ix = cx + 20
iy = cy + 358
for title, subtitle in insights:
    w = 292 if 'streak' in title else 216
    rr((ix, iy, ix + w, iy + 96), r=16, fill=card2, outline=border, width=1)
    d.text((ix + 14, iy + 18), title, fill=text, font=f_b)
    d.text((ix + 14, iy + 52), subtitle, fill=muted, font=f_sm)
    ix += w + 10

# right side comparison/notes
nx, ny, nw, nh = 760, 200, 860, 640
rr((nx, ny, nx + nw, ny + nh), r=22, fill=card, outline=border, width=1)
d.text((nx + 24, ny + 24), 'What Changed', fill=text, font=font(32, True))

bullets = [
    '1. Added blue hero block like the Location card.',
    '2. Keeping Month / Today / MoM pills unchanged below hero.',
    '3. Keeping insight chips and spacing rhythm from current card.',
    '4. Hero can show total + last update + quick CTA (+).',
    '5. No interaction changes required unless you want new CTA actions.'
]
by = ny + 86
for line in bullets:
    d.text((nx + 30, by), line, fill=muted, font=f_sm)
    by += 40

# mini side-by-side swatches
d.text((nx + 24, ny + 320), 'Hero Tone Options', fill=text, font=f_b)
opts = [
    ('Soft Blue', (31, 55, 76)),
    ('Deeper Blue', (24, 45, 67)),
    ('Desat Blue', (40, 57, 73)),
]
ox = nx + 24
oy = ny + 352
for label, col in opts:
    rr((ox, oy, ox + 250, oy + 128), r=14, fill=col, outline=(72, 90, 111), width=1)
    d.text((ox + 14, oy + 16), label, fill=(220, 230, 244), font=f_sm)
    d.text((ox + 14, oy + 92), f'RGB {col}', fill=(186, 200, 219), font=f_xs)
    ox += 270

rr((40, 934, 1660, 968), r=12, fill=(16, 20, 27), outline=(44, 54, 67), width=1)
d.text((56, 944), 'If this direction looks right, I can implement this hero section directly in SpendingAndETAWidget.swift.', fill=(171, 188, 208), font=f_sm)

out = '/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/spending_card_blue_hero_mockup.png'
img.save(out)
print(out)
