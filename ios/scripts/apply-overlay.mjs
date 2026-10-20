import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { validateManifest } from './payload.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const [utmArg, manifestArg] = process.argv.slice(2);
if (!utmArg || !manifestArg) throw new Error('Usage: node ios/scripts/apply-overlay.mjs UTM_SOURCE MANIFEST');
const utm = resolve(utmArg);
const lock = JSON.parse(await readFile(join(root, 'ios/upstream.json'), 'utf8'));
const commit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: utm, encoding: 'utf8' }).trim();
if (commit !== lock.commit) throw new Error(`UTM must be pinned to ${lock.commit}, found ${commit}.`);
const manifestText = await readFile(resolve(manifestArg), 'utf8');
validateManifest(JSON.parse(manifestText));
const viewPath = join(utm, 'Platform/iOS/UTMSingleWindowView.swift');
let view = await readFile(viewPath, 'utf8');
const call = 'ContentView().environmentObject(data!)';
if (view.split(call).length !== 2 || view.includes('struct OmarchyHomeView'))
  throw new Error('Unexpected UTM app entry point; use a clean checkout.');
view = view.replace(call, 'OmarchyHomeView().environmentObject(data!)');
const installer = await readFile(join(root, 'ios/OmarchyInstaller.swift'), 'utf8');
const home = (await readFile(join(root, 'ios/OmarchyHomeView.swift'), 'utf8'))
  .replace('__OMARCHY_MANIFEST_BASE64__', Buffer.from(manifestText).toString('base64'));
await writeFile(viewPath, view + '\n' + installer + '\n' + home);
let info = await readFile(join(utm, 'Platform/iOS/Info.plist'), 'utf8');
info = info.replace('<key>CFBundleName</key>\n\t<string>$(PRODUCT_NAME)</string>',
  '<key>CFBundleName</key>\n\t<string>iPhomarchy</string>\n\t<key>CFBundleDisplayName</key>\n\t<string>iPhomarchy</string>');
info = info.replace('<string>UTM</string>', '<string>iphomarchy</string>');
await writeFile(join(utm, 'Platform/iOS/Info.plist'), info);
const buildNumber = process.env.GITHUB_RUN_NUMBER || '1';
if (!/^[0-9]+$/.test(buildNumber)) throw new Error('Invalid build number.');
await writeFile(join(utm, 'CodeSigning.xcconfig'),
  `PRODUCT_BUNDLE_PREFIX = ${lock.bundlePrefix}\nDEVELOPER_ACCOUNT_PAID = YES\nMARKETING_VERSION = 0.1.0\nCURRENT_PROJECT_VERSION = ${buildNumber}\n`);
const buildScriptPath = join(utm, 'scripts/build_utm.sh');
let buildScript = await readFile(buildScriptPath, 'utf8');
if (!buildScript.includes('CODE_SIGNING_ALLOWED=NO $TEAM_IDENTIFIER_PREFIX'))
  throw new Error('Unexpected UTM archive invocation.');
buildScript = buildScript.replace('CODE_SIGNING_ALLOWED=NO $TEAM_IDENTIFIER_PREFIX',
  'CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=26.0 $TEAM_IDENTIFIER_PREFIX');
await writeFile(buildScriptPath, buildScript);
console.log(`Applied iPhomarchy launcher to UTM ${lock.version}.`);
