from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

W, H = 2100, 1260
img = Image.new("RGB", (W, H), "#07090d")
draw = ImageDraw.Draw(img)


def load_font(size, bold=False):
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


def rr(xy, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def add_glow(cx, cy, radius, color, blur=90):
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(blur))
    global img, draw
    img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    draw = ImageDraw.Draw(img)


def text(x, y, value, fill, size, bold=False, anchor=None):
    draw.text((x, y), value, fill=fill, font=load_font(size, bold), anchor=anchor)


def pill(x1, y1, x2, y2, label, fill, fg, outline=None):
    rr((x1, y1, x2, y2), 18, fill=fill, outline=outline, width=1)
    text((x1 + x2) / 2, (y1 + y2) / 2 + 1, label, fg, 20, True, "mm")


def avatar(x, y, label, fill):
    rr((x, y, x + 46, y + 46), 14, fill)
    text(x + 23, y + 24, label, "#0d1118", 18, True, "mm")


def metric_tile(x, y, w, h, label, value):
    rr((x, y, x + w, y + h), 18, "#121826", outline="#20273a")
    text(x + 18, y + 20, label, "#8d96aa", 18)
    text(x + 18, y + 56, value, "#eff3fb", 26, True)


def info_card(x, y, w, h, title, rows, accent_text=None):
    rr((x, y, x + w, y + h), 22, "#0f1420", outline="#20283c")
    text(x + 20, y + 22, title, "#e7edf8", 20, True)
    ry = y + 56
    for row in rows:
        text(x + 22, ry, row, "#9aa4bb", 18)
        ry += 28
    if accent_text:
        text(x + w - 22, y + 22, accent_text, "#ff9d64", 16, True, "ra")


def person_row(x, y, w, name, meta, submeta, avatar_fill, button_label="Open"):
    rr((x, y, x + w, y + 92), 20, "#111826", outline="#20283a")
    avatar(x + 18, y + 23, "".join(part[0] for part in name.split()[:2]), avatar_fill)
    text(x + 80, y + 26, name, "#eef3fb", 23, True)
    text(x + 80, y + 52, meta, "#8c97ac", 17)
    text(x + 80, y + 72, submeta, "#6f7b92", 15)
    pill(x + w - 124, y + 28, x + w - 20, y + 66, button_label, "#1f2738", "#d6ddeb")


def group_card(x, y, w, title, count, names, detail):
    rr((x, y, x + w, y + 116), 22, "#121927", outline="#20283a")
    text(x + 22, y + 24, title, "#eef3fb", 24, True)
    pill(x + 108, y + 12, x + 148, y + 40, str(count), "#1d2535", "#99a4b9")
    text(x + 22, y + 58, names, "#a2acc1", 18)
    text(x + 22, y + 84, detail, "#737f96", 16)
    pill(x + w - 120, y + 38, x + w - 20, y + 76, "Open", "#ff9d64", "#10141c")


def panel_shell(x, y, w, h, title):
    rr((x - 6, y - 6, x + w + 6, y + h + 6), 36, "#0b0f17", outline="#1c2333", width=2)
    rr((x, y, x + w, y + h), 32, "#090d14", outline="#1c2435")
    text(x + 20, y - 24, title, "#d5dcea", 18)


add_glow(260, 220, 320, (39, 53, 83, 120))
add_glow(1830, 280, 360, (41, 84, 73, 110))
add_glow(1120, 1120, 420, (56, 39, 20, 80))

text(68, 44, "Seline People Redesign Concept", "#eff3fb", 42, True)
text(
    68,
    92,
    "Direction: neutral surfaces, tighter hierarchy, action-only accent, and more useful relationship context.",
    "#9aa4bb",
    22,
)

panel_y = 140
panel_w = 640
panel_h = 1030
gap = 40

px1 = 40
px2 = px1 + panel_w + gap
px3 = px2 + panel_w + gap

panel_shell(px1, panel_y, panel_w, panel_h, "Concept 1  ·  Relationship Hub  (Recommended)")
panel_shell(px2, panel_y, panel_w, panel_h, "Concept 2  ·  Priority Feed")
panel_shell(px3, panel_y, panel_w, panel_h, "Concept 3  ·  People + Context")

