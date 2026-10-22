"""Compare identical paused battle frames with flash enabled/disabled."""
from pathlib import Path
from PIL import Image, ImageChops
import json
out=Path(__file__).parent/'artifacts/combat-effects'
normal=Image.open(out/'combat-effects.png').convert('RGB')
reduced=Image.open(out/'combat-reduced-flash.png').convert('RGB')
# Fixed 1440x900 tutorial camera, first shot muzzle; excludes the HUD.
delta=ImageChops.difference(normal,reduced).crop((480,565,540,620))
bright=sum(max(pixel)>50 for pixel in delta.get_flattened_data())
assert bright>=60, f'Muzzle effect is not sufficiently visible: {bright} bright pixels'
report=json.loads((out/'report.json').read_text())
report['visibility']={'muzzlePixelsOver50':bright,'minimum':60,'passed':True}
(out/'report.json').write_text(json.dumps(report,indent=2))
print(f'PASS muzzle visibility: {bright} high-contrast pixels')
