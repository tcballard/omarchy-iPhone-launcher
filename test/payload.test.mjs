import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { makePayload, validateManifest } from '../ios/scripts/payload.mjs';

test('phone payload reconstructs the disk exactly across part boundaries', async () => {
  const root = await mkdtemp(join(tmpdir(), 'omarchy-payload-'));
  try {
    const bundle = join(root, 'vm.utm');
    await mkdir(join(bundle, 'Data'), { recursive: true });
    const disk = Buffer.from('Test a final short part and exact split boundaries.');
    await writeFile(join(bundle, 'Data', 'omarchy.qcow2'), disk);
    await writeFile(join(bundle, 'config.plist'), '<plist/>');
    const output = join(root, 'payload');
    const manifest = await makePayload(bundle, output, 'test-tag', 7);
    const rebuilt = Buffer.concat(await Promise.all(manifest.parts.map(p => readFile(join(output, new URL(p.url).pathname.split('/').at(-1))))));
    assert.deepEqual(rebuilt, disk);
    assert.equal(manifest.imageSHA256, createHash('sha256').update(disk).digest('hex'));
    for (const part of manifest.parts) {
      const bytes = await readFile(join(output, new URL(part.url).pathname.split('/').at(-1)));
      assert.equal(bytes.length, part.bytes);
      assert.equal(part.sha256, createHash('sha256').update(bytes).digest('hex'));
    }
    assert.throws(() => validateManifest({ ...manifest, imageBytes: disk.length + 1 }));
    assert.throws(() => validateManifest({ ...manifest, parts: [{ ...manifest.parts[0], url: 'http://evil.example/disk' }] }));
    await assert.rejects(() => makePayload(bundle, output, 'test-tag', 7), /EEXIST/);
  } finally { await rm(root, { recursive: true, force: true }); }
});
