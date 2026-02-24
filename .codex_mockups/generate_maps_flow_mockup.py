from PIL import Image, ImageDraw, ImageFont

W,H = 1600,900
img = Image.new('RGB',(W,H),(248,250,252))
d = ImageDraw.Draw(img)

try:
    ft = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 44)
    fh = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 28)
    fb = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 22)
    fs = ImageFont.truetype('/System/Library/Fonts/SFNSDisplay.ttf', 18)
except:
    ft=fh=fb=fs=ImageFont.load_default()

def rr(xy,r=18,fill=(255,255,255),outline=(210,214,220),w=2):
    d.rounded_rectangle(xy,r,fill=fill,outline=outline,width=w)

def arrow(x1,y1,x2,y2,c=(96,110,130),w=3):
    d.line((x1,y1,x2,y2),fill=c,width=w)
    import math
    ang=math.atan2(y2-y1,x2-x1)
    l=12
    a1=ang+2.6
    a2=ang-2.6
    d.line((x2,y2,x2+l*math.cos(a1),y2+l*math.sin(a1)),fill=c,width=w)
    d.line((x2,y2,x2+l*math.cos(a2),y2+l*math.sin(a2)),fill=c,width=w)

# header
d.text((40,26),'Maps 3-Page UX Flow (Saved / People / Timeline)',font=ft,fill=(20,24,31))
d.text((40,84),'Keep tabs pinned in top center; use contextual deep-links so pages feel connected, not isolated.',font=fs,fill=(92,102,119))

# nodes
rr((70,170,520,400),fill=(255,255,255))
d.text((96,196),'Saved Locations',font=fh,fill=(17,24,39))
for i,t in enumerate([
    '• Folder cards + mini map + current location',
    '• Tap folder -> open filtered timeline',
    '• Tap place -> place detail + visit history',
    '• Long press place -> rename/move/favorite'
]):
    d.text((96,250+i*34),t,font=fs,fill=(71,85,105))

rr((560,170,1030,400),fill=(255,255,255))
d.text((586,196),'People',font=fh,fill=(17,24,39))
for i,t in enumerate([
    '• Grouped list (Family/Friends/Work/Custom)',
    '• Tap person -> profile + linked places',
    '• Quick chip: "Show visits with this person"',
    '• Favorites row for one-tap access'
]):
    d.text((586,250+i*34),t,font=fs,fill=(71,85,105))

rr((1070,170,1530,400),fill=(255,255,255))
d.text((1096,196),'Timeline',font=fh,fill=(17,24,39))
for i,t in enumerate([
    '• Calendar strip + day timeline cards',
    '• Card actions: notes, people, merge, delete',
    '• Filter chips: Folder, Person, Date range',
    '• Swipe-back from all detail screens'
]):
    d.text((1096,250+i*34),t,font=fs,fill=(71,85,105))

# arrows top row
arrow(520,280,560,280)
arrow(1030,280,1070,280)
arrow(1070,330,520,330)

# shared data layer
rr((200,480,1410,640),fill=(243,246,252),outline=(188,199,216))
d.text((230,510),'Shared Context Layer (cross-page glue)',font=fb,fill=(30,41,59))
for i,t in enumerate([
    '1) Unified filter state: selected folder / selected person / selected date persists across tab changes.',
    '2) Location visit events auto-refresh Timeline and subtly update Saved + People badges in real time.',
    '3) Person-place linkage: from a timeline visit, attach people; reflected in both person profile and folder analytics.'
]):
    d.text((230,550+i*30),t,font=fs,fill=(51,65,85))

# drilldown layer
rr((70,700,1530,850),fill=(255,255,255),outline=(210,214,220))
d.text((96,726),'Recommended drill-down pages (full screen + back swipe)',font=fb,fill=(17,24,39))
for i,t in enumerate([
    '• Place Detail: map preview, visit streaks, spend/notes links, related people.',
    '• Person Detail: relationship, upcoming dates, places visited together, timeline shortcut.',
    '• Day Detail: full timeline cards, AI day summary, merge mode, edit notes/people inline.'
]):
    d.text((96,764+i*28),t,font=fs,fill=(71,85,105))

# arrows to shared layer
arrow(295,400,420,480)
arrow(790,400,800,480)
arrow(1300,400,1180,480)

out='/Users/alishahamin/Desktop/Vibecode/Seline/.codex_mockups/maps_redesign_flow_mockup.png'
img.save(out)
print(out)
