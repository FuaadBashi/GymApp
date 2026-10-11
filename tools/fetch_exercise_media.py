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
        source = Path(directory) / 'source.webm'
        subprocess.run(['curl', '-fsSL', '-A', 'Mozilla/5.0', asset['download'], '-o', str(source)], check=True)
        if hashlib.sha256(source.read_bytes()).hexdigest() != asset['sha256']:
            raise ValueError('Source changed; review it first')
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(source), '-an',
                        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
                        str(ASSETS / (asset['name'] + '.mp4'))], check=True)
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', '0.2', '-i', str(source),
                        '-frames:v', '1', str(ASSETS / (asset['name'] + '.jpg'))], check=True)
