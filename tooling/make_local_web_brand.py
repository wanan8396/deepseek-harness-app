#!/usr/bin/env python3
"""Reproduce the current phone-shell brand assets from the supplied 245x35 wordmark.

No upstream app resources are replaced. The generated Android resources belong to
this single app product; the source stays separate from the derived images.
"""
from pathlib import Path
import json
import stat
from PIL import Image, ImageChops, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'app/assets/branding'
RES = ROOT / 'app/android/app/src/localWebLite/res'
SOURCE = ASSETS / 'source-logo.png'
INK = (21, 21, 23)
WHITE = (248, 248, 250)


def ink_mask(image):
    # The source has a nearly white, slightly tinted background. Keep antialiasing.
    grey = image.convert('L')
    return grey.point(lambda p: max(0, min(255, round((247-p)*255/226))))


def tinted(mask, color):
    out = Image.new('RGBA', mask.size, color + (0,))
    out.putalpha(mask)
    return out


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def main():
    # Attachment copies can inherit Windows' read-only file attribute. Flutter
    # propagates that attribute into its copied assets, then fails its next clean.
    # Only normalize this workspace copy; the original attachment stays intact.
    SOURCE.chmod(SOURCE.stat().st_mode | stat.S_IWRITE)
    source = Image.open(SOURCE).convert('RGB')
    mask = ink_mask(source)
    bbox = mask.point(lambda p: 255 if p > 80 else 0).getbbox()
    word = mask.crop(bbox)
    save(tinted(word, INK), ASSETS/'wordmark.png')
    save(tinted(word, WHITE), ASSETS/'wordmark-dark.png')
    # Only the whale mark; do not squeeze the entire wordmark into a launcher icon.
    whale = mask.crop((0, 0, 39, 35))
    whale = whale.crop(whale.point(lambda p: 255 if p > 60 else 0).getbbox())
    whale = ImageOps.expand(whale, border=2, fill=0)
    # Smooth a high-resolution coverage contour then rasterize crisp antialiased ink.
    contour_scale = 32
    whale = whale.resize((whale.width*contour_scale, whale.height*contour_scale), Image.Resampling.NEAREST)
    whale = whale.filter(ImageFilter.GaussianBlur(contour_scale*0.35)).point(lambda p: 255 if p >= 128 else 0)
    icon_h = round(208*whale.height/whale.width)
    save(tinted(whale.resize((208, icon_h), Image.Resampling.LANCZOS), INK), ASSETS/'whale.png')
    save(tinted(whale.resize((208, icon_h), Image.Resampling.LANCZOS), WHITE), ASSETS/'whale-dark.png')
    (RES/'drawable').mkdir(parents=True, exist_ok=True)
    for qualifier, color in [('values', '#FFF7F8FA'), ('values-night', '#FF151517')]:
        target = RES/qualifier/'colors.xml'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>' + ''.join(
            f'<color name="{name}">{color}</color>' for name in (
                'launch_background_top', 'launch_background_bottom', 'launch_icon_ground')) + '</resources>\n', encoding='utf-8')
    (RES/'drawable/ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle"><solid android:color="#F7F8FA" /></shape>\n', encoding='utf-8')
    adaptive = '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@drawable/ic_launcher_background" /><foreground android:drawable="@mipmap/ic_launcher_foreground" /><monochrome android:drawable="@drawable/ic_launcher_monochrome" /></adaptive-icon>\n'
    names = ['ic_launcher', 'ic_launcher_round', 'ic_launcher_night', 'ic_launcher_night_round',
             'ic_launcher_frost', 'ic_launcher_frost_round', 'ic_launcher_ink', 'ic_launcher_ink_round']
    for name in names:
        path = RES/'mipmap-anydpi-v26'/f'{name}.xml'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(adaptive, encoding='utf-8')
    for density, scale in [('mdpi',1),('hdpi',1.5),('xhdpi',2),('xxhdpi',3),('xxxhdpi',4)]:
        side = round(108*scale)
        fg = Image.new('RGBA', (side,side))
        width = round(56*scale)
        height = round(width*whale.height/whale.width)
        mark = tinted(whale.resize((width,height), Image.Resampling.LANCZOS), INK)
        fg.alpha_composite(mark, ((side-width)//2,(side-height)//2))
        save(fg, RES/f'mipmap-{density}/ic_launcher_foreground.png')
        save(fg, RES/f'drawable-{density}/ic_launcher_monochrome.png')
        legacy_side = round(48*scale)
        legacy = Image.new('RGBA',(legacy_side,legacy_side),(247,248,250,255))
        w = round(31*scale); h = round(w*whale.height/whale.width)
        legacy.alpha_composite(tinted(whale.resize((w,h),Image.Resampling.LANCZOS),INK),((legacy_side-w)//2,(legacy_side-h)//2))
        for name in names:
            save(legacy, RES/f'mipmap-{density}/{name}.png')
    preview = Image.new('RGBA',(512,512),(247,248,250,255))
    w=330; h=round(w*whale.height/whale.width)
    preview.alpha_composite(tinted(whale.resize((w,h),Image.Resampling.LANCZOS),INK),((512-w)//2,(512-h)//2))
    save(preview, ASSETS/'launcher-preview.png')
    (ASSETS/'provenance.json').write_text(json.dumps({
        'source':'User-provided deepseek HARNESS wordmark',
        'sourceSize':[source.width,source.height],
        'sourceSha256':'c94cfaef084d092ceaee1cdeff2ecee57dd979bab9dc893dae72864dd5aba89f',
        'method':'Extract antialiased ink and whale mark; adapt into monochrome light/dark and Android density-specific resources.',
        'note':'Derived from the supplied low-resolution image; not claimed as original vector artwork.'
    },ensure_ascii=False,indent=2)+'\n', encoding='utf-8')
    print('Generated wordmark, whale, and Android launcher resources.')

if __name__ == '__main__':
    main()
