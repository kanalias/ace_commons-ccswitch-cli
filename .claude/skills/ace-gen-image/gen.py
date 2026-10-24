#!/usr/bin/env python3
"""Ảnh AI qua proxy ANTHROPIC_BASE_URL (fallback chain) + crop nhiều size + overlay chữ/logo tuỳ chọn.
Usage: gen.py "<prompt>" [--size WxH ...] [--out DIR] [--name N] [--style S] [--no-style]
              [--title T] [--subtitle S] [--footer F] [--logo PNG]
       gen.py --selftest
Key + endpoint đọc ~/.claude/settings.json .env.ANTHROPIC_AUTH_TOKEN / ANTHROPIC_BASE_URL, không in key."""
import argparse, base64, glob, io, json, os, random, sys, urllib.request
from PIL import Image, ImageDraw, ImageFont

FONT = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
PRIMARY = ['cx/gpt-image-2.5', 'cx/gpt-5.6-terra-image']  # random 1, model còn lại là fallback đầu
FALLBACK = ['ag/gemini-3.1-flash-image', 'gemini/gemini-3-pro-image-preview']
STYLE = (', deep navy and electric blue palette with soft purple glow, isometric 3D style, minimal, '
         'professional tech-company aesthetic, no text, no logos')

def default_out():  # GEN_IMAGE_OUT > Shared drive "media" của Google Drive bất kỳ account > ./gen-image-out
    env = os.environ.get('GEN_IMAGE_OUT')
    if env: return os.path.expanduser(env)
    drives = sorted(glob.glob(os.path.expanduser('~/Library/CloudStorage/GoogleDrive-*/Shared drives/media')))
    return drives[0] if drives else os.path.abspath('gen-image-out')

def model_chain():
    return random.sample(PRIMARY, 2) + FALLBACK

def api_size(w, h):  # chọn khung gen gần aspect đích nhất
    r = w / h
    return '1536x1024' if r > 1.2 else '1024x1536' if r < 0.83 else '1024x1024'

def generate(prompt, size):
    env = json.load(open(os.path.expanduser('~/.claude/settings.json')))['env']
    key, api = env['ANTHROPIC_AUTH_TOKEN'], env['ANTHROPIC_BASE_URL'].rstrip('/') + '/images/generations'
    models = model_chain()
    for i, model in enumerate(models):
        body = json.dumps({'model': model, 'prompt': prompt, 'n': 1, 'size': size}).encode()
        req = urllib.request.Request(api, body, {'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json',
                                                 'User-Agent': 'curl/8'})  # Cloudflare chặn UA Python-urllib (403)
        try:
            data = json.load(urllib.request.urlopen(req, timeout=240))
            print('model: ' + model, file=sys.stderr)
            return Image.open(io.BytesIO(base64.b64decode(data['data'][0]['b64_json']))).convert('RGB')
        except Exception as e:
            if i == len(models) - 1: raise
            print('%s failed (%s), fallback %s' % (model, e, models[i + 1]), file=sys.stderr)

def compose(raw, W, H, title=None, subtitle=None, footer=None, logo=None):
    s = max(W / raw.width, H / raw.height)
    bg = raw.resize((round(raw.width * s), round(raw.height * s)), Image.LANCZOS)
    x, y = (bg.width - W) // 2, (bg.height - H) // 2
    bg = bg.crop((x, y, x + W, y + H))
    if not (title or subtitle or footer or logo): return bg
    pad = int(W * 0.06); d = ImageDraw.Draw(bg)
    if title or subtitle or footer:  # gradient tối nửa dưới để chữ dễ đọc
        g = Image.new('L', (1, H))
        for yy in range(H): g.putpixel((0, yy), int(235 * max(0, (yy - H * 0.35) / (H * 0.65)) ** 1.3))
        bg.paste(Image.new('RGB', (W, H), (8, 12, 32)), (0, 0), g.resize((W, H)))
    if logo:
        lg = Image.open(logo).convert('RGBA'); lw = int(W * 0.26)
        lg = lg.resize((lw, int(lg.height * lw / lg.width)), Image.LANCZOS)
        bg.paste(lg, (pad, pad), lg)
    fs = int(W * 0.062); ft = ImageFont.truetype(FONT, fs)
    while title and d.textlength(title, font=ft) > W - 2 * pad: fs -= 2; ft = ImageFont.truetype(FONT, fs)
    yt = H - pad - fs
    if title: d.text((pad, yt), title, font=ft, fill='white')
    if subtitle: d.text((pad, yt - int(W * 0.045)), subtitle, font=ImageFont.truetype(FONT, int(W * 0.024)), fill=(120, 190, 255))
    if footer: d.text((pad, H - pad + int(W * 0.012)), footer, font=ImageFont.truetype(FONT, int(W * 0.02)), fill=(200, 210, 230))
    return bg

def selftest():
    raw = Image.new('RGB', (1536, 1024), (40, 60, 120))
    for wh in [(1200, 628), (1080, 1080), (1080, 1920)]:
        assert compose(raw, *wh).size == wh
        assert compose(raw, *wh, title='A Very Long Title For Testing Wrap Width', subtitle='SUB', footer='x.co').size == wh
    assert [api_size(1200, 628), api_size(1080, 1080), api_size(1080, 1920)] == ['1536x1024', '1024x1024', '1024x1536']
    chains = {tuple(model_chain()) for _ in range(50)}
    assert len(chains) == 2 and all(c[2:] == tuple(FALLBACK) and set(c[:2]) == set(PRIMARY) for c in chains), chains
    os.environ['GEN_IMAGE_OUT'] = '~/x'; assert default_out() == os.path.expanduser('~/x')
    print('selftest ok')

if __name__ == '__main__':
    if sys.argv[1:] == ['--selftest']: selftest(); sys.exit()
    p = argparse.ArgumentParser(usage=__doc__)
    p.add_argument('prompt'); p.add_argument('--size', action='append', default=[])
    p.add_argument('--out', default=default_out()); p.add_argument('--name', default='img')
    p.add_argument('--style', default=STYLE); p.add_argument('--no-style', action='store_true')
    for k in ('title', 'subtitle', 'footer', 'logo'): p.add_argument('--' + k)
    a = p.parse_args()
    sizes = [tuple(map(int, s.lower().split('x'))) for s in a.size]
    os.makedirs(a.out, exist_ok=True)
    raw = generate(a.prompt + ('' if a.no_style else a.style), api_size(*sizes[0]) if sizes else '1536x1024')
    rp = os.path.join(a.out, a.name + '-raw.jpg'); raw.save(rp, quality=92); print(rp)
    for W, H in sizes:
        fp = os.path.join(a.out, '%s-%dx%d.jpg' % (a.name, W, H))
        compose(raw, W, H, a.title, a.subtitle, a.footer, a.logo).save(fp, quality=92); print(fp)
