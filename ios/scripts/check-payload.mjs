import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { validateManifest } from './payload.mjs';

const [expectedPath, actualPath] = process.argv.slice(2);
const expected = JSON.parse(await readFile(expectedPath, 'utf8'));
const actual = JSON.parse(await readFile(actualPath, 'utf8'));
for (const manifest of [expected, actual]) validateManifest(manifest);
for (const field of ['version', 'imageBytes', 'imageSHA256', 'parts']) {
  assert.deepEqual(actual[field], expected[field], `The rebuilt disk differs from the pinned phone image: ${field}`);
}
console.log('Rebuilt image matches the pinned disk and every download part.');
