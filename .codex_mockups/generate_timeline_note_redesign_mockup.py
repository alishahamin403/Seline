from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

W, H = 2600, 1700
img = Image.new("RGB", (W, H), "#08090b")
draw = ImageDraw.Draw(img)

# Subtle background glow
for cx, cy, r, color in [
    (420, 260, 520, (28, 42, 66, 110)),
    (2200, 380, 600, (19, 49, 56, 110)),
    (1300, 1500, 700, (36, 28, 54, 80)),
]:
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((cx-r, cy-r, cx+r, cy+r), fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(80))
    img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    draw = ImageDraw.Draw(img)


def font(size, bold=False):
    candidates = []
    if bold:
        candidates += [
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/SFNS.ttf",
            "/Library/Fonts/Arial Bold.ttf",
        ]
    else:
        candidates += [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/SFNS.ttf",
            "/Library/Fonts/Arial.ttf",
        ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()


def rr(xy, r, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)

# Title
ft_title = font(48, True)
ft_sub = font(24)
draw.text((80, 40), "Timeline + Visit Note Redesign Mockup", fill="#f2f4f7", font=ft_title)
draw.text((80, 102), "Sleek timeline with calendar context + richer note sub-page", fill="#9aa3b2", font=ft_sub)

phone_w, phone_h = 1080, 1460
left_x, top_y = 80, 180
right_x = left_x + phone_w + 80

# Phone shells
for x in [left_x, right_x]:
    rr((x-8, top_y-8, x+phone_w+8, top_y+phone_h+8), 56, fill="#0e1014", outline="#1d222c", width=2)
    rr((x, top_y, x+phone_w, top_y+phone_h), 50, fill="#090b0f", outline="#262d39", width=1)

# ---------------- LEFT SCREEN ----------------
x = left_x

draw.text((x+40, top_y+30), "7:55", fill="#f6f7fb", font=font(50, True))
draw.text((x+phone_w-190, top_y+30), "91%", fill="#76e28c", font=font(38, True))

# Tabs
rr((x+34, top_y+120, x+phone_w-34, top_y+230), 52, fill="#121722", outline="#283245")
rr((x+phone_w-350, top_y+132, x+phone_w-46, top_y+218), 42, fill="#f2f3f6")
draw.text((x+120, top_y+164), "Locations", fill="#9aa4b5", font=font(42, True))
draw.text((x+440, top_y+164), "People", fill="#9aa4b5", font=font(42, True))
draw.text((x+phone_w-300, top_y+164), "Timeline", fill="#101215", font=font(42, True))

# Calendar card
rr((x+34, top_y+260, x+phone_w-34, top_y+610), 36, fill="#0c1118", outline="#202a38")
draw.text((x+70, top_y+292), "September 2026", fill="#cad1de", font=font(34, True))

days = ["8","9","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24","25","26","27","28"]
start_x = x+95
start_y = top_y+350
col_w = 140
row_h = 92
for i, d in enumerate(days):
    row = i // 7
    col = i % 7
    dx = start_x + col*col_w
    dy = start_y + row*row_h
    if d == "26":
        rr((dx-18, dy-8, dx+54, dy+62), 30, fill="#edf0f6")
        draw.text((dx+6, dy+8), d, fill="#101215", font=font(38, True))
    else:
        draw.text((dx+8, dy+8), d, fill="#dde3ef", font=font(38))
    # small visit marker + tiny summary under each date
    dot = "•" * (1 + (i % 3))
    draw.text((dx+2, dy+50), dot, fill="#818ca0", font=font(24, True))
    if i % 2 == 0:
        draw.text((dx-8, dy+72), "Home 8h" if d=="26" else "Work 2h", fill="#6f7b90", font=font(16))

# Stats row
rr((x+34, top_y+642, x+phone_w-34, top_y+738), 24, fill="#0e1520", outline="#233043")
draw.text((x+70, top_y+672), "4 visits", fill="#e9edf5", font=font(34, True))
draw.text((x+360, top_y+672), "15h 27m", fill="#d1d8e7", font=font(34))
draw.text((x+640, top_y+672), "2 linked receipts", fill="#86b8ff", font=font(30, True))

# Visit cards
card_y = top_y + 768
cards = [
    ("Home", "Reason: Morning routine + planning", "People: Mia, Alex", "Receipt: None", "8h 0m"),
    ("Work", "Reason: Product sprint + interviews", "People: Team (5)", "Receipt: Lunch $18.45", "7h 25m"),
    ("Pizza Hut", "Reason: Dinner stop", "People: Jordan", "Receipt: Order #5839", "42m"),
]
for idx, (name, reason, ppl, rec, dur) in enumerate(cards):
    y1 = card_y + idx*196
    rr((x+56, y1, x+phone_w-56, y1+170), 28, fill="#141a24", outline="#2d3749")
    rr((x+78, y1+30, x+168, y1+120), 18, fill="#eef1f7")
    draw.text((x+104, y1+58), name[:2].upper(), fill="#101215", font=font(42, True))

    draw.text((x+198, y1+30), name, fill="#f3f5fa", font=font(44, True))
    draw.text((x+198, y1+80), reason, fill="#aab4c8", font=font(24))
    draw.text((x+198, y1+108), ppl, fill="#7fa8ff", font=font(22, True))
    draw.text((x+198, y1+134), rec, fill="#96a3ba", font=font(21))

    # right actions: note + duration + delete
    rr((x+phone_w-300, y1+46, x+phone_w-206, y1+122), 18, fill="#202938")
    draw.text((x+phone_w-278, y1+66), "✎", fill="#e6ebf6", font=font(42, True))
    draw.text((x+phone_w-196, y1+76), dur, fill="#d4dbe9", font=font(26, True))
    draw.text((x+phone_w-98, y1+66), "🗑", fill="#ff5f6d", font=font(34))

# bottom nav
for i, label in enumerate(["⌂", "✉", "S", "◔", "•"]):
    draw.text((x+95 + i*190, top_y+phone_h-70), label, fill="#9ea7b9", font=font(40, True))

# ---------------- RIGHT SCREEN ----------------
x = right_x

draw.text((x+40, top_y+30), "Visit Note", fill="#f6f7fb", font=font(50, True))
draw.text((x+40, top_y+84), "Home • Sep 26, 6:15 PM - 8:00 PM", fill="#8f9ab0", font=font(24))
rr((x+phone_w-180, top_y+34, x+phone_w-46, top_y+98), 20, fill="#1b2433")
draw.text((x+phone_w-148, top_y+54), "Save", fill="#d9e2f5", font=font(30, True))

# Reason editor
rr((x+34, top_y+130, x+phone_w-34, top_y+420), 28, fill="#101723", outline="#2a3549")
draw.text((x+62, top_y+162), "Visit reason", fill="#dce4f3", font=font(32, True))
rr((x+62, top_y+210, x+phone_w-62, top_y+392), 18, fill="#0b111a", outline="#243144")
draw.text((x+82, top_y+238), "Discussed Q4 planning and onboarding tasks.", fill="#9fb1cc", font=font(28))
draw.text((x+82, top_y+278), "Captured blockers + next steps for Monday.", fill="#9fb1cc", font=font(28))

# People section
rr((x+34, top_y+444, x+phone_w-34, top_y+760), 28, fill="#101723", outline="#2a3549")
draw.text((x+62, top_y+476), "People connected", fill="#dce4f3", font=font(32, True))
rr((x+62, top_y+526, x+phone_w-62, top_y+588), 20, fill="#0b111a", outline="#2e3d55")
draw.text((x+86, top_y+546), "Search people...", fill="#6f7f97", font=font(26))

# Search results with avatars
for i, (nm, role, col) in enumerate([
    ("Mia Torres", "Product", "#7fa8ff"),
    ("Alex Chen", "Design", "#7bd3b5"),
    ("Jordan Lee", "Ops", "#ff9ea9"),
]):
    y = top_y + 606 + i*46
    rr((x+62, y, x+phone_w-62, y+40), 14, fill="#111a27")
    rr((x+74, y+5, x+104, y+35), 14, fill=col)
    initials = "".join([p[0] for p in nm.split()[:2]])
    draw.text((x+80, y+10), initials, fill="#0a0d12", font=font(16, True))
    draw.text((x+116, y+8), nm, fill="#d6e0f3", font=font(22, True))
    draw.text((x+272, y+9), role, fill="#8ea0bd", font=font(20))
    rr((x+phone_w-130, y+7, x+phone_w-74, y+33), 12, fill="#20314a")
    draw.text((x+phone_w-114, y+10), "Add", fill="#9dc3ff", font=font(18, True))

# Selected people chips
for i, (nm, col) in enumerate([("Mia", "#7fa8ff"), ("Alex", "#7bd3b5")]):
    chip_x = x + 62 + i*120
    rr((chip_x, top_y+724, chip_x+108, top_y+752), 14, fill="#1c2b42")
    rr((chip_x+8, top_y+728, chip_x+28, top_y+748), 10, fill=col)
    draw.text((chip_x+34, top_y+730), nm, fill="#d9e5fa", font=font(18, True))

# Receipt linking
rr((x+34, top_y+786, x+phone_w-34, top_y+1050), 28, fill="#101723", outline="#2a3549")
draw.text((x+62, top_y+818), "Link receipt", fill="#dce4f3", font=font(32, True))
for i, (title, amt, selected) in enumerate([
    ("Pizza Hut - Downtown", "$23.48", True),
    ("Starbucks", "$6.90", False),
    ("Metro Fare", "$3.35", False),
]):
    y = top_y + 860 + i*56
    rr((x+62, y, x+phone_w-62, y+46), 14, fill="#0b111a", outline="#26364e")
    draw.text((x+86, y+12), title, fill="#d7e1f4", font=font(22))
    draw.text((x+phone_w-220, y+12), amt, fill="#99acd0", font=font(22, True))
    if selected:
        rr((x+phone_w-104, y+9, x+phone_w-74, y+37), 8, fill="#6aa1ff")
        draw.text((x+phone_w-96, y+11), "✓", fill="#09101c", font=font(22, True))
    else:
        rr((x+phone_w-104, y+9, x+phone_w-74, y+37), 8, fill="#1f2a3d", outline="#445b7f")

# Calendar + visits under each day
rr((x+34, top_y+1072, x+phone_w-34, top_y+1380), 28, fill="#0f1521", outline="#2a3549")
draw.text((x+62, top_y+1104), "Calendar + Visits", fill="#dce4f3", font=font(30, True))
for i, d in enumerate(["22", "23", "24", "25", "26", "27", "28"]):
    dx = x + 68 + i*138
    rr((dx, top_y+1150, dx+116, top_y+1336), 18, fill="#111a27")
    if d == "26":
        rr((dx+26, top_y+1164, dx+88, top_y+1226), 31, fill="#edf0f6")
        draw.text((dx+46, top_y+1180), d, fill="#111318", font=font(30, True))
    else:
        draw.text((dx+44, top_y+1178), d, fill="#dce3f1", font=font(30))
    visit_line = "Home 8h" if d == "26" else ("Work 7h" if d in ["23","24"] else "-")
    draw.text((dx+18, top_y+1244), visit_line, fill="#7f90aa", font=font(20, True))
    draw.text((dx+18, top_y+1276), "1 visit" if visit_line != "-" else "No visit", fill="#5f6e86", font=font(18))

out = "/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/timeline_note_redesign_mockup_v1.png"
img.save(out)
print(out)
