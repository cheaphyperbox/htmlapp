# HTMLApp 1.6.9 (build 16) — faster, more reliable mockup selection

## Root cause and improvements
The former three-style pipeline required the model to serialize HTML/CSS inside a JSON `html` string. Models often returned malformed JSON due to unescaped quotation marks or line breaks even when the HTML itself was usable, causing the "style previews aren't available" screen or missing slots.

- Each of the three styles now requests **standalone compact HTML** instead of JSON, reducing escaping failures and response length.
- The AI is asked for a small visual sketch (target under 5,000 characters), with first-attempt output limited to 2,400 tokens, a 45-second request timeout, and no provider-level retries.
- Slots still run concurrently and show completed styles as each arrives; only a failed slot retries once with a shorter 1,800-token, 35-second request.
- Parsing accepts regular HTML, Markdown-wrapped HTML, or the former JSON envelope for backwards compatibility.
- If both attempts for one slot fail, that slot receives one of three **visually distinct local fallback previews** instead of disappearing. These local previews are illustrative and not AI-personalized; a generated design can be retried to get a richer AI-produced mockup.
- The UI no longer resets the current style index on every arrival, so previously chosen styles do not unexpectedly jump.

These are limits and architecture improvements, not measured end-to-end speed claims. Providers can still take significant time; HTTP throttling and device performance are outside HTMLApp's control.

## Discard behavior
The recovery dialog's **Discard Draft** clears the saved checkpoint, cancels its task, and dismisses the Create with AI page. The existing **Discard and Close** path continues cancelling the task and dismissing the page. **Stop and Keep Draft** intentionally remains distinct: it pauses work and preserves the draft.

## Verification
Requires an Xcode build and on-device testing on iPhone/iPad; this environment did not provide an iOS compiler or runtime. Regression source-invariant checks were updated. Verify provider failures, malformed JSON, offline behavior, cancelling during previews, selecting a late-arriving slot, and both discard paths.
