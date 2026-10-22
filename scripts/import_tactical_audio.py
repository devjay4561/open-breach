#!/usr/bin/env python3
"""Select recorded CC0 shots / Kenney contact sounds; no synthesis.

Requires ffmpeg and cached original archives under .tools/asset-sources.
Re-running produces the same PCM samples and per-file provenance.
"""
from pathlib import Path
from zipfile import ZipFile
import array
import hashlib
import json
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.tools/asset-sources'
OUT = ROOT / 'web/assets/audio'
OUT.mkdir(parents=True, exist_ok=True)
WORK = CACHE / 'tactical-audio-import'
WORK.mkdir(exist_ok=True)
RATE = 32000
entries = []

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(args):
    subprocess.run(['ffmpeg', '-y', '-v', 'error', *args], check=True)

def pcm(path):
    with wave.open(str(path)) as source:
        return array.array('h', source.readframes(source.getnframes()))

def record(name, source, source_path, pack, filters, duration=None, start=0):
    arguments = ['-ss', str(start), '-i', str(source_path)]
    if duration is not None:
        arguments += ['-t', str(duration)]
    destination = OUT / (name + '.wav')
    run([*arguments, '-af', filters, '-ac', '1', '-ar', str(RATE), '-c:a', 'pcm_s16le', str(destination)])
    with wave.open(str(destination)) as audio:
        seconds = audio.getnframes() / audio.getframerate()
    entries.append({'path': str(destination.relative_to(ROOT)), 'pack': pack, 'source_member': source,
                    'source_sha256': sha(source_path), 'sha256': sha(destination), 'start_seconds': start,
                    'duration_seconds': seconds, 'processing': filters, 'format': 'mono 32000 Hz signed 16-bit PCM'})

for member, names in [
    ('Prepared SFX Library/AR-15/D_24P.wav', ['shot', 'shot_alt']),
    ('Prepared SFX Library/AR-15/D_32P.wav', ['shot_close', 'shot_close_alt']),
]:
    original = CACHE / member
    if not original.exists():
        original.parent.mkdir(parents=True, exist_ok=True)
        with original.open('wb') as destination:
            subprocess.run(['bsdtar', '-xOf', str(CACHE / 'firearms.7z'), member], stdout=destination, check=True)
    mono = WORK / (original.stem + '-mono.wav')
    run(['-i', str(original), '-ac', '1', '-ar', str(RATE), str(mono)])
    samples = pcm(mono)
    threshold = max(abs(value) for value in samples) * 0.18
    onsets = []
    for index, value in enumerate(samples):
        if abs(value) > threshold and (not onsets or index - onsets[-1] > RATE * 2.5):
            onsets.append(max(0, index - round(RATE * 0.003)))
    if len(onsets) != 2:
        raise ValueError(f'{member}: expected exactly 2 isolated recorded shots, got {len(onsets)}')
    for name, onset in zip(names, onsets):
        peak = max(abs(value) for value in samples[onset:onset + round(RATE * 1.2)]) / 32768
        gain = 0.8 / max(0.01, peak)
        record(name, member, original, 'free-firearm-library',
               f'highpass=f=65,volume={gain:.8f},afade=t=out:st=0.96:d=0.24,alimiter=limit=0.9:level=false:latency=true',
               duration=1.2, start=onset / RATE)

with ZipFile(CACHE / 'kenney-impact-sounds.zip') as archive:
    (ROOT / 'licenses/Kenney-Impact-Sounds.txt').write_bytes(archive.read('License.txt'))
    contacts = [
        ('hit', 'impactSoft_medium_000', 0.65),
        ('hit_alt', 'impactSoft_medium_001', 0.65),
        ('door', 'impactWood_medium_000', 0.6),
        ('door_alt', 'impactWood_medium_001', 0.6),
        ('door_alt2', 'impactWood_medium_002', 0.6),
        ('door_latch', 'impactWood_light_000', 0.5),
        ('door_latch_alt', 'impactWood_light_001', 0.5),
        ('door_latch_alt2', 'impactWood_light_002', 0.5),
    ]
    for name, member, gain in contacts:
        member = 'Audio/' + member + '.ogg'
        original = WORK / Path(member).name
        original.write_bytes(archive.read(member))
        record(name, member, original, 'kenney-impact-sounds',
               f'highpass=f=80,volume={gain},alimiter=limit=0.8:level=false:latency=true')
    for surface in ['concrete', 'wood']:
        for index in range(5):
            name = f'footstep_{surface}_{index:03d}'
            member = 'Audio/' + name + '.ogg'
            original = WORK / Path(member).name
            original.write_bytes(archive.read(member))
            mono = WORK / (name + '-mono.wav')
            run(['-i', str(original), '-ac', '1', '-ar', str(RATE), '-c:a', 'pcm_s16le', str(mono)])
            samples = pcm(mono)
            peak = max(abs(value) for value in samples) / 32768
            gain = min(4.0, 0.58 / max(0.01, peak))
            record(name, member, original, 'kenney-impact-sounds',
                   f'silenceremove=start_periods=1:start_duration=0:start_threshold=-48dB:start_silence=0.004,highpass=f=95,volume={gain:.8f},alimiter=limit=0.65:level=false:latency=true')

provenance = {
    'free_only': True,
    'sources': [
        {'id': 'free-firearm-library', 'url': 'https://opengameart.org/content/the-free-firearm-sound-library',
         'creators': ['Ben Jaszczak', 'Brian Nelson', 'Kevin Heras', 'Matthew Nanney'], 'license': 'CC0-1.0',
         'archive_sha256': sha(CACHE / 'firearms.7z'), 'license_evidence': 'licenses/Free-Firearm-Library.txt',
         'notes': 'Recorded single rifle shots. Archive contains no separate reload or weapon-handling recordings.'},
        {'id': 'kenney-impact-sounds', 'url': 'https://kenney.nl/assets/impact-sounds', 'creators': ['Kenney'],
         'license': 'CC0-1.0', 'archive_sha256': sha(CACHE / 'kenney-impact-sounds.zip'),
         'license_evidence': 'licenses/Kenney-Impact-Sounds.txt',
         'notes': 'Prepared concrete/wood footsteps plus generic soft/wood contacts. Light wood contacts accompany the start of a moving door, medium contacts its completed opening. Door contacts are not advertised as dedicated hinge recordings or real ballistic recordings.'},
    ],
    'files': entries,
}
destination = ROOT / 'licenses/provenance/tactical-audio-provenance.json'
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
print(f'Imported {len(entries)} recorded / prepared CC0 samples; {sum((ROOT / entry["path"]).stat().st_size for entry in entries):,} bytes')
