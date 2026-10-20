import { randomUUID, randomBytes } from 'node:crypto';

export function makeConfig({ memory = 2048, cores = 2, graphics = 'virgl' } = {}) {
  if (!Number.isInteger(memory) || memory < 1024 || memory > 4096)
    throw new Error('Memory must be 1024–4096 MiB.');
  if (!Number.isInteger(cores) || cores < 1 || cores > 4)
    throw new Error('Cores must be 1–4.');
  if (!['virgl', 'software'].includes(graphics)) throw new Error('Unknown graphics profile.');
  const hardware = graphics === 'virgl' ? 'virtio-ramfb-gl' : 'virtio-ramfb';
  const mac = ['02', ...randomBytes(5).toString('hex').match(/../g)].join(':');
  return {
    Backend: 'QEMU', ConfigurationVersion: 4,
    Information: {
      Name: 'iPhomarchy', UUID: randomUUID(), Icon: 'arch-linux', IconCustom: false,
      Notes: 'Experimental local ARM64 Omarchy VM for iPhone. Use UTM with JIT. Not device-tested. '
        + 'First boot creates your account. No shared password. Shut Linux down before closing UTM.'
    },
    System: {
      Architecture: 'aarch64', Target: 'virt', CPU: 'cortex-a72',
      CPUFlagsAdd: [], CPUFlagsRemove: [], CPUCount: cores,
      ForceMulticore: false, MemorySize: memory, JITCacheSize: 128
    },
    QEMU: {
      DebugLog: true, UEFIBoot: true, RNGDevice: true, BalloonDevice: false,
      TPMDevice: false, Hypervisor: false, TSO: false,
      RTCLocalTime: false, PS2Controller: false,
      MachinePropertyOverride: 'gic-version=3',
      AdditionalArguments: [
        '-global', `${hardware}.xres=1280`,
        '-global', `${hardware}.yres=720`,
        '-smbios', 'type=11,value=io.systemd.credential.binary:tryomarchy.host='
          + Buffer.from('tryomarchy.locale=en_US.UTF-8 tryomarchy.timezone=UTC').toString('base64')
      ]
    },
    Input: { UsbBusSupport: '3.0', UsbSharing: false, MaximumUsbShare: 0 },
    Sharing: { DirectoryShareMode: 'None', DirectoryShareReadOnly: true, ClipboardSharing: false },
    Display: [{ Hardware: hardware, DynamicResolution: false,
      UpscalingFilter: 'Linear', DownscalingFilter: 'Linear', NativeResolution: false }],
    Drive: [{ ImageName: 'omarchy.qcow2', ImageType: 'Disk', Interface: 'VirtIO',
      InterfaceVersion: 1, Identifier: randomUUID(), ReadOnly: false }],
    Network: [{ Mode: 'Emulated', Hardware: 'virtio-net-pci', MacAddress: mac,
      IsolateFromHost: false, PortForward: [] }],
    Serial: [], Sound: []
  };
}

function xmlEscape(value) {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}

export function plist(value) {
  function encode(item, depth) {
    const indent = '  '.repeat(depth);
    if (typeof item === 'boolean') return `${indent}<${item ? 'true' : 'false'}/>`;
    if (typeof item === 'number' && Number.isSafeInteger(item)) return `${indent}<integer>${item}</integer>`;
    if (typeof item === 'string') return `${indent}<string>${xmlEscape(item)}</string>`;
    if (Array.isArray(item)) return `${indent}<array>\n${item.map(x => encode(x, depth + 1)).join('\n')}\n${indent}</array>`;
    if (item && typeof item === 'object') return `${indent}<dict>\n${Object.entries(item).map(([key, val]) =>
      `${'  '.repeat(depth + 1)}<key>${xmlEscape(key)}</key>\n${encode(val, depth + 1)}`).join('\n')}\n${indent}</dict>`;
    throw new TypeError('Unsupported plist value.');
  }
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
    + '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    + `<plist version="1.0">\n${encode(value, 0)}\n</plist>\n`;
}
