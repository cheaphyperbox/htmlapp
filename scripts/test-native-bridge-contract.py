#!/usr/bin/env python3
"""Verify native dispatch, SDK, registry, viewport and Forge architecture consistency."""
import pathlib
import re
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
read = lambda path: (root / path).read_text(encoding="utf-8")
native = read("HTMLAppV3/NativeAPIBridge.swift")
registry = read("HTMLAppV3/HTMLAppBridgeRegistry.swift")
editor = read("HTMLAppV3/EditorWeb.swift")
verifier = read("HTMLAppV3/HTMLRuntimeVerifier.swift")
forge = read("HTMLAppV3/AIGenerationService.swift")
product = read("HTMLAppV3/ForgeProductContract.swift")
model = read("HTMLAppV3/ForgeSemanticAppModel.swift")

dispatcher = native.split("        switch method {", 1)[1].split(
    '        default:\n            reject(id, code: "unsupported_method"', 1
)[0]
extract_methods = lambda text: set(re.findall(r'"([A-Za-z][A-Za-z0-9]*\.[A-Za-z][A-Za-z0-9]*)"', text))
implemented = set()
for line in re.findall(r"case\s+[^\n]+", dispatcher):
    implemented.update(extract_methods(line))

registry_block = registry.split("static let methods: [String] = [", 1)[1].split(
    "static let methodSet", 1
)[0]
declared = extract_methods(registry_block)
assert implemented == declared, (
    "Native bridge registry drift.\nUnregistered Swift methods: "
    + repr(sorted(implemented - declared))
    + "\nNonexistent declared methods: " + repr(sorted(declared - implemented))
)

sdk = native.split("enum HTMLNativeAPIScript {", 1)[1]
sdk_calls = set(re.findall(r"call\('([^']+)'", sdk))
assert sdk_calls <= declared, f"Unregistered SDK calls: {sorted(sdk_calls - declared)}"
assert len(declared) >= 120, "Unexpected reduction in supported native methods"
assert "capabilities.describe" in declared
assert "permissions.status" in declared
assert "network.request" in declared
assert "bridge.cancel" in declared
assert {"audio.record", "audio.play", "video.capture", "ui.colorPicker"} <= declared
assert "HTMLAppAudioService" in native
assert "HTMLAppVideoCapture" in native
assert "HTMLAppNativeUIService.colorPicker" in native
assert "audio.record" in read("HTMLAppV3/DeviceAPICatalog.swift")
assert "video.capture" in read("HTMLAppV3/DeviceAPICatalog.swift")
assert "HTMLAppBridgeRegistry.methods" in native
assert "HTMLAppBridgeRegistry.methodSet" in read("HTMLAppV3/HTMLAppBridgeLint.swift")

assert "user-scalable=no" in editor
assert "maximum-scale=1" in editor
assert "pinchGestureRecognizer?.isEnabled = false" in editor
assert "overflow-x:clip" in editor
assert "data-htmlapp-horizontal-scroll" in editor
assert "Runtime: horizontal page overflow" in verifier
for width in ("320", "375", "390", "430", "768", "1024"):
    assert width in verifier, f"Missing viewport QA size: {width}"
assert "Never disable user zoom" not in product
assert "no document-level" in product.lower() or "no document-level" in forge.lower()
assert "ForgeEditContract.make" in forge
assert "ForgeEditSafetyGate.violations" in forge
assert "POST-REPAIR DATA PRESERVATION" in forge
assert 'Runtime: unmarked horizontal scroller' in verifier
assert 'Runtime: page zoom allowed' in verifier
assert "HTMLAppSystemPermissionStatus.read" in native
assert "ForgeSemanticAppModelStore.load" in forge
assert "ForgeSemanticAppModelStore.save" in read("HTMLAppV3/AIGenerationView.swift")
assert "data loss" not in model.lower()  # Model contains no stored user values.
assert "512 * 1024" in read("HTMLAppV3/HTMLAppNetworkBridge.swift")
assert "NoRedirects" in read("HTMLAppV3/HTMLAppNetworkBridge.swift")

# The embedded JavaScript is checked as real JavaScript, not just Swift string
# syntax. Node is optional locally, required in CI.
node = shutil.which("node")
if node:
    scripts = [
        ("native", sdk.split('static let source = #"""', 1)[1].split('"""#', 1)[0]),
        ("runtime-foundation", read("HTMLAppV3/HTMLAppRuntimeFoundation.swift")
         .split('static let source = #"""', 1)[1].split('"""#', 1)[0]),
        ("viewport", editor.split("enum HTMLAppResponsiveViewport {", 1)[1]
         .split('static let source = #"""', 1)[1].split('"""#', 1)[0]),
    ]
    with tempfile.TemporaryDirectory() as temporary:
        for name, source in scripts:
            path = pathlib.Path(temporary) / (name + ".js")
            path.write_text(source, encoding="utf-8")
            subprocess.run([node, "--check", str(path)], check=True)

print(f"Bridge and Forge architecture checks passed ({len(declared)} native methods).")
