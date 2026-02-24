from PIL import Image, ImageDraw, ImageFont
import os

W, H = 2200, 1500
img = Image.new('RGB', (W, H), '#0b0b0d')
d = ImageDraw.Draw(img)

# Fonts
try:
    f_title = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 40)
    f_sub = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 22)
    f_body = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 18)
    f_small = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 15)
    f_h3 = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 24)
except:
    f_title = ImageFont.load_default()
    f_sub = ImageFont.load_default()
    f_body = ImageFont.load_default()
    f_small = ImageFont.load_default()
    f_h3 = ImageFont.load_default()

ORANGE = '#E07850'
WHITE = '#F3F4F6'
MUTED = '#A4A7AE'
CARD = '#14161A'
CARD2 = '#1A1D22'
BORDER = '#2A2E36'
GREEN = '#39B56A'
RED = '#D76464'

# Header
d.text((60, 40), 'Seline Email Redesign - Unified, Modern, Swipe-Back Friendly', fill=WHITE, font=f_title)
d.text((60, 98), 'Concept 1: Replace tab-heavy switching with one clear hierarchy + focused drill-down pages', fill=MUTED, font=f_sub)

# Phone canvas helper

def phone(x, y, w=490, h=1240, title=''):
    d.rounded_rectangle((x, y, x+w, y+h), radius=48, fill='#0f1115', outline='#2b2f36', width=3)
    # notch
    d.rounded_rectangle((x+170, y+20, x+w-170, y+54), radius=16, fill='#08090b')
    if title:
        d.text((x+24, y+72), title, fill=WHITE, font=f_h3)
    return (x, y, w, h)

# 1) Unified Inbox Hub
x1, y1, w1, h1 = phone(60, 170, title='Email Hub')
# top controls
d.rounded_rectangle((x1+24, y1+116, x1+w1-24, y1+178), radius=24, fill=CARD2, outline=BORDER)
d.rounded_rectangle((x1+38, y1+128, x1+154, y1+166), radius=18, fill=ORANGE)
d.text((x1+72, y1+136), 'All', fill='white', font=f_small)
d.rounded_rectangle((x1+164, y1+128, x1+294, y1+166), radius=18, fill='#232730')
d.text((x1+196, y1+136), 'Unread', fill=MUTED, font=f_small)
d.rounded_rectangle((x1+304, y1+128, x1+448, y1+166), radius=18, fill='#232730')
d.text((x1+338, y1+136), 'Today', fill=MUTED, font=f_small)
# summary cards
for i, (label, val, col) in enumerate([('New', '18', ORANGE), ('Priority', '4', RED), ('Saved', '62', GREEN)]):
    xx = x1+24+i*154
    d.rounded_rectangle((xx, y1+194, xx+142, y1+274), radius=18, fill=CARD, outline=BORDER)
    d.text((xx+14, y1+208), label, fill=MUTED, font=f_small)
    d.text((xx+14, y1+236), val, fill=col, font=f_h3)
# Focus row
for j, t in enumerate(['Action Required', 'Shipping / Travel', 'Newsletters']):
    yy = y1+300 + j*118
    d.rounded_rectangle((x1+24, yy, x1+w1-24, yy+102), radius=18, fill=CARD, outline=BORDER)
    d.text((x1+42, yy+18), t, fill=WHITE, font=f_body)
    d.text((x1+w1-120, yy+18), ['4','6','8'][j], fill=ORANGE, font=f_body)
    d.text((x1+42, yy+50), ['2 overdue', '3 tracking updates', 'batch summarize'][j], fill=MUTED, font=f_small)

# CTA row
for i,t in enumerate(['Inbox Feed','Sent','Planner']):
    xx = x1+24 + i*152
    fill = ORANGE if i==0 else '#232730'
    tc = 'white' if i==0 else MUTED
    d.rounded_rectangle((xx, y1+670, xx+140, y1+714), radius=20, fill=fill)
    d.text((xx+26, y1+684), t, fill=tc, font=f_small)

