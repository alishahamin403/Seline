from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1100
img = Image.new("RGB", (W, H), (10, 12, 16))
d = ImageDraw.Draw(img)

# Palette aligned with Seline's grayscale + subtle accent language
bg = (10, 12, 16)
panel = (16, 19, 25)
card = (22, 26, 33)
card2 = (28, 33, 42)
border = (49, 57, 70)
text = (236, 240, 247)
muted = (150, 160, 176)
accent = (116, 202, 255)
accent_soft = (50, 86, 114)
green = (95, 220, 135)

try:
    f_title = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 44)
    f_sub = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 22)
    f_h = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 30)
    f_hero = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 42)
    f_b = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 20)
    f_sm = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 16)
    f_xs = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 13)
except Exception:
    f_title = ImageFont.load_default()
    f_sub = ImageFont.load_default()
    f_h = ImageFont.load_default()
    f_hero = ImageFont.load_default()
    f_b = ImageFont.load_default()
    f_sm = ImageFont.load_default()
    f_xs = ImageFont.load_default()


def rr(xy, r=18, fill=None, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def chip(x, y, w, h, label, selected=False):
    rr((x, y, x + w, y + h), r=h // 2, fill=accent if selected else card2, outline=(85, 120, 149) if selected else border, width=1)
    d.text((x + w / 2, y + h / 2 + 1), label, fill=(11, 14, 20) if selected else muted, font=f_xs, anchor="mm")


def draw_mockup_a(x0, y0):
    # Phone shell
    rr((x0, y0, x0 + 560, y0 + 900), r=42, fill=panel, outline=(40, 48, 62), width=2)
    rr((x0 + 205, y0 + 18, x0 + 355, y0 + 35), r=9, fill=(5, 7, 9))

    d.text((x0 + 28, y0 + 68), "A. Live Focus", fill=text, font=f_h)
    d.text((x0 + 28, y0 + 101), "Hero current place + cleaner hierarchy", fill=muted, font=f_sm)

    # Card
    cx, cy, cw, ch = x0 + 24, y0 + 146, 512, 716
    rr((cx, cy, cx + cw, cy + ch), r=30, fill=card, outline=border, width=1)

    # Glow gradient approximation by layered rounded rects
    for i, alpha in enumerate([40, 32, 24, 16, 10]):
        inset = i * 2
        rr((cx + 12 + inset, cy + 14 + inset, cx + cw - 12 - inset, cy + 205 - inset), r=22, fill=(31, 55, 76), outline=None, width=1)

    d.text((cx + 22, cy + 22), "LOCATION", fill=(176, 188, 206), font=f_xs)
    chip(cx + cw - 126, cy + 18, 104, 28, "ACTIVE", selected=True)

    d.text((cx + 22, cy + 64), "Home", fill=text, font=f_hero)
    d.text((cx + 22, cy + 112), "Inside geofence  •  1h 57m", fill=green, font=f_sm)

    # Quick stats row
    stats = [("Today", "4 places"), ("Longest", "Home 5h 41m"), ("Distance", "1.2 km")]
    sx = cx + 18
    for i, (k, v) in enumerate(stats):
        w = 154 if i == 1 else 146
        rr((sx, cy + 232, sx + w, cy + 292), r=14, fill=card2, outline=border, width=1)
        d.text((sx + 12, cy + 248), k, fill=muted, font=f_xs)
        d.text((sx + 12, cy + 268), v, fill=text, font=f_sm)
        sx += w + 10

    # places list with soft bars
    d.text((cx + 20, cy + 322), "TODAY", fill=(168, 179, 198), font=f_xs)
    rows = [
        ("Home", "1h 57m", 1.0, True),
        ("Chipotle", "24m", 0.32, False),
        ("GoodLife Gym", "53m", 0.52, False),
        ("RBC Office", "1h 11m", 0.68, False),
    ]
    yy = cy + 344
    for name, dur, p, active in rows:
        rr((cx + 18, yy, cx + cw - 18, yy + 78), r=16, fill=card2, outline=border, width=1)
        d.text((cx + 34, yy + 23), name, fill=text, font=f_b)
        d.text((cx + cw - 34, yy + 23), dur, fill=green if active else muted, font=f_sm, anchor="rm")

        rr((cx + 34, yy + 49, cx + cw - 34, yy + 57), r=4, fill=(48, 56, 70))
        rr((cx + 34, yy + 49, cx + 34 + int((cw - 68) * p), yy + 57), r=4, fill=green if active else accent)
        yy += 88


def draw_mockup_b(x0, y0):
    rr((x0, y0, x0 + 560, y0 + 900), r=42, fill=panel, outline=(40, 48, 62), width=2)
    rr((x0 + 205, y0 + 18, x0 + 355, y0 + 35), r=9, fill=(5, 7, 9))

    d.text((x0 + 28, y0 + 68), "B. Timeline Rail", fill=text, font=f_h)
    d.text((x0 + 28, y0 + 101), "More motion + day progression feel", fill=muted, font=f_sm)

    cx, cy, cw, ch = x0 + 24, y0 + 146, 512, 716
    rr((cx, cy, cx + cw, cy + ch), r=30, fill=card, outline=border, width=1)

    d.text((cx + 22, cy + 22), "LOCATION", fill=(176, 188, 206), font=f_xs)
    d.text((cx + 22, cy + 58), "Today", fill=text, font=f_h)
    d.text((cx + 22, cy + 95), "4 places  •  3h 29m tracked", fill=muted, font=f_sm)

    # Segmented filter chips
    chip(cx + 22, cy + 126, 88, 30, "Now", selected=True)
    chip(cx + 116, cy + 126, 82, 30, "Day", selected=False)
    chip(cx + 204, cy + 126, 102, 30, "Week", selected=False)

    # Vertical rail
    rail_x = cx + 52
    d.line((rail_x, cy + 186, rail_x, cy + ch - 34), fill=(66, 79, 97), width=3)

    events = [
        ("8:32 AM", "Home", "1h 57m", True),
        ("11:06 AM", "Chipotle", "24m", False),
        ("2:10 PM", "GoodLife Gym", "53m", False),
        ("5:40 PM", "RBC Office", "1h 11m", False),
    ]
    yy = cy + 188
    for t, name, dur, active in events:
        color = green if active else accent
        rr((rail_x - 8, yy + 8, rail_x + 8, yy + 24), r=8, fill=color)

        rr((cx + 76, yy, cx + cw - 20, yy + 96), r=18, fill=card2, outline=border, width=1)
        d.text((cx + 94, yy + 16), t, fill=muted, font=f_xs)
        d.text((cx + 94, yy + 39), name, fill=text, font=f_b)
        d.text((cx + cw - 38, yy + 39), dur, fill=color, font=f_sm, anchor="rm")

        # tiny activity sparkline
        sx = cx + 94
        sy = yy + 70
        for i, h in enumerate([4, 10, 6, 13, 8, 16, 9, 7]):
            rr((sx + i * 14, sy + 18 - h, sx + i * 14 + 8, sy + 18), r=4, fill=(79, 97, 120))
        yy += 112


def draw_mockup_c(x0, y0):
    rr((x0, y0, x0 + 560, y0 + 900), r=42, fill=panel, outline=(40, 48, 62), width=2)
    rr((x0 + 205, y0 + 18, x0 + 355, y0 + 35), r=9, fill=(5, 7, 9))

    d.text((x0 + 28, y0 + 68), "C. Minimal Grid", fill=text, font=f_h)
    d.text((x0 + 28, y0 + 101), "Compact, cleaner density for home stack", fill=muted, font=f_sm)

    cx, cy, cw, ch = x0 + 24, y0 + 146, 512, 716
    rr((cx, cy, cx + cw, cy + ch), r=30, fill=card, outline=border, width=1)

    # Header row
    d.text((cx + 22, cy + 22), "LOCATION", fill=(176, 188, 206), font=f_xs)
    rr((cx + cw - 114, cy + 16, cx + cw - 22, cy + 44), r=14, fill=card2, outline=border, width=1)
    d.text((cx + cw - 68, cy + 30), "4 places", fill=muted, font=f_xs, anchor="mm")

    d.text((cx + 22, cy + 58), "Home", fill=text, font=f_h)
    d.text((cx + 22, cy + 94), "Current location", fill=muted, font=f_sm)

    # two-column key stats
    blocks = [
        ("Elapsed", "1h 57m"),
        ("Nearest", "1.2 km"),
        ("Last", "Chipotle"),
        ("Visits", "4 today"),
    ]
    bx, by = cx + 22, cy + 126
    for i, (k, v) in enumerate(blocks):
        col = i % 2
        row = i // 2
        x = bx + col * 240
        y = by + row * 78
        rr((x, y, x + 228, y + 66), r=14, fill=card2, outline=border, width=1)
        d.text((x + 12, y + 18), k, fill=muted, font=f_xs)
        d.text((x + 12, y + 40), v, fill=text, font=f_sm)

    # Top places as clean list chips
    d.text((cx + 22, cy + 298), "TOP PLACES", fill=(168, 179, 198), font=f_xs)
    rows = [
        ("Home", "1h 57m", True),
        ("RBC Office", "1h 11m", False),
        ("GoodLife Gym", "53m", False),
        ("Chipotle", "24m", False),
    ]
    yy = cy + 320
    for name, dur, active in rows:
        rr((cx + 20, yy, cx + cw - 20, yy + 62), r=14, fill=card2, outline=border, width=1)
        rr((cx + 34, yy + 25, cx + 42, yy + 33), r=4, fill=green if active else (110, 124, 145))
        d.text((cx + 52, yy + 30), name, fill=text, font=f_sm, anchor="lm")
        d.text((cx + cw - 34, yy + 30), dur, fill=green if active else muted, font=f_sm, anchor="rm")
        yy += 74

    # Footer action row
    rr((cx + 20, cy + ch - 92, cx + cw - 20, cy + ch - 22), r=18, fill=(27, 42, 57), outline=(67, 89, 112), width=1)
    d.text((cx + cw / 2, cy + ch - 57), "Open Full Location Timeline", fill=(203, 226, 247), font=f_b, anchor="mm")


# Title section
d.text((44, 28), "Home Location Card Redesign Concepts", fill=text, font=f_title)
d.text((44, 82), "Goal: modern + sleek, consistent with Seline's neutral cards and subtle accent language", fill=muted, font=f_sub)

# Draw three concepts
draw_mockup_a(48, 130)
draw_mockup_b(678, 130)
draw_mockup_c(1308, 130)

# Footer note
rr((46, 1042, 1872, 1082), r=14, fill=(15, 20, 27), outline=(45, 55, 68), width=1)
d.text((62, 1054), "Recommended direction: A for strongest visual hierarchy on Home; C if you want tighter vertical density.", fill=(172, 188, 208), font=f_sm)

out = "/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/home_location_card_redesign_mockups.png"
img.save(out)
print(out)
