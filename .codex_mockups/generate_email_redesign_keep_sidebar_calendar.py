from PIL import Image, ImageDraw, ImageFont

W, H = 2400, 1550
img = Image.new('RGB', (W, H), '#0a0b0e')
d = ImageDraw.Draw(img)

# Fonts
try:
    f_title = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 42)
    f_sub = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 22)
    f_h = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 26)
    f_b = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 18)
    f_s = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 15)
except:
    f_title = f_sub = f_h = f_b = f_s = ImageFont.load_default()

ORANGE = '#E07850'
WHITE = '#F4F5F7'
MUTED = '#A2A8B3'
CARD = '#151821'
CARD2 = '#1B1F2A'
BORDER = '#2D3340'
BLACK = '#090A0C'

# Header

d.text((56, 36), 'Seline Email Redesign (Keeps Sidebar + Calendar)', fill=WHITE, font=f_title)
d.text((56, 94), 'Updated concept: preserve folder drawer + preserve calendar/events while modernizing hierarchy', fill=MUTED, font=f_sub)


def phone(x, y, w=540, h=1280, label=''):
    d.rounded_rectangle((x, y, x+w, y+h), radius=52, fill='#0f1218', outline='#313748', width=3)
    d.rounded_rectangle((x+190, y+20, x+w-190, y+54), radius=15, fill=BLACK)
    if label:
        d.text((x+24, y+74), label, fill=WHITE, font=f_h)
    return x, y, w, h

# Screen 1 - Hub with persistent sidebar entry + compact insight
x1, y1, w1, h1 = phone(40, 170, label='Email Hub (Primary)')
# top bar
d.rounded_rectangle((x1+24, y1+118, x1+w1-24, y1+182), radius=24, fill=CARD2, outline=BORDER)
# hamburger left
d.rounded_rectangle((x1+36, y1+130, x1+98, y1+170), radius=14, fill='#232938')
d.text((x1+58, y1+140), '≡', fill=WHITE, font=f_b)
# segmented center
d.rounded_rectangle((x1+108, y1+130, x1+382, y1+170), radius=18, fill='#232938')
d.rounded_rectangle((x1+112, y1+134, x1+196, y1+166), radius=14, fill=ORANGE)
d.text((x1+136, y1+142), 'Inbox', fill='white', font=f_s)
d.text((x1+224, y1+142), 'Sent', fill=MUTED, font=f_s)
d.text((x1+288, y1+142), 'Calendar', fill=MUTED, font=f_s)
# search
d.rounded_rectangle((x1+w1-98, y1+130, x1+w1-36, y1+170), radius=14, fill='#232938')
d.text((x1+w1-76, y1+141), '⌕', fill=WHITE, font=f_b)

# insight cards
for i,(title,val) in enumerate([('New','18'),('Priority','4'),('Follow-up','7')]):
    xx=x1+24+i*167
    d.rounded_rectangle((xx, y1+200, xx+155, y1+282), radius=16, fill=CARD, outline=BORDER)
    d.text((xx+12,y1+214),title, fill=MUTED, font=f_s)
    d.text((xx+12,y1+244),val, fill=ORANGE, font=f_h)

# feed cluster
d.text((x1+24, y1+306), 'Inbox Feed', fill=WHITE, font=f_h)
for i,(s,sub) in enumerate([
    ('RBC Royal Bank','Interac e-Transfer accepted'),
    ('Airbnb','Trip update and itinerary'),
    ('Your Lisgar neighbours','Petition update + comments')
]):
    yy=y1+342+i*104
    d.rounded_rectangle((x1+24, yy, x1+w1-24, yy+90), radius=14, fill=CARD2)
    d.ellipse((x1+38, yy+22, x1+74, yy+58), fill='#667086')
    d.text((x1+86, yy+26), s, fill=WHITE, font=f_b)
    d.text((x1+86, yy+54), sub, fill=MUTED, font=f_s)

# CTAs
d.rounded_rectangle((x1+24, y1+676, x1+240, y1+722), radius=18, fill=ORANGE)
d.text((x1+80, y1+689), 'Open Inbox', fill='white', font=f_b)
d.rounded_rectangle((x1+252, y1+676, x1+w1-24, y1+722), radius=18, fill='#262c38')
d.text((x1+320, y1+689), 'Open Calendar', fill=WHITE, font=f_b)

# compose
d.rounded_rectangle((x1+190, y1+h1-96, x1+w1-190, y1+h1-42), radius=26, fill=ORANGE)
d.text((x1+236, y1+h1-80), '+ Compose', fill='white', font=f_b)

