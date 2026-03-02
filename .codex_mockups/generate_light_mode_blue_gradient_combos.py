from PIL import Image, ImageDraw, ImageFont

W, H = 1800, 1280
img = Image.new('RGB', (W, H), (245, 248, 253))
d = ImageDraw.Draw(img)


def font(size, bold=False):
    candidates = [
        '/System/Library/Fonts/SFNSDisplay.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf' if bold else '/System/Library/Fonts/Supplemental/Arial.ttf',
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            continue
    return ImageFont.load_default()


def rounded(xy, radius=20, fill=None, outline=None, width=1):
    d.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def hex_to_rgb(value):
    value = value.lstrip('#')
    return tuple(int(value[i:i+2], 16) for i in (0, 2, 4))


def gradient_rect(x, y, w, h, c1, c2, radius=22, border=(196, 208, 225)):
    layer = Image.new('RGB', (w, h), c1)
    ld = ImageDraw.Draw(layer)

    for i in range(h):
        t = i / max(h - 1, 1)
        row = (
            int(c1[0] * (1 - t) + c2[0] * t),
            int(c1[1] * (1 - t) + c2[1] * t),
            int(c1[2] * (1 - t) + c2[2] * t),
        )
        ld.line((0, i, w, i), fill=row)

    mask = Image.new('L', (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)

    img.paste(layer, (x, y), mask)
    rounded((x, y, x + w, y + h), radius=radius, fill=None, outline=border, width=1)


ftitle = font(58, True)
fsub = font(24)
fh = font(34, True)
flabel = font(20, True)
fb = font(17)
fs = font(15)

# Header
d.text((56, 42), 'Light Mode Blue Gradient Options', fill=(28, 37, 53), font=ftitle)
d.text((56, 118), 'Cleaner, softer alternatives for Spending + Location hero cards', fill=(91, 108, 131), font=fsub)

options = [
    ("A. Soft Sky", "#EAF4FF", "#DCEBFF"),
    ("B. Mist Blue", "#E7F1FA", "#D5E7F8"),
    ("C. Steel Mist", "#DFEAF5", "#CCDDEF"),
    ("D. Ice Teal", "#E5F4F5", "#D2EAEE"),
    ("E. Slate Air", "#E3ECF4", "#D2E0EE"),
    ("F. Powder Blue", "#E6F0FC", "#D8E6FA"),
]

left = 56
top = 190
col_gap = 34
row_gap = 28
card_w = (W - left * 2 - col_gap) // 2
card_h = 320

for idx, (name, c1h, c2h) in enumerate(options):
    row = idx // 2
    col = idx % 2
    x = left + col * (card_w + col_gap)
    y = top + row * (card_h + row_gap)

    rounded((x, y, x + card_w, y + card_h), radius=26, fill=(253, 254, 255), outline=(220, 229, 240), width=1)

    d.text((x + 24, y + 18), name, fill=(39, 49, 67), font=flabel)
    d.text((x + 24, y + 50), f'{c1h} -> {c2h}', fill=(109, 124, 146), font=fs)

    c1 = hex_to_rgb(c1h)
    c2 = hex_to_rgb(c2h)

    # Spending hero sample
    hero_x = x + 24
    hero_y = y + 84
    hero_w = card_w - 48
    hero_h = 96
    gradient_rect(hero_x, hero_y, hero_w, hero_h, c1, c2, radius=16)
    d.text((hero_x + 14, hero_y + 12), 'SPENDING', fill=(67, 88, 114), font=fs)
    d.text((hero_x + 14, hero_y + 36), 'This Month  $1,438', fill=(25, 36, 54), font=fb)

    # Location hero sample
    loc_y = hero_y + 112
    gradient_rect(hero_x, loc_y, hero_w, hero_h, c1, c2, radius=16)
    d.text((hero_x + 14, loc_y + 12), 'LOCATION', fill=(67, 88, 114), font=fs)
    d.text((hero_x + 14, loc_y + 36), 'Home  1h 47m', fill=(25, 36, 54), font=fb)

# Recommendation bar
rounded((56, H - 110, W - 56, H - 52), radius=14, fill=(235, 242, 251), outline=(204, 218, 236), width=1)
d.text((72, H - 92), 'Recommended direction: B (Mist Blue) or E (Slate Air) for the most neutral premium look.', fill=(56, 75, 101), font=fb)

out = '/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/light_mode_blue_gradient_combos.png'
img.save(out)
print(out)
