from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 2400, 1560
PHONE_W, PHONE_H = 520, 1220
MARGIN_X = 50
MARGIN_Y = 210
GAP_X = 40
GAP_Y = 40


def load_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_REG = "/System/Library/Fonts/Supplemental/Arial.ttf"
f_title = load_font(FONT_BOLD, 44)
f_sub = load_font(FONT_REG, 22)
f_h = load_font(FONT_BOLD, 26)
f_b = load_font(FONT_BOLD, 18)
f_m = load_font(FONT_REG, 16)
f_s = load_font(FONT_REG, 14)
f_xs = load_font(FONT_REG, 12)

BG = "#f3f0ec"
PANEL = "#fbfaf8"
PANEL2 = "#f7f4f1"
BORDER = "#ddd7d1"
TEXT = "#181715"
MUTED = "#6f6b66"
ACCENT = "#ee9d69"
ACCENT_SOFT = "#f5d6bc"
WHITE = "#ffffff"


def canvas():
    img = Image.new("RGBA", (W, H), BG)
    base = Image.new("RGBA", (W, H), BG)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((180, 60, 650, 530), fill=(255, 255, 255, 180))
    gd.ellipse((1810, 40, 2140, 370), fill=(238, 157, 105, 40))
    gd.ellipse((1540, 1180, 2050, 1500), fill=(255, 255, 255, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(32))
    base.alpha_composite(glow)
    return base


def lowfi_canvas():
    img = Image.new("RGBA", (W, H), "#faf9f7")
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((1720, 70, 1980, 330), fill=(238, 157, 105, 26))
    gd.ellipse((200, 80, 580, 420), fill=(255, 255, 255, 155))
    glow = glow.filter(ImageFilter.GaussianBlur(24))
    img.alpha_composite(glow)
    return img


def rounded(draw, box, radius=28, fill=PANEL, outline=BORDER, width=2):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def phone_shell(draw, x, y, label, fill="#f7f4f1"):
    rounded(draw, (x, y, x + PHONE_W, y + PHONE_H), 54, fill, "#d8d2cb", 3)
    draw.rounded_rectangle((x + 188, y + 16, x + PHONE_W - 188, y + 50), radius=16, fill="#e8e1da")
    draw.text((x + 28, y + 76), label, font=f_h, fill=TEXT)


def pill(draw, box, text, selected=False, icon=None):
    fill = TEXT if selected else WHITE
    fg = WHITE if selected else MUTED
    rounded(draw, box, 18, fill, None, 0)
    if icon:
        draw.text((box[0] + 12, box[1] + 10), icon, font=f_s, fill=fg)
        draw.text((box[0] + 30, box[1] + 9), text, font=f_s, fill=fg)
    else:
        tw = draw.textlength(text, font=f_s)
        draw.text((box[0] + ((box[2] - box[0]) - tw) / 2, box[1] + 9), text, font=f_s, fill=fg)


def stat_tile(draw, x, y, title, value):
    rounded(draw, (x, y, x + 140, y + 94), 22, WHITE, "#e3ddd6", 1)
    draw.text((x + 14, y + 16), title, font=f_xs, fill=MUTED)
    draw.text((x + 14, y + 44), value, font=f_h, fill=TEXT)


def list_card(draw, x, y, w, title, subtitle, tag, trailing):
    rounded(draw, (x, y, x + w, y + 92), 22, WHITE, "#e6dfd8", 1)
    draw.ellipse((x + 16, y + 22, x + 56, y + 62), fill="#8b96a4")
    draw.text((x + 70, y + 18), title, font=f_b, fill=TEXT)
    draw.text((x + 70, y + 42), subtitle, font=f_m, fill=MUTED)
    rounded(draw, (x + 70, y + 62, x + 132, y + 82), 10, "#f1ece7", "#e6dfd8", 1)
    draw.text((x + 84, y + 67), tag, font=f_xs, fill="#6a655f")
    draw.text((x + w - 46, y + 18), trailing, font=f_xs, fill=MUTED)


def draw_lowfi_sheet():
    img = lowfi_canvas()
    d = ImageDraw.Draw(img)
    d.text((MARGIN_X, 50), "Email Tab Redesign Mockups", font=f_title, fill=TEXT)
    d.text((MARGIN_X, 104), "Low-fi structure pass: Inbox, Sent, Calendar, and Drawer with the new overview-first UX.", font=f_sub, fill=MUTED)

    positions = [
        (MARGIN_X, MARGIN_Y, "Inbox"),
        (MARGIN_X + PHONE_W + GAP_X, MARGIN_Y, "Sent"),
        (MARGIN_X + (PHONE_W + GAP_X) * 2, MARGIN_Y, "Calendar"),
        (MARGIN_X + (PHONE_W + GAP_X) * 3, MARGIN_Y, "Folders"),
    ]

    for x, y, label in positions:
        phone_shell(d, x, y, label)

    x, y, _ = positions[0]
    rounded(d, (x + 24, y + 120, x + PHONE_W - 24, y + 182), 24, WHITE, BORDER, 1)
    pill(d, (x + 98, y + 134, x + 190, y + 168), "Inbox", True)
    pill(d, (x + 196, y + 134, x + 278, y + 168), "Sent")
    pill(d, (x + 284, y + 134, x + 404, y + 168), "Calendar")
    rounded(d, (x + 24, y + 204, x + PHONE_W - 24, y + 362), 26, PANEL2, BORDER, 1)
    d.text((x + 42, y + 226), "Inbox", font=f_title, fill=TEXT)
    d.text((x + 42, y + 284), "18 unread   4 action   9 today", font=f_b, fill=MUTED)
    pill(d, (x + 42, y + 310, x + 148, y + 344), "Focus", True)
    pill(d, (x + 158, y + 310, x + 274, y + 344), "Updates")
    pill(d, (x + 284, y + 310, x + 420, y + 344), "Receipts")
    rounded(d, (x + 24, y + 378, x + PHONE_W - 24, y + 428), 22, WHITE, BORDER, 1)
    for i, title in enumerate(["All", "Primary", "Promotions", "Updates"]):
        pill(d, (x + 36 + i * 110, y + 388, x + 124 + i * 110, y + 420), title, i == 0)
    list_card(d, x + 24, y + 448, PHONE_W - 48, "RBC Royal Bank", "Interac e-Transfer accepted", "Action", "7:56")
    list_card(d, x + 24, y + 550, PHONE_W - 48, "Airbnb", "Trip update and itinerary", "FYI", "2:15")
    rounded(d, (x + 24, y + 664, x + PHONE_W - 24, y + 856), 26, PANEL2, BORDER, 1)
    d.text((x + 42, y + 688), "Older days", font=f_h, fill=TEXT)
    d.text((x + 42, y + 726), "Yesterday and earlier stay grouped below", font=f_m, fill=MUTED)

    x, y, _ = positions[1]
    rounded(d, (x + 24, y + 120, x + PHONE_W - 24, y + 182), 24, WHITE, BORDER, 1)
    pill(d, (x + 98, y + 134, x + 190, y + 168), "Inbox")
    pill(d, (x + 196, y + 134, x + 278, y + 168), "Sent", True)
    pill(d, (x + 284, y + 134, x + 404, y + 168), "Calendar")
    rounded(d, (x + 24, y + 204, x + PHONE_W - 24, y + 362), 26, PANEL2, BORDER, 1)
    d.text((x + 42, y + 226), "Sent", font=f_title, fill=TEXT)
    d.text((x + 42, y + 284), "6 today   21 this week   3 waiting", font=f_b, fill=MUTED)
    for i, title in enumerate(["All", "Today", "This Week", "Awaiting"]):
        pill(d, (x + 42 + i * 100, y + 310, x + 126 + i * 100, y + 344), title, i == 0)
    list_card(d, x + 24, y + 448, PHONE_W - 48, "To: Alex", "Re: Contract draft", "Attachment", "9:12")
    list_card(d, x + 24, y + 550, PHONE_W - 48, "To: Mom", "Dinner plans", "Sent", "8:41")

    x, y, _ = positions[2]
    rounded(d, (x + 24, y + 120, x + PHONE_W - 24, y + 182), 24, WHITE, BORDER, 1)
    pill(d, (x + 98, y + 134, x + 190, y + 168), "Inbox")
    pill(d, (x + 196, y + 134, x + 278, y + 168), "Sent")
    pill(d, (x + 284, y + 134, x + 404, y + 168), "Calendar", True)
    rounded(d, (x + 24, y + 204, x + PHONE_W - 24, y + 360), 26, PANEL2, BORDER, 1)
    d.text((x + 42, y + 226), "Calendar", font=f_title, fill=TEXT)
    d.text((x + 42, y + 284), "Thu, Mar 1   6 events   2 synced", font=f_b, fill=MUTED)
    pill(d, (x + 340, y + 226, x + 412, y + 260), "Add", True)
    pill(d, (x + 420, y + 226, x + 492, y + 260), "Import")
    rounded(d, (x + 24, y + 378, x + PHONE_W - 24, y + 430), 22, WHITE, BORDER, 1)
    for i, title in enumerate(["All", "Personal", "Sync", "Work"]):
        pill(d, (x + 36 + i * 110, y + 388, x + 124 + i * 110, y + 420), title, i == 0)
    rounded(d, (x + 24, y + 448, x + PHONE_W - 24, y + 756), 26, WHITE, BORDER, 1)
    d.text((x + 42, y + 472), "March 2026", font=f_h, fill=TEXT)
    for row in range(5):
        for col in range(7):
            xx = x + 42 + col * 64
            yy = y + 526 + row * 42
            rounded(d, (xx, yy, xx + 48, yy + 32), 10, "#f5f1ed", "#e6dfd8", 1)
            if row == 2 and col == 4:
                rounded(d, (xx, yy, xx + 48, yy + 32), 10, ACCENT, None, 0)
            label = str(row * 7 + col + 1)
            d.text((xx + 17, yy + 8), label, font=f_xs, fill=WHITE if row == 2 and col == 4 else MUTED)
    rounded(d, (x + 24, y + 780, x + PHONE_W - 24, y + 1036), 26, PANEL2, BORDER, 1)
    d.text((x + 42, y + 804), "Agenda", font=f_h, fill=TEXT)
    d.text((x + 42, y + 842), "11:30  Team standup", font=f_b, fill=TEXT)
    d.text((x + 42, y + 872), "2:00   Dentist reminder", font=f_b, fill=TEXT)
    d.text((x + 42, y + 902), "6:45   Flight check-in opens", font=f_b, fill=TEXT)

    x, y, _ = positions[3]
    rounded(d, (x + 24, y + 120, x + PHONE_W - 24, y + 182), 24, WHITE, BORDER, 1)
    pill(d, (x + 40, y + 134, x + 316, y + 168), "Search folders")
    pill(d, (x + 328, y + 134, x + 436, y + 168), "+ Folder", True)
    rounded(d, (x + 24, y + 204, x + PHONE_W - 24, y + 336), 26, PANEL2, BORDER, 1)
    d.text((x + 42, y + 226), "Folders", font=f_title, fill=TEXT)
    d.text((x + 42, y + 282), "12 total   5 custom   7 imported", font=f_b, fill=MUTED)
    for i, section in enumerate(["Custom", "Imported"]):
        yy = y + 368 + i * 264
        d.text((x + 42, yy), section.upper(), font=f_b, fill=MUTED)
        rounded(d, (x + 24, yy + 22, x + PHONE_W - 24, yy + 194), 24, WHITE, BORDER, 1)
        draw_folder_rows(d, x + 40, yy + 42)

    out = "/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/email_glass_redesign_lowfi.png"
    img.convert("RGB").save(out)
    return out


def draw_folder_rows(draw, x, y):
    rows = [("Travel", "12"), ("Work", "36"), ("Receipts", "130")]
    for i, (name, count) in enumerate(rows):
        yy = y + i * 44
        draw.ellipse((x, yy + 9, x + 8, yy + 17), fill=ACCENT_SOFT if i == 2 else "#d7d1cb")
        draw.text((x + 20, yy), name, font=f_m, fill=TEXT)
        draw.text((x + 350, yy), count, font=f_m, fill=MUTED)


def glass_card(img, box, title=None, subtitle=None, accent=False):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    fill = (255, 255, 255, 178)
    d.rounded_rectangle(box, radius=28, fill=fill, outline=(218, 211, 203, 255), width=2)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    if accent:
        gd.ellipse((box[2] - 150, box[1] - 26, box[2] + 50, box[1] + 174), fill=(238, 157, 105, 55))
    gd.ellipse((box[0] - 26, box[1] + 50, box[0] + 190, box[1] + 270), fill=(255, 255, 255, 80))
    glow = glow.filter(ImageFilter.GaussianBlur(12))
    layer.alpha_composite(glow)
    img.alpha_composite(layer)
    d = ImageDraw.Draw(img)
    if title:
        d.text((box[0] + 18, box[1] + 18), title, font=f_h, fill=TEXT)
    if subtitle:
        d.text((box[0] + 18, box[1] + 52), subtitle, font=f_m, fill=MUTED)


def hi_metric(draw, x, y, title, value):
    rounded(draw, (x, y, x + 138, y + 88), 22, (255, 255, 255, 205), "#e0d9d2", 1)
    draw.text((x + 14, y + 14), title, font=f_xs, fill=MUTED)
    draw.text((x + 14, y + 42), value, font=f_h, fill=TEXT)


def hi_chip(draw, box, text, selected=False):
    fill = TEXT if selected else (255, 255, 255, 192)
    fg = WHITE if selected else TEXT
    rounded(draw, box, 18, fill, "#e0d9d2" if not selected else None, 1 if not selected else 0)
    tw = draw.textlength(text, font=f_xs)
    draw.text((box[0] + ((box[2] - box[0]) - tw) / 2, box[1] + 10), text, font=f_xs, fill=fg)


def hi_email_card(draw, x, y, w, sender, subject, tag, time):
    rounded(draw, (x, y, x + w, y + 104), 22, (255, 255, 255, 198), "#e3ddd6", 1)
    draw.ellipse((x + 16, y + 18, x + 58, y + 60), fill="#9199a5")
    draw.text((x + 72, y + 18), sender, font=f_b, fill=TEXT)
    draw.text((x + 72, y + 44), subject, font=f_m, fill=MUTED)
    hi_chip(draw, (x + 72, y + 70, x + 146, y + 94), tag, False)
    draw.text((x + w - 44, y + 18), time, font=f_xs, fill=MUTED)


def draw_highfi_sheet():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.text((MARGIN_X, 50), "Email Tab Redesign Mockups", font=f_title, fill=TEXT)
    d.text((MARGIN_X, 104), "High-fi light mode: calmer glass surfaces, reduced orange atmosphere, and overview-first page hierarchy.", font=f_sub, fill=MUTED)

    positions = [
        (MARGIN_X, MARGIN_Y, "Inbox"),
        (MARGIN_X + PHONE_W + GAP_X, MARGIN_Y, "Sent"),
        (MARGIN_X + (PHONE_W + GAP_X) * 2, MARGIN_Y, "Calendar"),
        (MARGIN_X + (PHONE_W + GAP_X) * 3, MARGIN_Y, "Drawer"),
    ]

    for x, y, label in positions:
        phone_shell(d, x, y, label, fill="#f7f2ec")
        glass_card(img, (x + 20, y + 114, x + PHONE_W - 20, y + 186), accent=True)
        hi_chip(d, (x + 100, y + 132, x + 188, y + 164), "Inbox", label == "Inbox")
        hi_chip(d, (x + 194, y + 132, x + 276, y + 164), "Sent", label == "Sent")
        hi_chip(d, (x + 282, y + 132, x + 406, y + 164), "Calendar", label == "Calendar")

    x, y, _ = positions[0]
    glass_card(img, (x + 20, y + 204, x + PHONE_W - 20, y + 384), accent=True)
    d.text((x + 38, y + 226), "Inbox", font=f_title, fill=TEXT)
    d.text((x + 38, y + 282), "18 unread across the latest conversations.", font=f_m, fill=MUTED)
    hi_metric(d, x + 38, y + 312, "Unread", "18")
    hi_metric(d, x + 186, y + 312, "Action", "4")
    hi_metric(d, x + 334, y + 312, "Today", "9")
    glass_card(img, (x + 20, y + 402, x + PHONE_W - 20, y + 488))
    hi_chip(d, (x + 34, y + 420, x + 124, y + 452), "Action", True)
    hi_chip(d, (x + 134, y + 420, x + 238, y + 452), "Updates")
    hi_chip(d, (x + 248, y + 420, x + 368, y + 452), "Receipts")
    glass_card(img, (x + 20, y + 506, x + PHONE_W - 20, y + 568))
    for i, label in enumerate(["All", "Primary", "Promotions", "Updates"]):
        hi_chip(d, (x + 34 + i * 108, y + 522, x + 118 + i * 108, y + 554), label, i == 0)
    glass_card(img, (x + 20, y + 588, x + PHONE_W - 20, y + 952))
    d.text((x + 38, y + 610), "Today", font=f_h, fill=TEXT)
    hi_email_card(d, x + 34, y + 650, PHONE_W - 68, "RBC Royal Bank", "Interac e-Transfer accepted", "Action", "7:56")
    hi_email_card(d, x + 34, y + 764, PHONE_W - 68, "Airbnb", "Trip update and itinerary", "FYI", "2:15")

    x, y, _ = positions[1]
    glass_card(img, (x + 20, y + 204, x + PHONE_W - 20, y + 384), accent=False)
    d.text((x + 38, y + 226), "Sent", font=f_title, fill=TEXT)
    d.text((x + 38, y + 282), "6 messages sent today.", font=f_m, fill=MUTED)
    hi_metric(d, x + 38, y + 312, "Today", "6")
    hi_metric(d, x + 186, y + 312, "This Week", "21")
    hi_metric(d, x + 334, y + 312, "Waiting", "3")
    glass_card(img, (x + 20, y + 402, x + PHONE_W - 20, y + 468))
    for i, label in enumerate(["All", "Today", "This Week", "Awaiting"]):
        hi_chip(d, (x + 32 + i * 116, y + 420, x + 122 + i * 116, y + 452), label, i == 0)
    glass_card(img, (x + 20, y + 488, x + PHONE_W - 20, y + 852))
    d.text((x + 38, y + 510), "Recent Sends", font=f_h, fill=TEXT)
    hi_email_card(d, x + 34, y + 550, PHONE_W - 68, "To: Alex", "Re: Contract draft", "Attachment", "9:12")
    hi_email_card(d, x + 34, y + 664, PHONE_W - 68, "To: Mom", "Dinner plans", "Sent", "8:41")

    x, y, _ = positions[2]
    glass_card(img, (x + 20, y + 204, x + PHONE_W - 20, y + 384), accent=True)
    d.text((x + 38, y + 226), "Calendar", font=f_title, fill=TEXT)
    d.text((x + 38, y + 282), "Sunday, March 1", font=f_m, fill=MUTED)
    hi_metric(d, x + 38, y + 312, "Today", "6")
    hi_metric(d, x + 186, y + 312, "Synced", "2")
    hi_metric(d, x + 334, y + 312, "Quick", "2")
    glass_card(img, (x + 20, y + 402, x + PHONE_W - 20, y + 468))
    for i, label in enumerate(["All", "Personal", "Sync", "Work"]):
        hi_chip(d, (x + 32 + i * 110, y + 420, x + 118 + i * 110, y + 452), label, i == 0)
    glass_card(img, (x + 20, y + 488, x + PHONE_W - 20, y + 818))
    d.text((x + 38, y + 510), "March 2026", font=f_h, fill=TEXT)
    for row in range(5):
        for col in range(7):
            xx = x + 40 + col * 64
            yy = y + 556 + row * 46
            rounded(d, (xx, yy, xx + 50, yy + 36), 12, (255, 255, 255, 190), "#e4ddd7", 1)
            if row == 2 and col == 4:
                rounded(d, (xx, yy, xx + 50, yy + 36), 12, TEXT, None, 0)
            d.text((xx + 18, yy + 10), str(row * 7 + col + 1), font=f_xs, fill=WHITE if row == 2 and col == 4 else MUTED)
    glass_card(img, (x + 20, y + 838, x + PHONE_W - 20, y + 1074))
    d.text((x + 38, y + 860), "Agenda", font=f_h, fill=TEXT)
    d.text((x + 38, y + 902), "11:30  Team standup", font=f_b, fill=TEXT)
    d.text((x + 38, y + 934), "2:00   Dentist reminder", font=f_b, fill=TEXT)
    d.text((x + 38, y + 966), "6:45   Flight check-in opens", font=f_b, fill=TEXT)

    x, y, _ = positions[3]
    glass_card(img, (x + 20, y + 204, x + PHONE_W - 20, y + 360), accent=False)
    d.text((x + 38, y + 226), "Folders", font=f_title, fill=TEXT)
    d.text((x + 38, y + 282), "12 saved folders across custom and imported labels.", font=f_m, fill=MUTED)
    hi_metric(d, x + 38, y + 312, "Custom", "5")
    hi_metric(d, x + 186, y + 312, "Imported", "7")
    glass_card(img, (x + 20, y + 382, x + PHONE_W - 20, y + 712))
    d.text((x + 38, y + 406), "CUSTOM", font=f_b, fill=MUTED)
    draw_folder_rows(d, x + 40, y + 444)
    d.text((x + 38, y + 580), "IMPORTED", font=f_b, fill=MUTED)
    draw_folder_rows(d, x + 40, y + 618)

    out = "/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/email_glass_redesign_highfi.png"
    img.convert("RGB").save(out)
    return out


if __name__ == "__main__":
    low = draw_lowfi_sheet()
    high = draw_highfi_sheet()
    print(low)
    print(high)