# Screen 2 - Sidebar drawer retained
x2, y2, w2, h2 = phone(620, 170, label='Folder Sidebar (Retained)')
# base content darkened
for i in range(5):
    yy = y2+140+i*104
    d.rounded_rectangle((x2+24, yy, x2+w2-24, yy+86), radius=14, fill='#131722')
# overlay dim
# drawer
drawer_w = 365
d.rounded_rectangle((x2, y2, x2+drawer_w, y2+h2), radius=44, fill='#ffffff', outline='#e5e7eb', width=2)
d.rectangle((x2+drawer_w-20, y2, x2+drawer_w+6, y2+h2), fill='#ffffff')
# drawer header
d.rounded_rectangle((x2+18, y2+110, x2+drawer_w-18, y2+176), radius=18, fill='#f3f4f6', outline='#e5e7eb')
d.text((x2+34, y2+132), 'Search folders', fill='#9ca3af', font=f_b)
d.rounded_rectangle((x2+drawer_w-130, y2+120, x2+drawer_w-24, y2+166), radius=16, fill=ORANGE)
d.text((x2+drawer_w-95, y2+132), '+ Folder', fill='white', font=f_s)

d.text((x2+24, y2+216), 'BROWSE', fill='#9aa0aa', font=f_b)
for i,(name,cnt) in enumerate([('Pinned',4),('Unfiled',12),('Receipts',130),('Travel',12),('Work',36)]):
    yy = y2+248+i*82
    fill = '#f4f4f5' if i==0 else '#ffffff'
    d.rounded_rectangle((x2+18, yy, x2+drawer_w-18, yy+66), radius=12, fill=fill)
    d.text((x2+34, yy+22), name, fill='#111827', font=f_b)
    d.text((x2+drawer_w-52, yy+22), str(cnt), fill='#9ca3af', font=f_b)

d.text((x2+24, y2+690), 'FOLDERS', fill='#9aa0aa', font=f_b)
for i,txt in enumerate(['Important','Personal','Finance','Archive']):
    yy = y2+722+i*62
    d.text((x2+34, yy+20), txt, fill='#111827', font=f_b)

# note about hierarchy
d.rounded_rectangle((x2+24, y2+1030, x2+drawer_w-24, y2+1178), radius=14, fill='#f9fafb', outline='#e5e7eb')
d.text((x2+34, y2+1050), 'Behavior', fill='#111827', font=f_h)
d.text((x2+34, y2+1088), '• Drawer stays as fast access', fill='#374151', font=f_s)
d.text((x2+34, y2+1118), '• Opens above content and tabs', fill='#374151', font=f_s)
d.text((x2+34, y2+1148), '• Folder items push to saved list', fill='#374151', font=f_s)

# Screen 3 - Calendar preserved and modernized
x3, y3, w3, h3 = phone(1200, 170, label='Calendar (Retained)')
# top tabs
d.rounded_rectangle((x3+24, y3+118, x3+w3-24, y3+182), radius=24, fill=CARD2, outline=BORDER)
d.rounded_rectangle((x3+112, y3+134, x3+214, y3+166), radius=14, fill='#232938')
d.text((x3+142, y3+142), 'Inbox', fill=MUTED, font=f_s)
d.rounded_rectangle((x3+220, y3+134, x3+320, y3+166), radius=14, fill='#232938')
d.text((x3+254, y3+142), 'Sent', fill=MUTED, font=f_s)
d.rounded_rectangle((x3+326, y3+134, x3+438, y3+166), radius=14, fill=ORANGE)
d.text((x3+356, y3+142), 'Calendar', fill='white', font=f_s)

# month mini grid block
d.rounded_rectangle((x3+24, y3+202, x3+w3-24, y3+530), radius=18, fill=CARD, outline=BORDER)
d.text((x3+42, y3+224), 'February 2026', fill=WHITE, font=f_h)
# simple grid
gx, gy = x3+42, y3+266
for r in range(5):
    for c in range(7):
        xx = gx + c*62
        yy = gy + r*42
        fill = '#202534'
        if (r,c) in [(2,3),(3,1),(3,5)]:
            fill = ORANGE
        d.rounded_rectangle((xx,yy,xx+54,yy+34), radius=8, fill=fill)
        day = r*7+c+1
        if day <= 31:
            col = 'white' if fill==ORANGE else '#c2c7d1'
            d.text((xx+18,yy+9), str(day), fill=col, font=f_s)

