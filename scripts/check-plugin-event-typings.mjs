#!/usr/bin/env node
/**
 * Ensures listener events declared in src/definitions.ts match iOS native emissions
 * for interruption handling and recordingError payload fields.
 */

import fs from 'node:fs';
import path from 'node:path';

const definitionsPath = path.join(process.cwd(), 'src', 'definitions.ts');

if (!fs.existsSync(definitionsPath)) {
  console.error('[event-typings] ERROR: missing src/definitions.ts');
  process.exit(2);
}

const source = fs.readFileSync(definitionsPath, 'utf8');
const errors = [];

const requiredSnippets = [
  ["addListener overload for recordingInterruptionBegan", "eventName: 'recordingInterruptionBegan'"],
  ["addListener overload for recordingInterruptionEnded", "eventName: 'recordingInterruptionEnded'"],
  ['RecordingInterruptionEndedEvent interface', 'export interface RecordingInterruptionEndedEvent'],
  ['RecordingInterruptionEndedEvent.shouldResume', 'shouldResume: boolean'],
  ['RecordingErrorEvent.uri field', 'uri?: string'],
  ['iOS-only JSDoc on recordingInterruptionBegan', "eventName: 'recordingInterruptionBegan'"],
];

for (const [label, snippet] of requiredSnippets) {
  if (!source.includes(snippet)) {
    errors.push(`${label}: expected to find ${JSON.stringify(snippet)}`);
  }
}

const beganBlock = source.match(
  /Listen for the start of an audio session interruption[\s\S]*?Only emitted on iOS[\s\S]*?recordingInterruptionBegan/,
);
if (!beganBlock) {
  errors.push('recordingInterruptionBegan JSDoc must document iOS-only emission');
}

const endedBlock = source.match(
  /Listen for the end of an audio session interruption[\s\S]*?Only emitted on iOS[\s\S]*?recordingInterruptionEnded/,
);
if (!endedBlock) {
  errors.push('recordingInterruptionEnded JSDoc must document iOS-only emission');
}

const uriDoc = source.match(/export interface RecordingErrorEvent[\s\S]*?Emitted on iOS[\s\S]*?uri\?: string/);
if (!uriDoc) {
  errors.push('RecordingErrorEvent.uri JSDoc must document iOS emission');
}

if (errors.length) {
  console.error('[event-typings] FAIL');
  for (const e of errors) console.error(`- ${e}`);
  process.exit(1);
}

console.log('[event-typings] OK');
process.exit(0);
