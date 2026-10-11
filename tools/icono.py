# Genera el ícono de AeroRadar (iOS universal + tamaños macOS)
import json, math, os
from PIL import Image, ImageDraw, ImageFilter
N = 1024
def icono(mac=False):
    img = Image.new('RGBA', (N, N))
    px = img.load()
    for y in range(N):
        for x in range(N):
            t = (x * 0.35 + y * 0.65) / N
            r = int(8 + 22 * t); g = int(20 + 30 * t); b = int(56 + 90 * t)
            px[x, y] = (r, g, b, 255)
    ov = Image.new('RGBA', (N, N)); d = ImageDraw.Draw(ov)
    cx, cy = N * 0.42, N * 0.60
    for i, rad in enumerate((150, 290, 430, 570)):
        d.ellipse([cx-rad, cy-rad, cx+rad, cy+rad], outline=(120, 200, 255, 70 - i*10), width=6)
    # barrido de radar
    d.pieslice([cx-570, cy-570, cx+570, cy+570], -80, -35, fill=(90, 200, 255, 34))
    img.alpha_composite(ov)
    # estela curva
    glow = Image.new('RGBA', (N, N)); gd = ImageDraw.Draw(glow)
    pts = []
    for k in range(60):
        s = k / 59
        x = 70 + s * 455; y = 960 - s * 470 - math.sin(s * math.pi) * 110
        pts.append((x, y))
    for k in range(len(pts)-1):
        w = int(6 + 34 * k / len(pts)); a = int(40 + 215 * k / len(pts))
        gd.line([pts[k], pts[k+1]], fill=(255, 176, 64, a), width=w)
    glow = glow.filter(ImageFilter.GaussianBlur(3))
    img.alpha_composite(glow)
    # avión
    plane = Image.new('RGBA', (N, N)); pd = ImageDraw.Draw(plane)
    P = [(0,-1),(0.09,-0.85),(0.1,-0.25),(0.85,0.18),(0.85,0.32),(0.1,0.12),(0.08,0.62),(0.32,0.8),(0.32,0.92),(0,0.84)]
    P = P + [(-x, y) for x, y in reversed(P[1:-1])]
    S = 250; ang = math.radians(48); ox, oy = 700, 330
    def tr(p):
        x, y = p[0]*S, p[1]*S
        return (ox + x*math.cos(ang) - y*math.sin(ang), oy + x*math.sin(ang) + y*math.cos(ang))
    sh = Image.new('RGBA', (N, N)); ImageDraw.Draw(sh).polygon([(x+14, y+18) for x, y in map(tr, P)], fill=(0, 0, 0, 120))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))
    pd.polygon([tr(p) for p in P], fill=(255, 255, 255, 255))
    img.alpha_composite(plane)
    if mac:  # squircle con margen para macOS
        m = Image.new('L', (N, N), 0); ImageDraw.Draw(m).rounded_rectangle([100, 100, 924, 924], 185, fill=255)
        small = img.resize((824, 824), Image.LANCZOS)
        out = Image.new('RGBA', (N, N), (0, 0, 0, 0)); out.paste(small, (100, 100))
        out.putalpha(m); return out
    return img.convert('RGB')
dst = 'AeroRadar/Assets.xcassets/AppIcon.appiconset'; os.makedirs(dst, exist_ok=True)
icono().save(f'{dst}/icon-1024.png')
mac = icono(True)
imgs = [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]
for s in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        f = f'mac-{s}@{sc}x.png'; mac.resize((s*sc, s*sc), Image.LANCZOS).save(f'{dst}/{f}')
        imgs.append({"filename": f, "idiom": "mac", "scale": f"{sc}x", "size": f"{s}x{s}"})
json.dump({"images": imgs, "info": {"author": "xcode", "version": 1}}, open(f'{dst}/Contents.json', 'w'), indent=1)
json.dump({"info": {"author": "xcode", "version": 1}}, open('AeroRadar/Assets.xcassets/Contents.json', 'w'))
os.makedirs('AeroRadar/Assets.xcassets/AccentColor.colorset', exist_ok=True)
json.dump({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "1.0", "green": "0.69", "blue": "0.25", "alpha": "1.0"}}}], "info": {"author": "xcode", "version": 1}}, open('AeroRadar/Assets.xcassets/AccentColor.colorset/Contents.json', 'w'))
icono().resize((512, 512)).save('icono-preview.png')
