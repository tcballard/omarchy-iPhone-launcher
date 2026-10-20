import test from 'node:test';
import assert from 'node:assert/strict';
import { makeConfig, plist } from '../scripts/config.mjs';

test('invalid resource choices fail before a VM can be built', () => {
  for (const memory of [0, -1, 512, 8192, NaN, 2048.5]) assert.throws(() => makeConfig({ memory }));
  for (const cores of [0, -1, 5, NaN, 1.5]) assert.throws(() => makeConfig({ cores }));
  assert.throws(() => makeConfig({ graphics: 'host' }));
});

test('separate VM builds get distinct identities and unicast locally administered MACs', () => {
  const a = makeConfig(); const b = makeConfig();
  assert.notEqual(a.Information.UUID, b.Information.UUID);
  assert.notEqual(a.Network[0].MacAddress, b.Network[0].MacAddress);
  assert.equal(parseInt(a.Network[0].MacAddress.slice(0, 2), 16) & 3, 2);
  assert.notEqual(a.Drive[0].Identifier, b.Drive[0].Identifier);
});

test('plist text cannot inject XML or silently stringify unsupported values', () => {
  const encoded = plist({ '<key>': 'A&B < C > D "quoted"' });
  assert.ok(encoded.includes('&lt;key&gt;'));
  assert.ok(encoded.includes('A&amp;B &lt; C &gt; D &quot;quoted&quot;'));
  assert.throws(() => plist({ value: undefined }));
  assert.throws(() => plist({ value: 3.14 }));
});

test('guest language bootstrap works without activating the Mac cursor profile', () => {
  const config = makeConfig();
  const args = config.QEMU.AdditionalArguments;
  const credential = args[args.indexOf('-smbios') + 1];
  const value = Buffer.from(credential.split('tryomarchy.host=')[1], 'base64').toString();
  assert.match(value, /tryomarchy.locale=en_US.UTF-8/);
  assert.match(value, /tryomarchy.timezone=UTC/);
  assert.doesNotMatch(value, /(qemu_virgl|ssh_access|password|username)/);
});