# feed preview
for i in range(4):
    yy = y1+740 + i*98
    d.rounded_rectangle((x1+24, yy, x1+w1-24, yy+86), radius=16, fill=CARD2)
    d.ellipse((x1+38, yy+20, x1+74, yy+56), fill='#6c7380')
    d.text((x1+86, yy+24), ['RBC Royal Bank','Airbnb','MS Store','Your Lisgar neighbours'][i], fill=WHITE, font=f_body)
    d.text((x1+86, yy+52), ['Transfer accepted','Trip update','Surface promo','Winter petition update'][i], fill=MUTED, font=f_small)

# compose pill
d.rounded_rectangle((x1+146, y1+h1-96, x1+w1-146, y1+h1-42), radius=26, fill=ORANGE)
d.text((x1+203, y1+h1-79), '+ Compose', fill='white', font=f_body)

# 2) Thread Detail
x2, y2, w2, h2 = phone(590, 170, title='Thread Detail')
# top bar
d.rounded_rectangle((x2+24, y2+116, x2+w2-24, y2+178), radius=24, fill=CARD2, outline=BORDER)
d.text((x2+42, y2+136), '< Back', fill=WHITE, font=f_small)
d.text((x2+210, y2+136), '2:15 PM', fill=MUTED, font=f_small)
d.text((x2+390, y2+136), '•••', fill=MUTED, font=f_body)
# sender card
d.rounded_rectangle((x2+24, y2+196, x2+w2-24, y2+292), radius=18, fill=CARD, outline=BORDER)
d.text((x2+42, y2+220), 'Amazon.ca', fill=WHITE, font=f_body)
d.text((x2+42, y2+248), 'to me  ·  Today, 2:15 PM', fill=MUTED, font=f_small)
# AI Summary
d.rounded_rectangle((x2+24, y2+312, x2+w2-24, y2+534), radius=18, fill=CARD, outline=BORDER)
d.text((x2+42, y2+334), 'AI Summary', fill=WHITE, font=f_h3)
d.text((x2+42, y2+372), '• Shipment delayed by 1 day.', fill=WHITE, font=f_body)
d.text((x2+42, y2+406), '• Track package:', fill=WHITE, font=f_body)
d.text((x2+178, y2+406), 'Amazon Order Status', fill=ORANGE, font=f_body)
d.line((x2+178, y2+428, x2+372, y2+428), fill=ORANGE, width=1)
d.text((x2+42, y2+444), '• New ETA is Feb 22, 2026.', fill=WHITE, font=f_body)
# smart reply full-width chips
d.text((x2+42, y2+558), 'Smart Reply', fill=WHITE, font=f_h3)
chips = ['Sounds good','Need more info','Decline politely','Schedule call']
for i,c in enumerate(chips):
    row = i//2
    col = i%2
    xx = x2+24 + col*221
    yy = y2+596 + row*56
    d.rounded_rectangle((xx, yy, xx+209, yy+44), radius=16, fill='#2A2E36')
    tw = d.textlength(c, font=f_small)
    d.text((xx + (209-tw)/2, yy+13), c, fill=WHITE, font=f_small)
# body preview
d.rounded_rectangle((x2+24, y2+720, x2+w2-24, y2+1058), radius=18, fill=CARD2, outline=BORDER)
d.text((x2+42, y2+744), 'Original Email', fill=WHITE, font=f_body)
for i, line in enumerate([
    'Your order has shipped and is currently in transit.',
    'Due to weather conditions, delivery is now expected',
    'on Sunday. You can monitor progress from your',
    'order page using your tracking number.'
]):
    d.text((x2+42, y2+782+i*32), line, fill=MUTED, font=f_small)

# 3) Saved + Folders
x3, y3, w3, h3 = phone(1120, 170, title='Folders & Saved')
d.rounded_rectangle((x3+24, y3+116, x3+w3-24, y3+178), radius=24, fill=CARD2, outline=BORDER)
d.text((x3+48, y3+136), 'Search folders', fill='#8F95A3', font=f_small)
d.rounded_rectangle((x3+w3-160, y3+128, x3+w3-38, y3+166), radius=18, fill=ORANGE)
d.text((x3+w3-126, y3+136), '+ Folder', fill='white', font=f_small)

