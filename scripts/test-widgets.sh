#!/bin/bash
set -euo pipefail
xcrun simctl list devices available --json > /tmp/htmlapp-simulators.json
python3 - <<'PY' > /tmp/htmlapp-destinations.txt
import json
s=json.load(open('/tmp/htmlapp-simulators.json'))['devices']
for prefix in ['com.apple.CoreSimulator.SimRuntime.iOS-16-', 'com.apple.CoreSimulator.SimRuntime.iOS-26-']:
    choices=[(r,d) for r,ds in s.items() if r.startswith(prefix) for d in ds if d['isAvailable']]
    if choices:
        choices.sort(key=lambda x: ('iPad' in x[1]['name'],x[0]),reverse=True)
        print(choices[0][1]['udid'])
    else:
        print('::warning::Requested simulator runtime unavailable: '+prefix, file=__import__('sys').stderr)
if not any(r.startswith(('com.apple.CoreSimulator.SimRuntime.iOS-16-', 'com.apple.CoreSimulator.SimRuntime.iOS-26-')) for r in s):
    choices=[(r,d) for r,ds in s.items() for d in ds if d['isAvailable'] and 'iOS' in r]
    if choices: print(sorted(choices,key=lambda x:x[0],reverse=True)[0][1]['udid'])
PY
while IFS= read -r udid; do
  xcodebuild -project HTMLApp.xcodeproj -scheme HTMLAppWidgetTests -destination "platform=iOS Simulator,id=$udid" -resultBundlePath "WidgetTests-$udid.xcresult" CODE_SIGNING_ALLOWED=NO test
done < /tmp/htmlapp-destinations.txt
test -s /tmp/htmlapp-destinations.txt
