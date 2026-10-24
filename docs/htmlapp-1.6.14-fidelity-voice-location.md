# HTMLApp 1.6.14 (build 21)

## Selected-mockup fidelity
Selected style instructions now explicitly protect the original mockup's content hierarchy, header, dominant region, CTA location, card order and navigation. After the working app is generated, Forge inspects for missing CSS tokens and basic structural indicators for the chosen map/action/list archetype, and can request a focused AI repair. These are heuristics; pixel-identical output and runtime fidelity cannot be guaranteed.

## Faster native location
The saved-app Core Location bridge caches its last valid foreground fix. When a new request is allowed both by the HTMLApp permission policy and by iOS foreground-location authorization, a fix obtained within the last 45 seconds may be returned immediately if accurate within 75 meters (high accuracy) or 250 meters (standard accuracy). Otherwise Core Location proceeds with a normal fresh request. This doesn't bypass user/system permission dialogs or guarantee cold-start GPS speed.

## Whisper warmup
When the selected dictation engine is Whisper Offline, opening the Library starts a reusable WhisperKit model initialization task. A subsequent dictation waits for or reuses this task rather than always initializing the model after recording. First use can still require an offline model download, storage, and time. Other dictation engines do not preload Whisper by default.

## Draft recovery and Lock Screen voice
Successful completed Forge jobs now clear their checkpoint, and the screen's disappear lifecycle no longer re-creates completed checkpoints. Recovery only offers a draft that appears unfinished, while explicit Stop/Keep remains recoverable.

Generate Now from the Lock Screen voice-capture screen preserves its spoken text through the capture-cover dismissal and begins actual generation directly, rather than navigating to style selection or an empty prompt page. Voice handoff remains subject to iOS view-presentation timing; the generation screen should be tested on the user's iPhone and iPad.

## Clarification questions
For some long, ambiguous initial app-creation prompts, Forge asks its planner model for one meaningful multiple-choice question. The user can tap either answer, type a custom response, or choose the model's suggestion. After 20 seconds without an answer, the suggested response is selected and generation proceeds. A bounded fallback question is used if the planner model fails. This is a first-stage clarification, not a general conversational question system that can interrupt arbitrary later generation stages. Lock Screen quick-create deliberately skips this to avoid delaying voice generation.

## Verification
Code changes are committed to mekabrine/htmlapp only. The source-invariant checks were updated. No signed Xcode build/device benchmark was executed in this environment. Validate Siri/widget capture, Whisper cold and warm loads, Core Location permissions, chosen mockup fidelity, and completion/recovery lifecycle on physical devices.
