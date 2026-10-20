#!/usr/bin/env node
import { createReadStream } from 'node:fs';
import { mkdir, readFile, writeFile, rename, stat, rm, access } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { once } from 'node:events';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeConfig, plist } from './config.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const lock = JSON.parse(await readFile(join(root, 'source-lock.json'), 'utf8'));
const args = process.argv.slice(2);
function option(name, fallback) {
  const index = args.indexOf(name);
  return index < 0 ? fallback : args[index + 1];
}
if (args.includes('--help')) {
  console.log('node scripts/build.mjs [--cache PATH] [--out PATH] [--memory 2048] [--cores 2] [--graphics virgl|software]');
  console.log('Needs curl, zstd, qemu-img and zip. Downloads ~3 GB; allow 25 GB free during the build.');
  process.exit(0);
}
const known = ['--cache', '--out', '--memory', '--cores', '--graphics'];
for (let i = 0; i < args.length; i += 2) {
  if (!known.includes(args[i]) || !args[i + 1] || args[i + 1].startsWith('--'))
    throw new Error(`Invalid option: ${args[i]}. See --help.`);
}
const cache = resolve(option('--cache', join(root, '.cache')));
const out = resolve(option('--out', join(root, 'dist')));
const config = makeConfig({ memory: Number(option('--memory', '2048')),
  cores: Number(option('--cores', '2')), graphics: option('--graphics', 'virgl') });
const bundle = join(out, 'iPhomarchy.utm');
const archive = join(out, 'iPhomarchy.utm.zip');

async function run(command, argv, options = {}) {
  const child = spawn(command, argv, { stdio: 'inherit', ...options });
  const [code, signal] = await once(child, 'exit');
  if (code !== 0) throw new Error(`${command} failed (${signal || code}).`);
}
async function exists(path) { try { await access(path); return true; } catch { return false; } }
async function sha256(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}
async function verifyPart(part, path) {
  return await exists(path) && (await stat(path)).size === part.bytes && await sha256(path) === part.sha256;
}
async function decompress(paths, target) {
  const temporary = `${target}.partial`;
  await rm(temporary, { force: true });
  const child = spawn('zstd', ['-q', '-d', '--sparse', '-o', temporary], { stdio: ['pipe', 'inherit', 'inherit'] });
  // Register completion before writing so early decompressor failures are observed.
  const completion = once(child, 'exit');
  child.stdin.on('error', () => {});
  try {
    for (const path of paths) {
      for await (const chunk of createReadStream(path)) {
        if (child.stdin.destroyed) throw new Error('Decompressor closed its input.');
        if (!child.stdin.write(chunk)) await once(child.stdin, 'drain');
      }
    }
    child.stdin.end();
    const [code] = await completion;
    if (code !== 0) throw new Error('Image decompression failed.');
    if ((await stat(temporary)).size !== lock.imageBytes) throw new Error('Unexpected image size.');
    await rename(temporary, target);
  } catch (error) {
    child.kill();
    await completion.catch(() => {});
    await rm(temporary, { force: true });
    throw error;
  }
}

try {
  for (const tool of ['curl', 'zstd', 'qemu-img', 'zip']) {
    execFileSync(tool, tool === 'qemu-img' ? ['--version'] : tool === 'zip' ? ['-v'] : ['--version'], { stdio: 'ignore' });
  }
  if (await exists(bundle) || await exists(archive)) throw new Error(`Output already exists in ${out}. Choose a new --out directory.`);
  await mkdir(cache, { recursive: true });
  await mkdir(out, { recursive: true });
  const paths = [];
  for (const part of lock.parts) {
    const path = join(cache, part.name);
    paths.push(path);
    if (await verifyPart(part, path)) { console.log(`Verified cached ${part.name}`); continue; }
    // Preserve interrupted downloads separately; never accept an unverified final file.
    await rm(path, { force: true });
    const temporary = `${path}.partial`;
    console.log(`Downloading ${part.name}`);
    await run('curl', ['--fail', '--location', '--retry', '3', '--connect-timeout', '20',
      '--continue-at', '-', '--output', temporary,
      `https://github.com/${lock.repository}/releases/download/${lock.release}/${part.name}`]);
    if (!await verifyPart(part, temporary)) {
      await rm(temporary, { force: true });
      throw new Error(`Checksum or size mismatch: ${part.name}. Run again to download a fresh copy.`);
    }
    await rename(temporary, path);
  }
  const raw = join(cache, lock.imageName);
  const metadata = join(cache, `${lock.imageName}.verified.json`);
  let rawIsVerified = false;
  if (await exists(raw) && await exists(metadata)) {
    try {
      const previous = JSON.parse(await readFile(metadata, 'utf8'));
      rawIsVerified = previous.parts === lock.parts.map(x => x.sha256).join(':')
        && (await stat(raw)).size === lock.imageBytes && previous.sha256 === lock.factorySha256
        && lock.factorySha256 === await sha256(raw);
    } catch {}
  }
  if (!rawIsVerified) {
    console.log('Decompressing the verified factory image…');
    await decompress(paths, raw);
    const factoryHash = await sha256(raw);
    if (factoryHash !== lock.factorySha256) throw new Error('Decompressed factory SHA-256 mismatch.');
    await writeFile(metadata, JSON.stringify({ parts: lock.parts.map(x => x.sha256).join(':'), sha256: factoryHash }, null, 2));
  }
  console.log('Converting to a standalone, compact QCOW2 disk…');
  const staging = join(out, 'iPhomarchy.utm.partial');
  if (await exists(staging)) throw new Error(`Previous staging directory exists: ${staging}. Inspect or remove it before retrying.`);
  await mkdir(join(staging, 'Data'), { recursive: true });
  await run('qemu-img', ['convert', '-p', '-f', 'raw', '-O', 'qcow2', '-c',
    '-o', 'compat=1.1,compression_type=zlib', raw, join(staging, 'Data', 'omarchy.qcow2')]);
  await run('qemu-img', ['check', '-f', 'qcow2', join(staging, 'Data', 'omarchy.qcow2')]);
  await writeFile(join(staging, 'config.plist'), plist(config));
  await writeFile(join(staging, 'README.txt'), await readFile(join(root, 'QUICKSTART.txt')));
  await writeFile(join(staging, 'provenance.json'), JSON.stringify({
    ...lock, factorySha256: JSON.parse(await readFile(metadata, 'utf8')).sha256,
    diskSha256: await sha256(join(staging, 'Data', 'omarchy.qcow2')),
    configuration: { memoryMiB: config.System.MemorySize, cores: config.System.CPUCount, graphics: option('--graphics', 'virgl') },
    validation: { qcow2Check: 'passed', iphoneBoot: 'not tested', utmImport: 'not tested' }
  }, null, 2));
  await rename(staging, bundle);
  console.log('Packaging the UTM import…');
  const temporaryZip = join(out, 'iPhomarchy.partial.zip');
  await rm(temporaryZip, { force: true });
  await run('zip', ['-q', '-0', temporaryZip,
    'iPhomarchy.utm/config.plist', 'iPhomarchy.utm/README.txt',
    'iPhomarchy.utm/provenance.json', 'iPhomarchy.utm/Data/omarchy.qcow2'], { cwd: out });
  await rename(temporaryZip, archive);
  await writeFile(`${archive}.sha256`, `${await sha256(archive)}  iPhomarchy.utm.zip\n`);
  console.log(`Created ${archive}`);
  console.log('iPhone import, graphics and performance still require device testing.');
} catch (error) {
  console.error(`iPhomarchy: ${error.message}`);
  process.exitCode = 1;
}