# Concept 1
rr((px1 + 18, panel_y + 20, px1 + panel_w - 18, panel_y + 86), 22, "#111826", outline="#20283a")
rr((px1 + 34, panel_y + 34, px1 + 82, panel_y + 72), 14, "#1a2233")
pill(px1 + 98, panel_y + 30, px1 + 438, panel_y + 74, "People", "#1a2233", "#d7deed")
pill(px1 + panel_w - 170, panel_y + 30, px1 + panel_w - 34, panel_y + 74, "+ Add", "#ff9d64", "#0f141c")

metric_tile(px1 + 20, panel_y + 108, 186, 96, "Total", "48")
metric_tile(px1 + 226, panel_y + 108, 186, 96, "Favorites", "11")
metric_tile(px1 + 432, panel_y + 108, 188, 96, "Birthdays soon", "3")

rr((px1 + 20, panel_y + 224, px1 + panel_w - 20, panel_y + 344), 22, "#101724", outline="#20283a")
text(px1 + 40, panel_y + 246, "Favorites", "#eaf0fa", 20, True)
for idx, (name, fill) in enumerate([
    ("S", "#7089bf"),
    ("L", "#7f95cc"),
    ("R", "#7388b7"),
    ("M", "#7b8fbd"),
]):
    card_x = px1 + 40 + idx * 142
    rr((card_x, panel_y + 280, card_x + 118, panel_y + 332), 16, "#151d2c")
    avatar(card_x + 12, panel_y + 283, name, fill)
    text(card_x + 66, panel_y + 292, ["Sujus", "Liliana", "Ragulan", "Mom"][idx], "#dbe3f1", 17, True)
    text(card_x + 66, panel_y + 314, ["12 visits", "12 visits", "10 visits", "21 visits"][idx], "#7d879b", 14)

rr((px1 + 20, panel_y + 364, px1 + panel_w - 20, panel_y + 466), 22, "#101724", outline="#20283a")
text(px1 + 40, panel_y + 386, "Attention", "#eaf0fa", 20, True)
text(px1 + 40, panel_y + 420, "Birthday in 4d  ·  Liliana", "#ffb27d", 18, True)
text(px1 + 40, panel_y + 446, "No recent timeline context  ·  Mom", "#9ba6bc", 17)
text(px1 + panel_w - 40, panel_y + 388, "Lightweight, glanceable", "#69768c", 15, anchor="ra")

pill(px1 + 20, panel_y + 490, px1 + 86, panel_y + 526, "All", "#edf1f8", "#10141c")
pill(px1 + 96, panel_y + 490, px1 + 182, panel_y + 526, "Family", "#161d2c", "#cfd7e6")
pill(px1 + 192, panel_y + 490, px1 + 278, panel_y + 526, "Friends", "#161d2c", "#cfd7e6")
pill(px1 + 288, panel_y + 490, px1 + 358, panel_y + 526, "Work", "#161d2c", "#cfd7e6")
pill(px1 + 368, panel_y + 490, px1 + 472, panel_y + 526, "Recently seen", "#161d2c", "#cfd7e6")

group_card(px1 + 20, panel_y + 548, panel_w - 40, "Family", 8, "Mom, Dad, Sister", "Shared places: Home, Saryo, Costco")
group_card(px1 + 20, panel_y + 684, panel_w - 40, "Friends", 14, "Sujus, Liliana, Ragulan", "Strongest signal: coffee, dinner, weekend trips")
group_card(px1 + 20, panel_y + 820, panel_w - 40, "Work", 9, "Manager, Team Lead, Client", "Useful when linking visits or receipts to meetings")

# Concept 2
rr((px2 + 18, panel_y + 20, px2 + panel_w - 18, panel_y + 86), 22, "#111826", outline="#20283a")
rr((px2 + 34, panel_y + 34, px2 + 82, panel_y + 72), 14, "#1a2233")
pill(px2 + 98, panel_y + 30, px2 + 430, panel_y + 74, "Priority People", "#1a2233", "#d7deed")
pill(px2 + panel_w - 170, panel_y + 30, px2 + panel_w - 34, panel_y + 74, "+ Add", "#ff9d64", "#0f141c")

info_card(
    px2 + 20,
    panel_y + 108,
    panel_w - 40,
    122,
    "Needs attention",
    [
        "Birthday soon  ·  Liliana",
        "Gift idea missing  ·  Mom",
        "No recent shared visit  ·  Ragulan",
    ],
    "Utility first",
)

