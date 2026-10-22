import { chromium } from 'playwright';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const app = await readFile('web/app.js', 'utf8');
const audioStart = app.indexOf('const combatVoices=');
const audioEnd = app.indexOf('function stopAudio()');
if (audioStart < 0 || audioEnd <= audioStart) throw new Error('Audio playback source block not found');
const playback = app.slice(audioStart, audioEnd);
const provenance = JSON.parse(await readFile('licenses/provenance/tactical-audio-provenance.json', 'utf8'));
const samples = [];
for (const file of provenance.files) {
  const content = await readFile(file.path);
  if (createHash('sha256').update(content).digest('hex') !== file.sha256) throw new Error(`Provenance hash mismatch: ${file.path}`);
  samples.push({ name: file.path.split('/').at(-1).replace('.wav', ''), base64: content.toString('base64') });
}
const browser = await chromium.launch({ channel: 'chrome', headless: true });
try {
  const page = await browser.newPage();
  const result = await page.evaluate(async ({ playback, samples }) => {
    const checks = [];
    const check = (condition, description) => { checks.push({ description, passed: Boolean(condition) }); };
    async function render(events, muted = false) {
      const audioContext = new OfflineAudioContext(2, 48000 * 2, 48000);
      const audioBuffers = new Map();
      for (const sample of samples) {
        const bytes = Uint8Array.from(atob(sample.base64), character => character.charCodeAt(0));
        audioBuffers.set(sample.name, await audioContext.decodeAudioData(bytes.buffer));
      }
      const sources = [];
      const createSource = audioContext.createBufferSource.bind(audioContext);
      audioContext.createBufferSource = () => { const source = createSource(); sources.push(source); return source; };
      const effectGain = audioContext.createGain(); effectGain.gain.value = .65; effectGain.connect(audioContext.destination);
      const combatBus = audioContext.createDynamicsCompressor();
      combatBus.threshold.value = -10; combatBus.knee.value = 9; combatBus.ratio.value = 4; combatBus.attack.value = .003; combatBus.release.value = .12; combatBus.connect(effectGain);
      const harness = new Function('audioContext', 'audioBuffers', 'audioUnlocked', 'settings', 'effectGain', 'combatBus', playback + '\nreturn {playSound, combatVoices};')(audioContext, audioBuffers, true, { muted }, effectGain, combatBus);
      for (const event of events) harness.playSound(event.name, event);
      const voicesBefore = harness.combatVoices.length;
      const selected = sources.map(source => [...audioBuffers].find(([, buffer]) => source.buffer === buffer)?.[0]);
      const rates = sources.map(source => source.playbackRate.value);
      const rendered = await audioContext.startRendering();
      const channels = [rendered.getChannelData(0), rendered.getChannelData(1)];
      const energy = channels.map(values => values.reduce((total, value) => total + value * value, 0));
      let peak = 0;
      for (const channel of channels) for (const value of channel) peak = Math.max(peak, Math.abs(value));
      return { voicesBefore, voicesAfter: harness.combatVoices.length, selected, rates, energy, peak, buffers: audioBuffers.size };
    }
    const left = await render([{ name: 'shot', event_seq: 1, attacker_id: 'alpha', pan: -.8 }]);
    check(left.buffers === samples.length && left.peak > .02, 'All provenance-listed PCM assets decode and produce audible native Web Audio output');
    check(left.energy[0] > left.energy[1] * 4, 'A left-side shot places substantially more energy in the left channel');
    const right = await render([{ name: 'shot', event_seq: 1, attacker_id: 'alpha', pan: .8 }]);
    check(right.energy[1] > right.energy[0] * 4, 'Right-side stereo placement is symmetrical');
    check(left.selected[0] === right.selected[0] && left.rates[0] === right.rates[0], 'Identical event IDs retain the same sample and pitch for replays');
    const burst = await render(Array.from({ length: 31 }, (_, index) => ({ name: 'shot', event_seq: index + 1, attacker_id: 'alpha' })));
    check(burst.selected.length === 31 && new Set(burst.selected).size === 4, 'Every shot is instantiated across all four actual recording takes');
    check(burst.voicesBefore === 12 && burst.voicesAfter === 0, 'Voice budget caps old tails and releases every completed audio node');
    check(burst.rates.every(rate => rate >= .9879 && rate <= 1.0121), 'Pitch variation stays within 1.2 percent of the recorded take');
    check(burst.peak <= 1, 'Even a 31-shot stress mix remains below digital clipping');
    const muted = await render([{ name: 'shot', event_seq: 1 }], true);
    check(muted.selected.length === 0 && muted.peak === 0, 'Mute prevents all sample playback');
    return { checks, peakStress: burst.peak, passed: checks.every(item => item.passed) };
  }, { playback, samples });
  await mkdir('tests/artifacts', { recursive: true });
  await writeFile('tests/artifacts/audio-playback-report.json', JSON.stringify(result, null, 2));
  for (const check of result.checks) console.log(`${check.passed ? 'PASS' : 'FAIL'} ${check.description}`);
  console.log(`BREACH_AUDIO_PLAYBACK_RESULT checks=${result.checks.length} failures=${result.checks.filter(item => !item.passed).length} stress_peak=${result.peakStress}`);
  if (!result.passed) process.exitCode = 1;
} finally { await browser.close(); }
