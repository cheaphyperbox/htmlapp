# HTMLApp 1.6.11 (build 18)

## Native status bar control
Saved HTMLApps show the genuine iOS system status bar by default. For an immersive app, Forge can place the following declaration inside the HTML head:

```html
<meta name="htmlapp-status-bar" content="hidden">
```

The saved-app host detects the tag and requests status bar hiding. It accepts either quote style and attribute order. Removing the tag restores the default visible status bar. Existing saved apps without this tag now show the status bar. The generated web content must never simulate a fake iPhone status bar, notch, Dynamic Island, or home indicator. During unrelated AI edits, the agent is instructed to preserve the existing status-bar choice.

## AI system prompt simplified
The advanced editable system-prompt field and restore-confirmation dialog have been removed from AI & Creation settings. The AI configuration store always returns the maintained built-in prompt; historical custom UserDefaults overrides are ignored. Look & Feel preferences and specialist AI model configuration are still supported. This is a behavior change for anyone with a formerly customized system prompt.

## Widget family completeness
Forge and its edit agent are instructed to expose all three native WidgetKit families when an app adds that screen type:

- Home Screen: `systemSmall`, `systemMedium`, `systemLarge`.
- Lock Screen: `accessoryCircular` (square/circular), `accessoryRectangular`, `accessoryInline` (top text).

Apps that support both screens should declare all six or appropriate screen-specific configurations, keep snapshot values useful for each family, and use `HTMLAppNative.widgets.configure` with supported family identifiers. The host WidgetKit extension already renders all six families. The instructions do not enable unrelated private iOS APIs, and WidgetKit still decides placement and reload schedules.

## Verification
The change was committed to `mekabrine/htmlapp`. The source-invariant CI checks were updated. It has not been compiled or tested on real iPhone/iPad hardware in this session. Verify normal status-bar visibility, immersive opt-in, returning to a saved app after edits, and all six sizes in the WidgetKit picker. System UI and safe-area behavior still depend on iOS.