person_row(px2 + 20, panel_y + 252, panel_w - 40, "Sujus", "Close friend  ·  last seen 2d ago", "18 visits  ·  6 shared places", "#7790c7", "Timeline")
person_row(px2 + 20, panel_y + 362, panel_w - 40, "Liliana", "Friend  ·  birthday in 4 days", "12 visits  ·  gift saved", "#8ba1d4", "Open")
person_row(px2 + 20, panel_y + 472, panel_w - 40, "Ragulan", "Work  ·  last seen 11d ago", "10 visits  ·  no recent note", "#7588b6", "Timeline")
person_row(px2 + 20, panel_y + 582, panel_w - 40, "Mom", "Family  ·  last seen today", "21 visits  ·  2 favorite places", "#8398c7", "Open")
person_row(px2 + 20, panel_y + 692, panel_w - 40, "Dad", "Family  ·  last seen yesterday", "17 visits  ·  4 shared places", "#93a6d0", "Open")

rr((px2 + 20, panel_y + 818, px2 + panel_w - 20, panel_y + 976), 22, "#101724", outline="#20283a")
text(px2 + 40, panel_y + 840, "Why this works", "#eaf0fa", 20, True)
text(px2 + 40, panel_y + 878, "Better for retrieval than broad relationship sections.", "#9ba6bc", 17)
text(px2 + 40, panel_y + 906, "Feels modern because the page does one job: surface the next useful person.", "#9ba6bc", 17)
text(px2 + 40, panel_y + 934, "Strong fit if People is used as an action hub, not just a static address book.", "#9ba6bc", 17)

# Concept 3
rr((px3 + 18, panel_y + 20, px3 + panel_w - 18, panel_y + 86), 22, "#111826", outline="#20283a")
rr((px3 + 34, panel_y + 34, px3 + 82, panel_y + 72), 14, "#1a2233")
pill(px3 + 98, panel_y + 30, px3 + 430, panel_y + 74, "People", "#1a2233", "#d7deed")
pill(px3 + panel_w - 170, panel_y + 30, px3 + panel_w - 34, panel_y + 74, "Import", "#1f2738", "#d6ddeb")

rr((px3 + 20, panel_y + 108, px3 + panel_w - 20, panel_y + 236), 22, "#101724", outline="#20283a")
text(px3 + 40, panel_y + 132, "People summary", "#eaf0fa", 20, True)
metric_tile(px3 + 40, panel_y + 156, 164, 62, "Most visited with", "Sujus")
metric_tile(px3 + 220, panel_y + 156, 164, 62, "Shared places", "31")
metric_tile(px3 + 400, panel_y + 156, 180, 62, "New month", "5")

rr((px3 + 20, panel_y + 258, px3 + panel_w - 20, panel_y + 570), 22, "#101724", outline="#20283a")
text(px3 + 40, panel_y + 282, "Relationship groups", "#eaf0fa", 20, True)
group_card(px3 + 40, panel_y + 314, panel_w - 80, "Family", 8, "Mom, Dad, Sister", "Shortcut into the strongest circle")
group_card(px3 + 40, panel_y + 442, panel_w - 80, "Friends", 14, "Sujus, Liliana, Ragulan", "Useful if you want large-group browsing")

rr((px3 + 20, panel_y + 594, px3 + panel_w - 20, panel_y + 774), 22, "#101724", outline="#20283a")
text(px3 + 40, panel_y + 618, "Connected UX", "#eaf0fa", 20, True)
text(px3 + 40, panel_y + 658, "Tap a person to open a richer detail page.", "#9ba6bc", 17)
text(px3 + 40, panel_y + 688, "From detail, jump directly to timeline-filtered visits.", "#9ba6bc", 17)
text(px3 + 40, panel_y + 718, "Keep receipt and place linking on the same path.", "#9ba6bc", 17)

rr((px3 + 20, panel_y + 798, px3 + panel_w - 20, panel_y + 976), 22, "#101724", outline="#20283a")
text(px3 + 40, panel_y + 822, "Recommendation", "#eaf0fa", 20, True)
text(px3 + 40, panel_y + 860, "Use Concept 1 as the page architecture,", "#9ba6bc", 17)
text(px3 + 40, panel_y + 888, "then borrow the 'Needs attention' strip from Concept 2.", "#9ba6bc", 17)
text(px3 + 40, panel_y + 918, "That keeps the screen sleek without losing utility.", "#9ba6bc", 17)

text(
    68,
    1202,
    "Accent should stay minimal and action-only. Base palette should remain neutral to match the app's current surface tokens.",
    "#7b869c",
    18,
)

out = "/Users/alishahamin/Desktop/Vibecode/Seline/people-redesign-mockups-v3.png"
img.save(out)
print(out)
