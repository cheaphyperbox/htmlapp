#!/bin/bash
set -euo pipefail
if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo 'Discord delivery not configured: DISCORD_WEBHOOK_URL is absent.'
  exit 1
fi
echo "::add-mask::$DISCORD_WEBHOOK_URL"
case "$DISCORD_WEBHOOK_URL" in
  https://discord.com/api/webhooks/*|https://discordapp.com/api/webhooks/*) ;;
  *) echo 'Invalid Discord webhook secret.'; exit 1 ;;
esac
MESSAGE="HTMLApp Forge and sharing build: automated tests and packaged IPA checks passed. Dictation, nearby transfer and Safari profile installation require physical-device validation. Feather requires App Group authorization in both profiles. Build: https://github.com/${GITHUB_REPOSITORY}/actions/runs/${SOURCE_RUN_ID:-$GITHUB_RUN_ID}"
BODY="$(jq -nc --arg hook "$DISCORD_WEBHOOK_URL" --arg content "$MESSAGE" '{webhook_url:$hook,wait:true,payload:{content:$content,username:"HTMLApp Build Bot",allowed_mentions:{parse:[]}}}')"
STATUS="$(curl --silent --show-error --connect-timeout 10 --max-time 30 --output /dev/null --write-out '%{http_code}' --header 'Content-Type: application/json' --data-binary "$BODY" 'https://mekapc.hostish.site/api/webhook' || true)"
echo "HOSTISH notification HTTP $STATUS"
# A proxy outage must not suppress the independently supported attachment route.
test -s HTMLApp.ipa
UPLOAD="$(curl --silent --show-error --connect-timeout 15 --max-time 120 --output discord-delivery-response.json --write-out '%{http_code}' --form-string 'payload_json={"content":"HTMLApp Forge and sharing build: Single HTMLApp.ipa attached: install with TrollStore or re-sign with Feather, then configure an authorized signing group. Device validation remains required; see the GitHub build summary.","username":"HTMLApp Build Bot","allowed_mentions":{"parse":[]}}' -F 'files[0]=@HTMLApp.ipa;filename=HTMLApp.ipa;type=application/octet-stream' "$DISCORD_WEBHOOK_URL?wait=true")"
echo "Discord attachment HTTP $UPLOAD"
if [ "$UPLOAD" != '200' ]; then
  jq '{code: .code, errorFields: ((.errors // {}) | keys)}' discord-delivery-response.json || true
  rm -f discord-delivery-response.json
  exit 1
fi
jq -e '[.attachments[] | select(.size > 0) | .filename] | (index("HTMLApp.ipa") != null)' discord-delivery-response.json >/dev/null
rm discord-delivery-response.json
echo 'Discord confirmed the nonempty HTMLApp.ipa attachment.'
if [ "$STATUS" != '200' ] && [ "$STATUS" != '204' ]; then
  echo '::error::Attachments delivered, but HOSTISH notification failed. Do not report full delivery success.'
  exit 1
fi
