import { spawn } from 'node:child_process';
import { access, mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { sourceFingerprint } from '../scripts/build_fingerprint.mjs';

const startedAt = new Date().toISOString();
const fingerprint = await sourceFingerprint();

// Godot can log a script runtime error and still exit 0. Treat that as a test
// failure, and require the explicit runner summary as proof it reached the end.
const bundled = resolve('.tools/Godot.app/Contents/MacOS/Godot');
let engine = process.env.GODOT_BIN;
if (!engine) {
  try { await access(bundled); engine = bundled; }
  catch { engine = 'godot'; }
}
const userArguments = process.argv.slice(2);
const suites = userArguments.length ? ['test_runner'] : ['test_runner', 'mission_playthrough', 'command_schema_test', 'movement_planning_test', 'combat_feedback_test', 'presentation_state_test', 'presentation_motion_test', 'actor_visual_test', 'audio_dispatch_test', 'presentation_lab_test', 'door_collision_test', 'spatial_consistency_test', 'navigation_optimization_test', 'loading_transition_test', 'simulation_control_test', 'movement_audio_test', 'world_readability_test', 'mission_variants_test', 'extra_missions_test', 'difficulty_test', 'visibility_field_test', 'visibility_optimization_test', 'quality_lifecycle_test', 'quality_soak_test', 'sustained_control_test', 'sustained_combat_test', 'sustained_replay_test', 'sustained_catalog_test', 'mission_type_rules_test', 'context_input_test', 'door_defense_benchmark', 'safe_area_camera_test', 'camera_pan_test', 'bindings_input_test', 'room_clear_test', 'tactical_response_test', 'movement_reliability_test', 'door_realism_test', 'spatial_realism_test', 'cognition_acoustic_test', 'combat_state_test', 'realism_maps_test', 'realism_contract_test', 'realism_integration_test'];
async function runSuite(name) {
  return new Promise(resolveSuite => {
    const child = spawn(engine, ['--headless', '--path', 'game', '--script', `res://tests/${name}.gd`, ...(userArguments.length ? ['--', ...userArguments] : [])], { stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    let spawnError;
    for (const stream of [child.stdout, child.stderr]) stream.on('data', chunk => {
      const text = chunk.toString();
      output += text;
      // Report progress while long fixed-seed suites run; keep the complete
      // per-suite capture and strict completion/error checks unchanged.
      process.stdout.write(text);
    });
    child.on('error', error => { spawnError = error.message; });
    child.on('close', code => {
      const summary = output.match(/BREACH_[A-Z_]+_RESULT checks=(\d+) failures=(\d+)/);
      const engineError = /SCRIPT ERROR|(^|\n)ERROR:|Parse Error|Failed loading resource/.test(output);
      const passed = !spawnError && code === 0 && summary && Number(summary[1]) > 0 && Number(summary[2]) === 0 && !engineError;
      if (!passed) console.error(`Suite ${name} failed: ${spawnError || 'engine error, failed assertion or missing summary'}`);
      resolveSuite({ name, passed: Boolean(passed), exitCode: code, checks: summary ? Number(summary[1]) : 0, failures: summary ? Number(summary[2]) : 1, engineError, spawnError, output });
    });
  });
}
if (!userArguments.length) suites.push('crosspc_optimization_test', 'large_map_navigation_test', 'large_map_replay_test', 'large_map_extent_test', 'historical_render_test', 'wall_render_contract_test', 'historical_catalog_test', 'historical_elevation_test', 'elevated_floor_replay_test', 'visibility_bounds_test', 'historical_surface_render_test');
if (!userArguments.length) suites.push('steam_optimization_contract_test', 'render_optimization_test', 'render_pose_optimization_test', 'actor_event_cursor_test', 'idle_render_test', 'catalog_cache_test', 'replay_main_optimization_test');
if (!userArguments.length) suites.push('door_entry_test');
if (!userArguments.length) suites.push('quiet_lantern_map_test');
if (!userArguments.length) suites.push('door_traffic_test');
if (!userArguments.length) suites.push('hit_reaction_test');
if (!userArguments.length) suites.push('cqb_doctrine_baseline_test');
if (!userArguments.length) suites.push('cqb_doctrine_schema_test', 'cqb_contact_test', 'cqb_contact_replay_test');
if (!userArguments.length) suites.push('room_drill_geometry_test', 'room_drill_test', 'room_drill_replay_test', 'room_drill_main_test');
if (!userArguments.length) suites.push('room_control_test', 'room_reformation_test', 'room_state_schema_test', 'room_state_replay_test', 'room_control_main_test', 'room_control_browser_preflight_test');
if (!userArguments.length) suites.push('room_observation_optimization_test');
if (!userArguments.length) suites.push('formation_geometry_test', 'formation_test', 'team_communication_test', 'noise_discipline_schema_test', 'wall_contact_acoustic_test', 'formation_replay_test', 'formation_combat_test', 'communication_gameplay_test', 'formation_main_test', 'formation_browser_preflight_test');
if (!userArguments.length) suites.push('roe_schema_test', 'roe_catalog_test', 'roe_gameplay_test', 'roe_replay_test', 'roe_main_test', 'roe_browser_preflight_test', 'observed_statistics_filter_test');
if (!userArguments.length) suites.push('room_doctrine_test', 'room_doctrine_simulation_test', 'room_doctrine_replay_test', 'prior_attempt_test', 'prior_attempt_main_test');
if (!userArguments.length) suites.push('cqb_seed_test', 'cqb_catalog_test', 'cqb_content_geometry_test', 'historical_doctrine_test', 'known_door_planning_test', 'drill_lane_recovery_test', 'shoot_house_test');
if (!userArguments.length) suites.push('equipment_catalog_test', 'customization_accuracy_benchmark', 'customization_tactics_test', 'customization_replay_test', 'customization_bridge_test', 'operator_visual_test', 'customization_review_test');
if (!userArguments.length) suites.push('enemy_strength_test');
if (!userArguments.length) suites.push('actor_hit_feedback_test');
if (!userArguments.length) suites.push('hit_feedback_test', 'first_sighting_test', 'friendly_damage_feedback_test');
// Large navigation/render suites retain substantial Godot data while running.
// A small queue avoids starting fifty engines and exhausting system memory.
const requestedWorkers = Number(process.env.BREACH_TEST_WORKERS || 4);
const workerCount = Math.min(6, Math.max(1, Number.isFinite(requestedWorkers) ? Math.floor(requestedWorkers) : 4), suites.length);
const results = new Array(suites.length);
// Start the longest fixed-seed suites first so short suites can fill their tail.
// Results retain registration order, and every suite still runs exactly once.
const longSuites = ['cqb_contact_test', 'cqb_doctrine_baseline_test', 'formation_combat_test', 'formation_replay_test', 'room_control_test', 'room_drill_replay_test'];
const schedule = [...longSuites.map(name => suites.indexOf(name)).filter(index => index >= 0),
  ...suites.map((name, index) => longSuites.includes(name) ? -1 : index).filter(index => index >= 0)];
let nextSuite = 0;
await Promise.all(Array.from({ length: workerCount }, async () => {
  while (nextSuite < schedule.length) {
    const index = schedule[nextSuite++];
    results[index] = await runSuite(suites[index]);
  }
}));
const checks = results.reduce((sum, result) => sum + result.checks, 0);
const failures = results.reduce((sum, result) => sum + result.failures, 0);
const sourceUnchanged = fingerprint.sourceHash === (await sourceFingerprint()).sourceHash;
const passed = results.every(result => result.passed) && sourceUnchanged;
if (!sourceUnchanged) console.error('Game sources changed while the suites were running; rerun against the final source.');
console.log(`BREACH_TEST_SUMMARY suites=${results.length} checks=${checks} failures=${failures} status=${passed ? 'PASS' : 'FAIL'}`);
await mkdir('tests/artifacts', { recursive: true });
await writeFile('tests/artifacts/headless-report.json', JSON.stringify({ startedAt, testedAt: new Date().toISOString(), fullSuite: !userArguments.length, fingerprint, sourceUnchanged, engine, checks, failures, passed, suites: results }, null, 2));
process.exitCode = passed ? 0 : 1;
