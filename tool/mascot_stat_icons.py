"""White notification small icons (ic_stat_<id>) from the mascot renders.

    python3 tool/mascot_stat_icons.py <render dir> <res dir>

Called by tool/mascot_icons.sh. The status bar only uses the alpha channel, so
each icon is the mascot's silhouette with its dark features (eyes, mouth,
outlines) cut out, cropped square with a 2dp margin, in all five densities.
"""
import os
import sys

from PIL import Image, ImageFilter

DENSITIES = {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96}
DARK = 0.3  # luminance below this is a feature → hole


def silhouette(path):
    im = Image.open(path).convert('RGBA')
    im = im.crop(im.getchannel('A').point(lambda a: 255 if a > 40 else 0).getbbox())
    w, h = im.size
    s = max(w, h)
    sq = Image.new('RGBA', (s, s))
    sq.paste(im, ((s - w) // 2, (s - h) // 2))
    mask = Image.new('L', (s, s))
    px, mp = sq.load(), mask.load()
    for y in range(s):
        for x in range(s):
            r, g, b, a = px[x, y]
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            mp[x, y] = 255 if a >= 128 and lum >= DARK else 0
    out = Image.new('RGBA', (s, s), (255, 255, 255, 0))
    out.putalpha(mask.filter(ImageFilter.MedianFilter(5)))
    return out


def main(src, res):
    for f in sorted(os.listdir(src)):
        if not f.endswith('_foreground.png'):
            continue
        mascot = f[: -len('_foreground.png')]
        sil = silhouette(os.path.join(src, f))
        for density, size in DENSITIES.items():
            margin = size // 12
            icon = Image.new('RGBA', (size, size), (255, 255, 255, 0))
            icon.paste(sil.resize((size - 2 * margin,) * 2, Image.LANCZOS), (margin, margin))
            icon.save(os.path.join(res, f'drawable-{density}', f'ic_stat_{mascot}.png'))


if __name__ == '__main__':
    main(*sys.argv[1:3])