# agenda list
d.rounded_rectangle((x3+24, y3+548, x3+w3-24, y3+1048), radius=18, fill=CARD2, outline=BORDER)
d.text((x3+42, y3+570), 'Agenda - Thu, Feb 20', fill=WHITE, font=f_h)
for i,(t,desc) in enumerate([
    ('11:30 AM', 'Team standup (from email invite)'),
    ('2:00 PM', 'Dentist appointment reminder'),
    ('6:45 PM', 'Flight check-in opens')
]):
    yy = y3+610+i*126
    d.rounded_rectangle((x3+42, yy, x3+w3-42, yy+108), radius=14, fill='#232838')
    d.text((x3+58, yy+18), t, fill=ORANGE, font=f_b)
    d.text((x3+58, yy+50), desc, fill=WHITE, font=f_s)
    d.rounded_rectangle((x3+w3-176, yy+28, x3+w3-58, yy+72), radius=16, fill='#2f3544')
    d.text((x3+w3-136, yy+42), 'Open Email', fill=MUTED, font=f_s)

# Screen 4 - Thread detail with swipe-back
x4, y4, w4, h4 = phone(1780, 170, label='Thread Detail + Swipe Back')
# nav bar
d.rounded_rectangle((x4+24, y4+118, x4+w4-24, y4+182), radius=24, fill=CARD2, outline=BORDER)
d.text((x4+44, y4+142), '←', fill=WHITE, font=f_h)
d.text((x4+70, y4+142), 'Back', fill=WHITE, font=f_s)
d.text((x4+224, y4+142), 'RBC Royal Bank', fill=WHITE, font=f_s)

# sender summary
d.rounded_rectangle((x4+24, y4+202, x4+w4-24, y4+292), radius=16, fill=CARD, outline=BORDER)
d.text((x4+42, y4+228), 'Interac e-Transfer accepted', fill=WHITE, font=f_b)
d.text((x4+42, y4+256), 'Today · 7:56 AM', fill=MUTED, font=f_s)

# AI summary card
d.rounded_rectangle((x4+24, y4+308, x4+w4-24, y4+520), radius=16, fill=CARD, outline=BORDER)
d.text((x4+42, y4+330), 'AI Summary', fill=WHITE, font=f_h)
d.text((x4+42, y4+370), '• Transfer confirmed for $240.00', fill=WHITE, font=f_b)
d.text((x4+42, y4+404), '• Deposited to your chequing account', fill=WHITE, font=f_b)
d.text((x4+42, y4+438), '• View transaction details', fill=WHITE, font=f_b)
d.text((x4+260, y4+438), 'Open Receipt', fill=ORANGE, font=f_b)
d.line((x4+260, y4+460, x4+372, y4+460), fill=ORANGE, width=1)

# smart reply row full-width
d.text((x4+42, y4+548), 'Smart Reply', fill=WHITE, font=f_h)
for i,text in enumerate(['Thanks, got it', 'Need confirmation']):
    xx = x4+24 + i*246
    d.rounded_rectangle((xx, y4+586, xx+234, y4+636), radius=16, fill='#2a2f3d')
    tw = d.textlength(text, font=f_s)
    d.text((xx + (234-tw)/2, y4+603), text, fill=WHITE, font=f_s)
for i,text in enumerate(['Can you resend?', 'I will reply later']):
    xx = x4+24 + i*246
    d.rounded_rectangle((xx, y4+644, xx+234, y4+694), radius=16, fill='#2a2f3d')
    tw = d.textlength(text, font=f_s)
    d.text((xx + (234-tw)/2, y4+661), text, fill=WHITE, font=f_s)

# swipe guidance
d.rounded_rectangle((x4+24, y4+732, x4+w4-24, y4+1046), radius=16, fill=CARD2, outline=BORDER)
d.text((x4+42, y4+758), 'Navigation & Gestures', fill=WHITE, font=f_h)
lines = [
    '1. Thread/detail pages are push navigation,',
    '   not bottom sheets.',
    '2. iOS edge-swipe back enabled on detail pages.',
    '3. Sidebar remains a drawer for folder browsing.',
    '4. Calendar remains its own main surface.'
]
for i,l in enumerate(lines):
    d.text((x4+42, y4+804+i*40), l, fill=MUTED, font=f_s)

# footer
d.text((56, 1498), 'Accent usage: active tab/chips, primary CTA, clickable link text. Keep the rest neutral for clarity.', fill='#B2B8C3', font=f_s)

out = '/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/email_redesign_keep_sidebar_calendar.png'
img.save(out)
print(out)
