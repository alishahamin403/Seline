from PIL import Image, ImageDraw, ImageFont

W, H = 1800, 980
bg = (14, 16, 20)
card = (22, 26, 33)
card2 = (27, 31, 39)
border = (49, 57, 69)
text = (235, 239, 245)
muted = (145, 155, 170)
accent = (232, 236, 244)
accent_text = (15, 18, 22)
chip_idle = (36, 41, 50)
line = (61, 72, 88)

img = Image.new('RGB', (W, H), bg)
d = ImageDraw.Draw(img)

# Fonts
try:
    f_title = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 42)
    f_sub = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 22)
    f_h = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 28)
    f_b = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 20)
    f_sm = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 17)
    f_xs = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 14)
except:
    f_title = ImageFont.load_default()
    f_sub = f_h = f_b = f_sm = f_xs = ImageFont.load_default()


def rr(xy, r=20, fill=None, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def phone(x0, y0, title, selected_tab):
    pw, ph = 540, 860
    rr((x0, y0, x0+pw, y0+ph), r=34, fill=(9, 11, 15), outline=(44, 50, 62), width=2)
    # dynamic island
    rr((x0+205, y0+18, x0+335, y0+34), r=8, fill=(4, 5, 7))

    # header
    rr((x0+22, y0+54, x0+pw-22, y0+136), r=24, fill=card, outline=border, width=2)
    # left button
    rr((x0+36, y0+72, x0+88, y0+118), r=12, fill=chip_idle)
    d.text((x0+56, y0+84), '≡', font=f_b, fill=text, anchor='mm')
    # right search
    rr((x0+pw-88, y0+72, x0+pw-36, y0+118), r=12, fill=chip_idle)
    d.text((x0+pw-62, y0+94), '⌕', font=f_b, fill=text, anchor='mm')

    # tab bar center (same placement)
    rr((x0+108, y0+72, x0+pw-108, y0+118), r=23, fill=(32, 36, 45), outline=(52,58,72), width=1)
    labels = ['Saved', 'People', 'Timeline']
    tx = [x0+168, x0+270, x0+382]
    for lab, cx in zip(labels, tx):
        is_sel = lab == selected_tab
        if is_sel:
            rr((cx-54, y0+76, cx+54, y0+114), r=19, fill=accent)
        d.text((cx, y0+95), lab, font=f_sm, fill=accent_text if is_sel else muted, anchor='mm')

    d.text((x0+30, y0+165), title, font=f_h, fill=text)

    return pw, ph


def stat_pills(x0, y0, labels):
    x = x0
    for l1, l2 in labels:
        rr((x, y0, x+150, y0+78), r=16, fill=card2, outline=(45,52,64), width=1)
        d.text((x+14, y0+17), l1, font=f_xs, fill=muted)
        d.text((x+14, y0+43), l2, font=f_b, fill=text)
        x += 162

# Title
d.text((42, 26), 'Seline Maps Redesign (3 Tabs Restored, Same Placement)', font=f_title, fill=text)
d.text((42, 76), 'Concept: Keep Saved / People / Timeline as primary pages, modernize cards + cross-page drill-down', font=f_sub, fill=muted)

# --- Screen 1: Saved ---
x1, y = 36, 106
pw, ph = phone(x1, y, 'Saved Locations', 'Saved')

# current location
rr((x1+24, y+198, x1+pw-24, y+268), r=18, fill=card, outline=border, width=1)
d.text((x1+40, y+216), 'Current location', font=f_xs, fill=muted)
d.text((x1+40, y+240), 'Home · 3h 42m', font=f_b, fill=(95, 220, 130))
d.text((x1+pw-44, y+236), 'Open', font=f_xs, fill=accent_text, anchor='mm')
rr((x1+pw-86, y+218, x1+pw-26, y+252), r=14, fill=accent)

stat_pills(x1+24, y+282, [('Saved', '32'), ('Favorites', '8'), ('Active today', '4')])

# mini map
rr((x1+24, y+372, x1+pw-24, y+520), r=20, fill=card, outline=border, width=1)
d.text((x1+42, y+392), 'Map Snapshot', font=f_sm, fill=text)
d.text((x1+42, y+416), 'Tap cluster to open folder list', font=f_xs, fill=muted)
# fake map lines
for i in range(6):
    d.line((x1+44+i*70, y+452, x1+72+i*70, y+488), fill=line, width=2)
for px, py in [(x1+130,y+454),(x1+240,y+478),(x1+325,y+440),(x1+420,y+490)]:
    rr((px-8,py-8,px+8,py+8), r=8, fill=(220,80,80))
    rr((px-3,py-3,px+3,py+3), r=3, fill=(250,240,240))

# folders card
rr((x1+24, y+534, x1+pw-24, y+816), r=20, fill=card, outline=border, width=1)
d.text((x1+42, y+554), 'Folders', font=f_sm, fill=text)
for i,(name,count) in enumerate([('Home',11),('Work',7),('Food & Dining',9),('Travel',5)]):
    yy = y+584+i*54
    rr((x1+40, yy, x1+pw-40, yy+42), r=12, fill=card2)
    d.text((x1+54, yy+21), name, font=f_xs, fill=text, anchor='lm')
    d.text((x1+pw-58, yy+21), str(count), font=f_xs, fill=muted, anchor='rm')

# --- Screen 2: People ---
x2 = 630
phone(x2, y, 'People', 'People')
stat_pills(x2+24, y+198, [('People', '46'), ('With visits', '31'), ('New month', '5')])

rr((x2+24, y+288, x2+540-24, y+390), r=20, fill=card, outline=border, width=1)
d.text((x2+42, y+308), 'Frequent Together', font=f_sm, fill=text)
for i,(nm,cnt) in enumerate([('Sujus',18),('Liliana',12),('Ragulan',10)]):
    xx = x2+42+i*160
    rr((xx, y+334, xx+148, y+374), r=12, fill=card2)
    d.text((xx+12,y+348), nm, font=f_xs, fill=text)
    d.text((xx+12,y+364), f'{cnt} visits', font=f_xs, fill=muted)

rr((x2+24, y+406, x2+540-24, y+816), r=20, fill=card, outline=border, width=1)
d.text((x2+42, y+426), 'People List', font=f_sm, fill=text)
# relation groups + rows
rows = [
    ('FAMILY · 8','Mom, Dad, Sister'),
    ('FRIENDS · 14','Sujus, Ragulan, Amaan'),
    ('WORK · 9','Manager, Team Lead'),
    ('OTHER · 15','Dentist, Trainer, Barber')
]
yy = y+454
for g, names in rows:
    d.text((x2+42, yy), g, font=f_xs, fill=muted)
    rr((x2+40, yy+20, x2+500, yy+62), r=12, fill=card2)
    d.text((x2+52, yy+42), names, font=f_xs, fill=text, anchor='lm')
    d.text((x2+486, yy+42), '↗ timeline', font=f_xs, fill=(180,190,205), anchor='rm')
    yy += 92

# --- Screen 3: Timeline ---
x3 = 1224
phone(x3, y, 'Timeline', 'Timeline')

rr((x3+24, y+198, x3+540-24, y+258), r=16, fill=card, outline=border, width=1)
d.text((x3+42, y+218), 'Thursday, Feb 20', font=f_sm, fill=text)
d.text((x3+42, y+240), '6 visits · 5h 24m', font=f_xs, fill=muted)

# mini week strip
rr((x3+24, y+272, x3+540-24, y+328), r=16, fill=card, outline=border, width=1)
for i,day in enumerate(['M 17','T 18','W 19','T 20','F 21','S 22']):
    xx = x3+40+i*79
    sel = (day=='T 20')
    rr((xx, y+284, xx+68, y+316), r=12, fill=accent if sel else chip_idle)
    d.text((xx+34, y+300), day, font=f_xs, fill=accent_text if sel else muted, anchor='mm')

rr((x3+24, y+342, x3+540-24, y+816), r=20, fill=card, outline=border, width=1)
d.text((x3+42, y+362), 'Visits', font=f_sm, fill=text)
visit_rows = [
    ('9:12 AM','Home','with Sujus · note added'),
    ('11:30 AM','RBC Office','with Team · 2h 10m'),
    ('2:05 PM','Mos Mos Coffee','solo · quick stop'),
    ('6:15 PM','GoodLife Gym','with Ragulan · workout')
]
yy = y+390
for t,p,meta in visit_rows:
    rr((x3+40, yy, x3+500, yy+88), r=14, fill=card2)
    d.text((x3+54, yy+18), t, font=f_xs, fill=muted)
    d.text((x3+54, yy+42), p, font=f_b, fill=text)
    d.text((x3+54, yy+64), meta, font=f_xs, fill=muted)
    d.text((x3+486, yy+42), '•••', font=f_sm, fill=muted, anchor='rm')
    yy += 98

# UX connection panel
rr((36, 900, 1764, 964), r=16, fill=(18,22,28), outline=(55,63,77), width=1)
d.text((52, 914), 'Connected UX recommendations: 1) Tap folder in Saved -> auto-filter Timeline to that folder + date chips. 2) Tap person in People -> open Timeline prefiltered to "with this person".', font=f_xs, fill=(185,195,210))
d.text((52, 938), '3) From Timeline visit card: one-tap actions -> Add/Edit notes, Link people, Open place detail. 4) Keep swipe-back on all drill-down pages, but keep these 3 tabs pinned in the same top position.', font=f_xs, fill=(185,195,210))

out = '/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/maps_redesign_3tabs_mockup.png'
img.save(out)
print(out)
