"""Rebuild the curated offline media. Requires ffmpeg; see the provenance file.

A change to the pinned source hash requires another visual/provenance review.
"""
from pathlib import Path
import hashlib
import subprocess
import tempfile
import json

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'GymApp/Resources/ExerciseMedia'
manifest = json.loads((ASSETS / 'manifest.json').read_text())
for asset in manifest:
    with tempfile.TemporaryDirectory() as directory:
        source = Path(directory) / 'source'
        subprocess.run(['curl', '-fsSL', '-A', 'Mozilla/5.0', asset['download'], '-o', str(source)], check=True)
        if hashlib.sha256(source.read_bytes()).hexdigest() != asset['sha256']:
            raise ValueError('Source changed; review it first')
        # wger originals are 1080p HEVC phone videos: scale down so the app stays small.
        small = asset['author'] == 'Goulart'
        scale = ['-vf', 'scale=-2:480,fps=24', '-preset', 'slow', '-crf', '30', '-tag:v', 'avc1'] if small else []
        subprocess.run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(source), '-an',
                        *scale, '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
                        str(ASSETS / (asset['name'] + '.mp4'))], check=True)
        subprocess.run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-ss', '1' if small else '0.2',
                        '-i', str(source), *(['-vf', 'scale=-2:480', '-q:v', '4'] if small else []),
                        '-frames:v', '1', str(ASSETS / (asset['name'] + '.jpg'))], check=True)