d.text((x3+24, y3+210), 'Browse', fill=MUTED, font=f_h3)
for i,(name,cnt) in enumerate([('Pinned',4),('Receipts',130),('Travel',12),('Work',36),('Unfiled',18)]):
    yy = y3+250+i*86
    d.rounded_rectangle((x3+24, yy, x3+w3-24, yy+74), radius=14, fill=CARD, outline=BORDER)
    d.text((x3+42, yy+24), name, fill=WHITE, font=f_body)
    d.text((x3+w3-72, yy+24), str(cnt), fill=MUTED, font=f_body)

# saved thread preview
d.rounded_rectangle((x3+24, y3+720, x3+w3-24, y3+1090), radius=18, fill=CARD2, outline=BORDER)
d.text((x3+42, y3+742), 'Saved Thread View', fill=WHITE, font=f_h3)
d.text((x3+42, y3+780), 'Full-thread save, not single message fragments.', fill=MUTED, font=f_small)
for i,s in enumerate(['RBC: E-transfer receipt', 'Airbnb: Reservation confirmation', 'CRA: Account update notice']):
    yy = y3+820+i*84
    d.rounded_rectangle((x3+42, yy, x3+w3-42, yy+68), radius=12, fill='#1f232b')
    d.text((x3+58, yy+23), s, fill=WHITE, font=f_small)

# 4) Planner from Email (formerly events tab)
x4, y4, w4, h4 = phone(1650, 170, title='Planner (Email-linked)')
# insights
for i,(lab,val) in enumerate([('Today','6'),('Pending RSVP','2'),('Flights/Trips','1')]):
    xx = x4+24+i*154
    d.rounded_rectangle((xx, y4+116, xx+142, y4+194), radius=16, fill=CARD, outline=BORDER)
    d.text((xx+14, y4+132), lab, fill=MUTED, font=f_small)
    d.text((xx+14, y4+160), val, fill=ORANGE, font=f_h3)
# timeline cards
for i,(t,sub) in enumerate([
    ('11:30 AM  Team standup', 'From email: Zoom invite'),
    ('2:00 PM  Dentist reminder', 'From email: appointment confirmation'),
    ('6:45 PM  Flight check-in', 'From email: airline update')
]):
    yy = y4+224+i*124
    d.rounded_rectangle((x4+24, yy, x4+w4-24, yy+108), radius=16, fill=CARD2, outline=BORDER)
    d.text((x4+42, yy+22), t, fill=WHITE, font=f_body)
    d.text((x4+42, yy+58), sub, fill=MUTED, font=f_small)
    d.rounded_rectangle((x4+w4-168, yy+20, x4+w4-38, yy+56), radius=15, fill=ORANGE)
    d.text((x4+w4-134, yy+31), 'Open', fill='white', font=f_small)

# nav notes
d.rounded_rectangle((x4+24, y4+640, x4+w4-24, y4+980), radius=18, fill=CARD, outline=BORDER)
d.text((x4+42, y4+664), 'Navigation Rules', fill=WHITE, font=f_h3)
notes = [
    '1. Hub -> Thread Detail uses NavigationStack push.',
    '2. Thread Detail, Saved Thread, Planner Detail support',
    '   native swipe-from-left back gesture.',
    '3. Compose opens full-screen, dismiss by swipe-down +',
    '   explicit Cancel for reliability.',
    '4. Sidebars become full pages on compact widths.'
]
for i, line in enumerate(notes):
    d.text((x4+42, y4+704+i*36), line, fill=MUTED, font=f_small)

# Footer legend
d.text((60, 1428), 'Accent: #E07850 (orange) | Use accent only for active state, primary CTA, and actionable links', fill='#B1B5BF', font=f_small)

out = '/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/email_redesign_mockups.png'
img.save(out)
print(out)
