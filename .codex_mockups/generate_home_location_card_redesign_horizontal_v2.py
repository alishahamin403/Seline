from PIL import Image, ImageDraw, ImageFont

W, H = 1700, 980
img = Image.new('RGB', (W, H), (10, 12, 16))
d = ImageDraw.Draw(img)

# Seline-aligned palette
bg = (10, 12, 16)
panel = (16, 19, 25)
card = (22, 26, 33)
card2 = (28, 33, 42)
border = (49, 57, 70)
text = (236, 240, 247)
muted = (150, 160, 176)
accent = (113, 198, 250)
active = (95, 220, 135)
track = (61, 72, 88)


def load_font(size):
    paths = [
        '/System/Library/Fonts/SFNSDisplay.ttf',
        '/System/Library/Fonts/Supplemental/Arial.ttf'
    ]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            pass
    return ImageFont.load_default()


f_title = load_font(40)
f_sub = load_font(20)
f_h = load_font(30)
f_b = load_font(19)
f_sm = load_font(15)
f_xs = load_font(12)


def rr(xy, r=18, fill=None, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def top_label(x, y, label, value):
    d.text((x, y), label, fill=muted, font=f_xs)
    d.text((x, y + 20), value, fill=text, font=f_sm)


# Header

d.text((42, 28), 'Home Location Card Redesign (Horizontal Scroll Preserved)', fill=text, font=f_title)
d.text((42, 78), 'Updated concept: keep existing horizontal location cards exactly as interaction pattern, modernize top hierarchy only', fill=muted, font=f_sub)

# Phone shell
x0, y0 = 120, 130
pw, ph = 560, 820
rr((x0, y0, x0 + pw, y0 + ph), r=42, fill=panel, outline=(40, 48, 62), width=2)
rr((x0 + 206, y0 + 18, x0 + 354, y0 + 35), r=9, fill=(5, 7, 9))

# Card
cx, cy, cw, ch = x0 + 26, y0 + 72, 508, 720
rr((cx, cy, cx + cw, cy + ch), r=28, fill=card, outline=border, width=1)

# Top section (modernized)
for i in range(6):
    inset = i * 2
    rr((cx + 14 + inset, cy + 14 + inset, cx + cw - 14 - inset, cy + 202 - inset), r=20, fill=(32, 54, 74), outline=None)

d.text((cx + 22, cy + 24), 'LOCATION', fill=(172, 184, 203), font=f_xs)
rr((cx + cw - 118, cy + 18, cx + cw - 24, cy + 46), r=14, fill=card2, outline=(83, 111, 139), width=1)
d.text((cx + cw - 71, cy + 32), 'ACTIVE', fill=accent, font=f_xs, anchor='mm')

d.text((cx + 22, cy + 62), 'Home', fill=text, font=load_font(38))
d.text((cx + 22, cy + 109), 'Inside geofence  •  1h 57m', fill=active, font=f_sm)

# quick metrics
rr((cx + 18, cy + 230, cx + 160, cy + 290), r=14, fill=card2, outline=border, width=1)
rr((cx + 170, cy + 230, cx + 332, cy + 290), r=14, fill=card2, outline=border, width=1)
rr((cx + 342, cy + 230, cx + cw - 18, cy + 290), r=14, fill=card2, outline=border, width=1)
top_label(cx + 30, cy + 242, 'Today', '4 places')
top_label(cx + 182, cy + 242, 'Longest', 'Home 5h 41m')
top_label(cx + 354, cy + 242, 'Distance', '1.2 km')

# Active now strip
rr((cx + 18, cy + 314, cx + cw - 18, cy + 376), r=16, fill=card2, outline=border, width=1)
d.text((cx + 34, cy + 333), 'Now at Home', fill=text, font=f_b)
d.text((cx + cw - 34, cy + 333), '1h 57m', fill=active, font=f_sm, anchor='rm')
rr((cx + 34, cy + 355, cx + cw - 34, cy + 362), r=4, fill=track)
rr((cx + 34, cy + 355, cx + cw - 34 - 80, cy + 362), r=4, fill=active)

# Keep horizontal cards section (explicitly preserved)
d.text((cx + 22, cy + 404), 'TODAY (Horizontal scroll - kept)', fill=(172, 184, 203), font=f_xs)

# left fade to imply offscreen previous
rr((cx + 18, cy + 426, cx + 34, cy + 618), r=8, fill=(24, 29, 37), outline=None)

cards = [
    ('Home', '1h 57m', 1.0, True),
    ('Chipotle', '24m', 0.36, False),
    ('GoodLife Gym', '53m', 0.58, False),
    ('RBC Office', '1h 11m', 0.74, False),
]

start_x = cx + 38
card_w = 162
gap = 10
for i, (name, dur, p, is_active) in enumerate(cards):
    x = start_x + i * (card_w + gap)
    y = cy + 428
    rr((x, y, x + card_w, y + 190), r=16, fill=card2, outline=border, width=1)

    # status dot
    rr((x + 14, y + 16, x + 22, y + 24), r=4, fill=active if is_active else (128, 141, 162))
    d.text((x + 30, y + 18), name, fill=text, font=f_sm, anchor='lm')
    d.text((x + 14, y + 48), dur, fill=active if is_active else muted, font=f_sm)

    rr((x + 14, y + 72, x + card_w - 14, y + 80), r=4, fill=track)
    rr((x + 14, y + 72, x + 14 + int((card_w - 28) * p), y + 80), r=4, fill=active if is_active else accent)

    d.text((x + 14, y + 105), 'Tap for place details', fill=muted, font=f_xs)

# right fade + arrow to imply more horizontal cards
rr((cx + cw - 34, cy + 426, cx + cw - 18, cy + 618), r=8, fill=(24, 29, 37), outline=None)
rr((cx + cw - 62, cy + 508, cx + cw - 32, cy + 538), r=15, fill=(34, 43, 56), outline=(75, 90, 110), width=1)
d.text((cx + cw - 47, cy + 522), '>', fill=accent, font=f_sm, anchor='mm')

# Bottom action
d.text((cx + 22, cy + 646), 'Pattern retained: same horizontal location cards + same tap behavior', fill=muted, font=f_xs)
rr((cx + 18, cy + 666, cx + cw - 18, cy + 706), r=12, fill=(25, 41, 57), outline=(66, 86, 108), width=1)
d.text((cx + cw / 2, cy + 686), 'Open Full Location Timeline', fill=(199, 224, 247), font=f_sm, anchor='mm')

# Right side notes panel
nx, ny, nw, nh = 760, 200, 860, 640
rr((nx, ny, nx + nw, ny + nh), r=22, fill=card, outline=border, width=1)
d.text((nx + 26, ny + 24), 'What changed vs current', fill=text, font=f_h)

notes = [
    '1. Keeps your current horizontal scroll cards for all locations.',
    '2. Top area is redesigned with clearer hierarchy + active context.',
    '3. Added compact metric row to make card feel more premium.',
    '4. Active location strip improves glanceability before scrolling.',
    '5. No change to interaction model for location chips/cards.'
]

y = ny + 82
for n in notes:
    d.text((nx + 30, y), n, fill=muted, font=f_sm)
    y += 38

# Tiny before/after lane sketches
d.text((nx + 26, ny + 300), 'Horizontal Card Lane (preserved)', fill=text, font=f_b)
rr((nx + 26, ny + 334, nx + nw - 26, ny + 462), r=16, fill=card2, outline=border, width=1)

sx = nx + 42
for nm, dur in [('Home', '1h 57m'), ('Chipotle', '24m'), ('Gym', '53m'), ('Office', '1h 11m')]:
    rr((sx, ny + 350, sx + 150, ny + 446), r=12, fill=(32, 40, 51), outline=(66, 80, 99), width=1)
    d.text((sx + 12, ny + 372), nm, fill=text, font=f_sm)
    d.text((sx + 12, ny + 398), dur, fill=muted, font=f_xs)
    sx += 160

rr((nx + nw - 54, ny + 382, nx + nw - 30, ny + 410), r=12, fill=(34, 43, 56), outline=(75, 90, 110), width=1)
d.text((nx + nw - 42, ny + 396), '>', fill=accent, font=f_xs, anchor='mm')

d.text((nx + 26, ny + 500), 'If you approve this direction, I can apply it directly in CurrentLocationCardWidget.swift', fill=(174, 198, 221), font=f_sm)

out = '/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/home_location_card_redesign_horizontal_v2.png'
img.save(out)
print(out)
