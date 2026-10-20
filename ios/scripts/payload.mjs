import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

export function validateManifest(manifest) {
  const hash = /^[0-9a-f]{64}$/;
  if (manifest.version !== 1 || !Number.isSafeInteger(manifest.imageBytes) || manifest.imageBytes <= 0
      || manifest.imageBytes > 32 * 1073741824 || !hash.test(manifest.imageSHA256)
      || typeof manifest.configBase64 !== 'string' || !manifest.configBase64.length
      || !Array.isArray(manifest.parts) || !manifest.parts.length || manifest.parts.length > 32)
    throw new Error('Invalid payload manifest.');
  let total = 0;
  for (const part of manifest.parts) {
    const url = new URL(part.url);
    if (url.protocol !== 'https:' || url.hostname !== 'github.com'
        || !url.pathname.startsWith('/tcballard/omarchy-iPhone-launcher/releases/download/')
        || !Number.isSafeInteger(part.bytes) || part.bytes <= 0 || part.bytes > 1073741824
        || !hash.test(part.sha256)) throw new Error('Invalid payload part.');
    total += part.bytes;
  }
  if (total !== manifest.imageBytes) throw new Error('Payload length mismatch.');
}

export async function makePayload(bundle, output, releaseTag, partSize = 1073741824) {
  if (!/^[a-zA-Z0-9._-]+$/.test(releaseTag)) throw new Error('Invalid release tag.');
  if (!Number.isSafeInteger(partSize) || partSize <= 0 || partSize > 1073741824) throw new Error('Invalid part size.');
  await mkdir(output, { recursive: true });
  const whole = createHash('sha256');
  const parts = [];
  let stream, partHash, bytes = 0, imageBytes = 0;
  async function start() {
    const name = `omarchy.qcow2.part-${String(parts.length + 1).padStart(3, '0')}`;
    stream = createWriteStream(join(output, name), { flags: 'wx' });
    stream.on('error', () => {});
    partHash = createHash('sha256');
    bytes = 0;
    return name;
  }
  async function finish(name) {
    const completion = once(stream, 'finish');
    stream.end();
    await completion;
    parts.push({ url: `https://github.com/tcballard/omarchy-iPhone-launcher/releases/download/${releaseTag}/${name}`,
      bytes, sha256: partHash.digest('hex') });
    stream = undefined;
  }
  let name;
  for await (const chunk of createReadStream(join(bundle, 'Data', 'omarchy.qcow2'))) {
    whole.update(chunk);
    imageBytes += chunk.length;
    let offset = 0;
    while (offset < chunk.length) {
      if (!stream) name = await start();
      const piece = chunk.subarray(offset, Math.min(chunk.length, offset + partSize - bytes));
      partHash.update(piece);
      if (!stream.write(piece)) await once(stream, 'drain');
      offset += piece.length;
      bytes += piece.length;
      if (bytes === partSize) await finish(name);
    }
  }
  if (stream) await finish(name);
  const manifest = { version: 1, imageBytes, imageSHA256: whole.digest('hex'),
    configBase64: (await readFile(join(bundle, 'config.plist'))).toString('base64'), parts };
  validateManifest(manifest);
  await writeFile(join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx' });
  return manifest;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [bundle, output, tag] = process.argv.slice(2);
  if (!bundle || !output || !tag) throw new Error('Usage: node ios/scripts/payload.mjs BUNDLE OUTPUT RELEASE_TAG');
  const result = await makePayload(resolve(bundle), resolve(output), tag);
  console.log(`Prepared ${result.parts.length} verified image parts (${result.imageBytes} bytes).`);
}
