"""Add the integrated services' bundle metadata without requiring Apple's plist tools."""
import pathlib
import plistlib
import sys

utm = pathlib.Path(sys.argv[1])
bundle = sys.argv[2]

def update(path, modify):
    value = plistlib.loads(path.read_bytes())
    modify(value)
    path.write_bytes(plistlib.dumps(value, sort_keys=False))

def app_info(value):
    value["NSLocalNetworkUsageDescription"] = "iPhomarchy pairs with this iPhone and connects to its developer services to enable acceleration."
    for service in ("_remotepairing-pairable-host._tcp", "_remotepairing._tcp"):
        if service not in value["NSBonjourServices"]:
            value["NSBonjourServices"].append(service)
    if "processing" not in value["UIBackgroundModes"]:
        value["UIBackgroundModes"].append("processing")
    value["BGTaskSchedulerPermittedIdentifiers"] = [bundle + ".pairing.*"]

update(utm / "Platform/iOS/Info.plist", app_info)
update(utm / "Platform/iOS/iOS.entitlements", lambda value: value.update({
    "com.apple.developer.networking.networkextension": ["packet-tunnel-provider"],
}))
