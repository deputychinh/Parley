#!/usr/bin/env python3
"""Parley TikTok intro (1080×1920, ~60 s): `make tiktok` → docs/video/parley_tiktok.mp4 + .srt.

Each scene = a headline, an app screenshot in a window frame, a caption, and a Vietnamese voice-over spoken by the
macOS voice "Linh" (`say`, offline). Scenes are drawn with Pillow, given a slow zoom and joined with ffmpeg.
Screenshots come from docs/screenshots (taken with seeded sample data by scripts/shot.sh — never the owner's data).
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.path.join(ROOT, "docs", "screenshots")
OUT = os.path.join(ROOT, "docs", "video")
W, H, FPS = 1080, 1920, 30
FONT = "/System/Library/Fonts/SFNS.ttf"
PURPLE = (139, 92, 246)
LILAC = (196, 181, 253)

# headline (white line, lilac line), screenshot and the part of it to show (fractions x0, y0, x1, y1 — a close
# crop keeps the app's text readable on a phone), who speaks, what is said (Vietnamese voice "Linh").
SCENES = [
    ("Họp tiếng Anh", "mà nghe không kịp?", ("history.png", (0.21, 0.04, 0.60, 0.80)), "Parley",
     "Họp tiếng Anh mà nghe không kịp? Nói ra thì người ta không hiểu? Để Parley lo cho nha!"),
    ("Gặp Parley,", "phiên dịch ngay trên Mac", ("history.png", (0.21, 0.04, 0.99, 0.62)), "Parley",
     "Mình là Parley, phiên dịch và luyện nói tiếng Anh ngay trên máy Mac. Không cần mạng, không gửi dữ liệu đi đâu."),
    ("Zoom, Meet, YouTube", "dịch song song tức thì", ("history.png", (0.21, 0.04, 0.99, 0.80)), "Parley",
     "Mọi âm thanh trên máy, từ Zoom, Meet tới YouTube, được dịch song song theo thời gian thực. Họp xong vẫn xem lại được."),
    ("Chữ, ảnh, manga", "dán vào là dịch", ("translate.png", (0.21, 0.03, 0.99, 0.52)), "Parley",
     "Dán chữ hay chụp một vùng màn hình, kể cả tiếng Nhật, Parley tự nhận ngôn ngữ và dịch ngay."),
    ("Học từng âm IPA", "giải thích bằng tiếng Việt", ("sound-sh.png", (0.23, 0.04, 0.99, 0.97)), "Parley",
     "Phát âm sai? Học đủ bốn mươi mốt âm tiếng Anh, có hướng dẫn đặt môi lưỡi bằng tiếng Việt, ưu tiên những âm người Việt hay sai."),
    ("Nói sai âm nào?", "Parley chỉ rõ", ("sound-lab-answer.png", (0.30, 0.17, 0.91, 0.58)), "Parley",
     "Luyện cặp âm dễ nhầm, nghe nhiều giọng khác nhau rồi tự nói. Nói ship thành sip, Parley chỉ ra ngay âm nào bị đổi."),
    ("Ôn mỗi ngày", "từ vựng, ngữ pháp, hội thoại", ("practice-game.png", (0.31, 0.12, 0.96, 0.70)), "Parley",
     "Thêm thẻ từ, ngữ pháp và hội thoại với trí tuệ nhân tạo chạy ngay trên máy. Mỗi ngày mười phút là đủ."),
]
END = ("Parley", "Nghe kịp. Nói rõ.",
       "Phiên dịch và luyện nói tiếng Anh, 100% offline trên máy Mac.",
       "Tải miễn phí: github.com/deputychinh/Parley",
       "Parley. Nghe kịp, nói rõ. Tải miễn phí trên GitHub nha!")


def font(size, weight="Bold"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def background():
    """Night purple, lighter toward the bottom, a soft glow behind the window."""
    top, bottom = (14, 10, 28), (40, 18, 78)
    grad = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        grad.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    img = grad.resize((W, H)).convert("RGBA")
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-200, 560, W + 200, 1460), fill=(110, 60, 220, 110))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(160)))
    return img


def brand(img, icon):
    small = icon.resize((56, 56))
    img.alpha_composite(small, (64, 92))
    ImageDraw.Draw(img).text((132, 96), "Parley", font=font(40, "Semibold"), fill=(255, 255, 255))


def wrap(text, f, width, draw):
    lines, line = [], ""
    for w in text.split():
        trial = (line + " " + w).strip()
        if draw.textlength(trial, font=f) <= width:
            line = trial
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def window(shot):
    """The cropped screenshot in a rounded window with a soft shadow (a Mac app, not a phone); at most 980 × 880."""
    name, (x0, y0, x1, y1) = shot
    img = Image.open(os.path.join(SHOTS, name)).convert("RGB")
    img = img.crop((int(x0 * img.width), int(y0 * img.height), int(x1 * img.width), int(y1 * img.height)))
    scale = min(980 / img.width, 880 / img.height)
    img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    radius = 26
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width, img.height), radius, fill=255)
    framed = Image.new("RGBA", (img.width + 120, img.height + 120), (0, 0, 0, 0))
    shadow = Image.new("RGBA", framed.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((60, 75, 60 + img.width, 75 + img.height), radius, fill=(0, 0, 0, 170))
    framed.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    framed.paste(img, (60, 60), mask)
    ImageDraw.Draw(framed).rounded_rectangle((60, 60, 60 + img.width, 60 + img.height), radius,
                                             outline=(160, 130, 255, 120), width=2)
    return framed


def caption(img, who, text):
    d = ImageDraw.Draw(img)
    f = font(46, "Semibold")
    lines = wrap(f"{who}: {text}", f, 900, d)
    lh = 60
    top = 1440
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(overlay).rounded_rectangle((60, top, W - 60, top + len(lines) * lh + 56), 22,
                                              fill=(16, 10, 30, 225), outline=(120, 90, 200, 160), width=2)
    img.alpha_composite(overlay)
    d = ImageDraw.Draw(img)
    y = top + 28
    for i, line in enumerate(lines):
        x = (W - d.textlength(line, font=f)) / 2
        head = who + ":"
        if i == 0 and line.startswith(head):
            d.text((x, y), head, font=f, fill=LILAC)
            d.text((x + d.textlength(head + " ", font=f), y), line[len(head) + 1:], font=f, fill=(255, 255, 255))
        else:
            d.text((x, y), line, font=f, fill=(255, 255, 255))
        y += lh


def scene_image(icon, top, second, shot, who, text):
    img = background()
    brand(img, icon)
    d = ImageDraw.Draw(img)
    size = 84  # shrink a long headline to fit the frame
    while size > 50 and max(d.textlength(top, font=font(size, "Heavy")),
                            d.textlength(second, font=font(size, "Heavy"))) > W - 128:
        size -= 2
    d.text((64, 190), top, font=font(size, "Heavy"), fill=(255, 255, 255))
    d.text((64, 190 + size * 1.2), second, font=font(size, "Heavy"), fill=LILAC)
    win = window(shot)
    img.alpha_composite(win, ((W - win.width) // 2, 910 - win.height // 2))
    caption(img, who, text)
    return img.convert("RGB")


def end_image(icon):
    title, tag, line, cta, _ = END
    img = background()
    big = icon.resize((260, 260))
    img.alpha_composite(big, ((W - 260) // 2, 520))
    d = ImageDraw.Draw(img)
    for text, f, y in [(title, font(130, "Heavy"), 830), (tag, font(80, "Bold"), 1010)]:
        d.text(((W - d.textlength(text, font=f)) / 2, y), text, font=f, fill=(255, 255, 255))
    f = font(46, "Medium")
    y = 1150
    for l in wrap(line, f, 880, d):
        d.text(((W - d.textlength(l, font=f)) / 2, y), l, font=f, fill=(220, 210, 245))
        y += 62
    f = font(44, "Semibold")
    tw = d.textlength(cta, font=f)
    d.rounded_rectangle(((W - tw) / 2 - 40, 1340, (W + tw) / 2 + 40, 1430), 45, fill=PURPLE)
    d.text(((W - tw) / 2, 1360), cta, font=f, fill=(255, 255, 255))
    return img.convert("RGB")


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", path],
                         check=True, capture_output=True, text=True).stdout
    return float(json.loads(out)["format"]["duration"])


def srt_time(t):
    ms = int(round(t * 1000))
    return f"{ms // 3600000:02}:{ms // 60000 % 60:02}:{ms // 1000 % 60:02},{ms % 1000:03}"


def main():
    os.makedirs(OUT, exist_ok=True)
    work = tempfile.mkdtemp(prefix="parley-tiktok-")
    icon_png = os.path.join(work, "icon.png")
    run(["sips", "-s", "format", "png", "-z", "512", "512",
         os.path.join(ROOT, "build", "Parley.app", "Contents", "Resources", "AppIcon.icns"), "--out", icon_png])
    icon = Image.open(icon_png).convert("RGBA")
    items = [(scene_image(icon, *s), s[3], s[4]) for s in SCENES] + [(end_image(icon), "Parley", END[4])]
    parts, srt, t = [], [], 0.0
    for i, (img, who, text) in enumerate(items):
        png, aiff, mp4 = (os.path.join(work, f"s{i}.{ext}") for ext in ("png", "aiff", "mp4"))
        img.save(png)
        run(["/usr/bin/say", "-v", "Linh", "-r", "175", "-o", aiff, text])
        speech = duration(aiff)
        lead, tail = 0.3, 0.7
        length = lead + speech + tail
        frames = int(length * FPS)
        zoom = (f"zoompan=z='1+0.04*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
                f":d={frames}:s={W}x{H}:fps={FPS}")  # slow push-in, 1.00 → 1.04
        delay = int(lead * 1000)
        run(["ffmpeg", "-y", "-loop", "1", "-i", png, "-i", aiff,
             "-filter_complex", f"[0:v]scale={W * 2}:{H * 2},{zoom},format=yuv420p[v];"
                                f"[1:a]aresample=48000,adelay={delay}|{delay},apad[a]",
             "-map", "[v]", "-map", "[a]", "-t", f"{length:.3f}", "-r", str(FPS),
             "-c:v", "libx264", "-preset", "medium", "-crf", "20",
             "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-ac", "2", mp4])
        parts.append(mp4)
        srt.append(f"{i + 1}\n{srt_time(t + lead)} --> {srt_time(t + lead + speech)}\n{who}: {text}\n")
        t += length
    listing = os.path.join(work, "parts.txt")
    with open(listing, "w") as f:
        f.writelines(f"file '{p}'\n" for p in parts)
    final = os.path.join(OUT, "parley_tiktok.mp4")
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", "-movflags", "+faststart", final])
    with open(os.path.join(OUT, "parley_tiktok.srt"), "w") as f:
        f.write("\n".join(srt))
    print(f"{final} ({t:.1f} s)")


if __name__ == "__main__":
    sys.exit(main())
