from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

W, H = 1600, 1200
BG = (244, 243, 240)
CARD = (255, 255, 252)
INNER = (242, 240, 235)
BORDER = (225, 221, 214)
TEXT = (18, 18, 18)
MUTED = (110, 108, 103)
ORANGE = (250, 163, 105)
CHIP = (236, 233, 226)
SHADOW = (0, 0, 0, 16)

img = Image.new('RGB', (W, H), BG)
d = ImageDraw.Draw(img)

try:
    title_font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 52)
    h2_font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 28)
    body_font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 24)
    small_font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 20)
    small_bold = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 20)
    metric_font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 40)
except Exception:
    title_font = ImageFont.load_default()
    h2_font = ImageFont.load_default()
    body_font = ImageFont.load_default()
    small_font = ImageFont.load_default()
    small_bold = ImageFont.load_default()
    metric_font = ImageFont.load_default()


def rr(xy, r, fill, outline=None, width=1):
    d.rounded_rectangle(xy, r, fill=fill, outline=outline, width=width)

# Header label
rr((70, 54, 258, 94), 18, fill=(230, 226, 220))
d.text((92, 64), 'Notes Top Card Mockup', font=small_bold, fill=MUTED)

# Main card
card = (70, 120, 1530, 750)
rr(card, 40, fill=CARD, outline=BORDER, width=2)

# Subtle warm accent wash
for i in range(200):
    alpha = max(0, 55 - i // 5)
    x0 = 920 - i * 2
    y0 = 70 - i
    x1 = 1580 + i * 2
    y1 = 500 + i * 2
    overlay = Image.new('RGBA', (W, H), (0,0,0,0))
    od = ImageDraw.Draw(overlay)
    od.ellipse((x0, y0, x1, y1), fill=(250, 163, 105, alpha))
    img = Image.alpha_composite(img.convert('RGBA'), overlay).convert('RGB')
    d = ImageDraw.Draw(img)
rr(card, 40, fill=None, outline=BORDER, width=2)

# Title + actions
left = 112
right = 1488
d.text((left, 168), 'Notes', font=title_font, fill=TEXT)
d.text((left, 232), 'Pinned notes front and center, with search and quick stats in one place.', font=body_font, fill=MUTED)

# Action pills
for idx, (bg, label) in enumerate([((CHIP), 'Filter'), (ORANGE, '+')]):
    size = 58
    x = right - (2-idx) * 76
    y = 160
    rr((x, y, x+size, y+size), 29, fill=bg)
    tw = d.textbbox((0,0), label, font=h2_font)
    tx = x + (size - (tw[2]-tw[0]))/2
    ty = y + (size - (tw[3]-tw[1]))/2 - 2
    d.text((tx, ty), label, font=h2_font, fill=(0,0,0))

# Search bar
search = (112, 292, 1488, 364)
rr(search, 24, fill=INNER, outline=BORDER, width=2)
d.text((140, 314), 'Search notes, reminders, ideas', font=body_font, fill=MUTED)
d.text((1450, 313), '⌕', font=h2_font, fill=MUTED)

# Metric tiles
metrics = [
    ('Pinned', '12'),
    ('Recent 7d', '18'),
    ('Unfiled', '6'),
]
mx = 112
my = 394
mw = 430
mh = 130
gap = 18
for i, (label, value) in enumerate(metrics):
    x0 = mx + i*(mw+gap)
    x1 = x0 + mw
    rr((x0, my, x1, my+mh), 28, fill=INNER)
    d.text((x0+24, my+22), label, font=small_bold, fill=MUTED)
    d.text((x0+24, my+56), value, font=metric_font, fill=TEXT)

# Embedded pinned notes rail
section_y = 558
d.text((112, section_y), 'Pinned Notes', font=h2_font, fill=TEXT)

rail_y = 610
cards = [
    ('Trip ideas', 'Compare Lisbon and Tokyo costs', 'Updated 2h ago'),
    ('Birthday plan', 'Gift, dinner list, reminder', 'Updated yesterday'),
    ('Work sprint', 'Client feedback and next steps', 'Updated 3d ago'),
    ('Reading list', 'Books, essays, podcast notes', 'Updated 5d ago'),
]
card_w = 300
card_h = 110
for i, (title, line, meta) in enumerate(cards):
    x0 = 112 + i*332
    rr((x0, rail_y, x0+card_w, rail_y+card_h), 24, fill=INNER)
    d.text((x0+20, rail_y+18), title, font=small_bold, fill=TEXT)
    d.text((x0+20, rail_y+48), line, font=small_font, fill=MUTED)
    d.text((x0+20, rail_y+78), meta, font=small_font, fill=MUTED)

# Existing page below, simplified
section_top = 790
for idx, title in enumerate(['Pinned', 'Recent', 'March 2026']):
    y = section_top + idx*118
    rr((70, y, 1530, y+92), 28, fill=CARD, outline=BORDER, width=2)
    d.text((110, y+26), title, font=h2_font, fill=TEXT)
    d.text((1450, y+28), '12' if idx==0 else ('18' if idx==1 else '31'), font=small_bold, fill=MUTED)

out = Path('/Users/alishahamin/Desktop/Vibecode/Seline/notes-top-card-mockup.png')
img.save(out)
print(out)
