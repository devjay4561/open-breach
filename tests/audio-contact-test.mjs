import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import vm from 'node:vm';

let checks = 0;
const check = (condition, message) => { checks++; assert(condition, message); };
const source = await readFile('web/app.js', 'utf8');
const code = source.slice(source.indexOf('const combatVoices='), source.indexOf('function stopAudio()'));
check(code.includes('function playSound'), 'Tests use the production audio mixer');
const started = [], sources = [];
const node = () => ({ connect() {}, disconnect() {} });
const audioContext = {
  currentTime: 1,
  createBufferSource() {
    const source = { ...node(), playbackRate: { value: 1 }, stopped: false, start() { started.push(this); }, stop() { this.stopped = true; } };
    sources.push(source);
    return source;
  },
  createGain() { return { ...node(), gain: { value: 1, cancelScheduledValues() {}, setTargetAtTime() {} } }; },
  createStereoPanner() { return { ...node(), pan: { value: 0 } }; },
};
const provenance = JSON.parse(await readFile('licenses/provenance/tactical-audio-provenance.json', 'utf8'));
const buffers = new Map(provenance.files.map(entry => [entry.path.split('/').at(-1).replace('.wav', ''), { file: entry.path }]));
const sandbox = { audioContext, audioBuffers: buffers, audioUnlocked: true, settings: { muted: false }, combatBus: node(), effectGain: node() };
vm.createContext(sandbox);
vm.runInContext(`${code}\nglobalThis.audioTest={playSound,soundPools,combatVoices,contactVoices};`, sandbox);
const { playSound, combatVoices, contactVoices } = sandbox.audioTest;
for (let i = 1; i <= 5; i++) playSound('footstep_wood', { event_seq: i, attacker_id: 'alpha' });
check(new Set(started.map(x => x.buffer.file)).size === 5, 'Five consecutive foot contacts use five prepared recordings');
check(started.every(x => x.playbackRate.value >= 0.982 && x.playbackRate.value <= 1.018), 'Footstep pitch variation stays subtle and bounded');
playSound('shot', { event_seq: 20, attacker_id: 'alpha' });
const shot = started.at(-1);
for (let i = 0; i < 30; i++) playSound('footstep_concrete', { event_seq: i, attacker_id: 'bravo' });
check(contactVoices.length === 8, 'Contact polyphony stays within its independent eight-voice budget');
check(combatVoices.length === 1 && !shot.stopped, 'A moving squad never steals the shot voice');
check(sources.filter(x => x.stopped).length >= 27, 'Old contact tails yield without unbounded voice accumulation');
for (let i = 1; i <= 3; i++) playSound('door', { event_seq: i, attacker_id: 'd1' });
check(new Set(started.slice(-3).map(x => x.buffer.file)).size === 3, 'Door completion uses three prepared wood-contact variations');
playSound('door_latch', { event_seq: 11, attacker_id: 'd1' });
const latch = started.at(-1);
playSound('door_latch', { event_seq: 11, attacker_id: 'd1' });
check(latch.buffer.file === started.at(-1).buffer.file && latch.playbackRate.value === started.at(-1).playbackRate.value, 'Replay contact IDs choose deterministic sample and pitch');
const count = started.length;
sandbox.settings.muted = true;
playSound('footstep_wood', { event_seq: 9 });
sandbox.settings.muted = false;
sandbox.audioUnlocked = false;
playSound('door_latch', { event_seq: 9 });
check(started.length === count, 'Muted and locked audio contexts do not start contacts');

const measurements = [];
for (const entry of provenance.files.filter(x => x.pack === 'kenney-impact-sounds')) {
  const wav = await readFile(entry.path);
  check(createHash('sha256').update(wav).digest('hex') === entry.sha256, `Provenance hash matches ${entry.path}`);
  check(wav.toString('ascii', 0, 4) === 'RIFF' && wav.toString('ascii', 8, 12) === 'WAVE', 'Imported sample is a local WAV recording');
  let format, pcm;
  for (let at = 12; at + 8 <= wav.length;) {
    const id = wav.toString('ascii', at, at + 4), size = wav.readUInt32LE(at + 4);
    if (id === 'fmt ') format = wav.subarray(at + 8, at + 8 + size);
    if (id === 'data') pcm = wav.subarray(at + 8, at + 8 + size);
    at += 8 + size + size % 2;
  }
  check(format && pcm && format.readUInt16LE(0) === 1 && format.readUInt16LE(2) === 1 && format.readUInt32LE(4) === 32000 && format.readUInt16LE(14) === 16, 'Contact import uses mono 32 kHz PCM16');
  let peak = 0, squares = 0;
  for (let at = 0; at < pcm.length; at += 2) {
    const value = pcm.readInt16LE(at) / 32768;
    peak = Math.max(peak, Math.abs(value));
    squares += value * value;
  }
  const seconds = pcm.length / 2 / 32000;
  check(peak > 0.01 && peak < 0.9 && seconds > 0.04 && seconds < 1, 'Prepared contact is audible, short and has no digital clipping');
  measurements.push({ path: entry.path, durationSeconds: seconds, peak, rms: Math.sqrt(squares / (pcm.length / 2)) });
}
await writeFile('tests/artifacts/audio-contact-report.json', JSON.stringify({ checks, failures: 0, passed: true, measurements }, null, 2));
console.log(`BREACH_AUDIO_CONTACT_RESULT checks=${checks} failures=0`);
