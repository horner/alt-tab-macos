"""Render the recorded AltTab rough cut with ffmpeg; no desktop interaction."""
import concurrent.futures
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
WORK = Path(tempfile.mkdtemp(prefix="alttab-rough-edit-"))
EDIT = json.loads((ROOT / "edit.json").read_text())
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"


def run(args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def render_shot(item):
    index, shot = item
    w, h, x, y = shot["crop"]
    output = WORK / f"shot-{index:02}.mp4"
    filters = f"crop={w}:{h}:{x}:{y},scale=1920:960:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos,pad=1920:960:(ow-iw)/2:(oh-ih)/2:color=0x11151c,fps=30,setsar=1,pad=1920:1080:0:0:color=0x11151c"
    run(["-ss", str(shot["start"]), "-i", str(ROOT / shot["source"]), "-t", str(shot["duration"]),
         "-an", "-vf", filters, "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-threads", "2",
         "-pix_fmt", "yuv420p", "-video_track_timescale", "15360", str(output)])
    print(f"Rendered shot {index + 1}/{len(EDIT['shots'])}", flush=True)
    return output


with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    clips = list(pool.map(render_shot, enumerate(EDIT["shots"])))
concat = WORK / "concat.txt"
concat.write_text("\n".join(f"file '{clip}'" for clip in clips) + "\n")
clean = ROOT / "alttab-rough-clean.mp4"
run(["-f", "concat", "-safe", "0", "-i", str(concat), "-c", "copy", "-movflags", "+faststart", str(clean)])
filters = [
    "drawbox=x=0:y=960:w=1920:h=3:color=0x3e8cff:t=fill",
    f"drawtext=fontfile={FONT}:text=AltTab:x=1730:y=986:fontsize=30:fontcolor=white",
    f"drawtext=fontfile={FONT}:text=ROUGH CUT:x=1730:y=1028:fontsize=17:fontcolor=0x9ca9bb"
]
elapsed = 0
for index, shot in enumerate(EDIT["shots"]):
    text_file = WORK / f"caption-{index}.txt"
    text_file.write_text(shot["caption"])
    end = elapsed + shot["duration"]
    filters.append(f"drawtext=fontfile={FONT}:textfile={text_file}:x=64:y=993:fontsize=40:fontcolor=white:enable='gte(t,{elapsed})*lt(t,{end})'")
    elapsed = end
filter_file = WORK / "captions.ffmpeg"
filter_file.write_text(",".join(filters))
run(["-i", str(clean), "-an", "-filter_script:v", str(filter_file), "-c:v", "libx264", "-preset", "fast",
     "-crf", "19", "-threads", "4", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(ROOT / "alttab-rough-cut.mp4")])
print(f"Saved {ROOT / 'alttab-rough-cut.mp4'}", flush=True)
