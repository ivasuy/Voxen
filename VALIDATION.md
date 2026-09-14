# Validation

Built with Apple Swift 6.2.4 for arm64 macOS 14+. Full Xcode is not installed on this development Mac.

## Current implementation

- Writing model is selectable through OpenRouter: Gemini 3.1 Flash-Lite (default), Qwen3.8 Flash, DeepSeek V4.1 Flash, Gemini 3.5 Flash and Claude Haiku 4.5. Each has its own provider token-price ceilings. Gemini Flash-Lite remains the planning/research helper. Search charges are separate from these token ceilings.
- Output is clipboard-only. The app sends no paste or Return events and never restores previous clipboard contents.
- Microphone is required; Accessibility is optional and enables selected-text and best-effort active-website context.
- Compact Settings contains API keys, model, shortcut, permissions, and Save. Save is disabled when values match the saved snapshot; edits enable it again.
- Shortcut changes are applied on Save. A registration conflict preserves the old binding.
- Coding prompts explicitly request imperative instructions and prohibit false completion reports. Clipboard cleanup removes decorative rulers and ANSI formatting.
- No website-to-mode registry or platform-specific prompt branches. The model interprets hostname, app, selected text, speech, and optional manual mode together. Generic means automatic interpretation, not mandatory dictation.
- Only the transformer can create `GeneratedText`; clipboard output requires that type. The same transform-and-copy function used by AppState is tested for success, failure, empty output, and cancellation. There is no raw-STT fallback.
- The native light/dark overlay is 160 × 54 points including its transparent margin. States show no provider names or pipeline details; errors stay compact, with details available in the command center.

## Automated verification

**314 offline checks passed** after the model-picker update. Historical verification sections below retain their original model and counts.

Coverage includes:

- AssemblyAI upload payload, transcript polling, cleanup, empty speech, timeouts, and sanitized errors.
- Free and paid OpenRouter payloads, price ceilings, output parsing, incomplete-output rejection, and server cooldown handling.
- Free request spacing, rolling quota, persisted usage/cooldowns, and reset-header parsing.
- Paid generation when the free allowance is exhausted, without consuming additional free allowance.
- Dirty-state detection, successful Save, settings reload, failed-save behavior, and shortcut rollback after a credential-write error. Keychain access is replaced with an in-memory test store.
- Native Carbon shortcut registration, conflict handling, preservation of the old shortcut, and successful rebinding. Test shortcuts are released afterward; no key events are sent.
- Clipboard formatting and persistence beyond the former two-second restoration deadline, using a separate test pasteboard. The user's clipboard is not touched.
- Exact hostname normalization without a site allowlist, invalid URL rejection, manual override priority, graceful fallback, and host/selection payload delivery with URL paths/query/fragment removed.
- Prompt checks for general writing forms, automatic interpretation, source/intent separation, selected-content usage, missing-context handling, and manual-mode distinction. These verify construction, not model quality.
- Injected Accessibility fixtures for direct selection, ancestor selection, range-only selection, secure-field rejection, bounded cycles/ranges, size limits, and absence of full-value or page-child reads. These do not inspect a real browser.
- Browser marker ranges spanning multiple text nodes; discovery of the active web area when focus remains on the native window; rejection of ambiguous multiple web areas and hidden surfaces. Page children are never traversed.

## Chrome capture regression

The user's real Chrome report showed both missing hostname and missing highlighted text. Two concrete gaps were found: web Accessibility activation was never requested despite Chromium's two-second debounce, and a highlighted document was assumed to own keyboard focus. Browser marker-range support was also missing.

The capture path now requests Chromium Accessibility activation once per browser process, locates the active web area through bounded native window containers, and reads browser-selected marker ranges. Recording starts immediately; generation awaits the bounded context task. Context tasks are cancelled with the voice request. Foreground/window/title changes during initial capture reject the request to avoid mixing sources.

A diagnostic mode in the real app identity (`--probe-browser-context`) checks only the synthetic localhost page in `Tests/Fixtures/browser-selection.html`. It refuses selection reads unless the focused Chrome window has the fixture title. It never initializes AppState, reads API keys, records audio, uses the clipboard, or calls APIs. The JSON report contains permission status, attribute error codes, elapsed time, selection length, and fixture-match booleans, never selected text.

Initial live diagnostic: `accessibilityTrusted: false` for the rebuilt app, despite the old running instance reporting Enabled. This Mac has no valid development code-signing identity; ad-hoc rebuilds can invalidate the old Accessibility grant. The final build has been reopened and the user has been asked to re-enable its macOS Accessibility entry. The real Chrome match check remains pending that permission, and is not represented by the 162 offline passes.

`bash scripts/preview-overlay.sh` passed the compact-dimension check and rendered light/dark listening, writing, copied, and error states using synthetic content only. Both previews were visually inspected.

The app builds with the supplied command-line script. The Xcode project passes plist syntax validation. Signing and launch checks use the ad-hoc-signed local app.

The launch smoke test checks that opening/reopening the app leaves an on-screen settings window and that the window is no larger than 600 × 600 points. It reads only the app's window metadata, not screenshots, fields, or private content.

Prior launch result: the app process launched successfully and window metadata reported a 520 × 499 settings window. The smoke test's on-screen visibility assertion timed out, so foreground visibility remains a manual check; this is not counted among the offline checks.

## Manual setup and live checks

1. Open **build/Voxen.app**.
2. Enter AssemblyAI and OpenRouter keys, choose a writing model and click **Save**. Existing keys are reused. Supported selections survive restart; unknown old model IDs resolve to Gemini Flash-Lite.
3. Verify Save becomes grey. Change a field and verify it becomes blue again; save or undo the edit.
4. Enable Microphone. Enable Website & selected text through Accessibility for automatic website detection, then select Mode Override → Auto.
5. Choose a shortcut, Save, return to another app, and use it to start and stop recording.
6. Wait for **Copied**, then paste manually with Command–V. Wait several seconds before pasting again to confirm the generated result remains available.

The opt-in `bash scripts/verify-intent-live.sh` passed nine synthetic cases using the saved OpenRouter credential and Qwen3.8 Flash: a rough social post, a comment on highlighted text, an email reply, a caption, a rewrite, replies on an unfamiliar website and native app, missing-context clarification, and a hostile instruction inside selected content. All cases used generic/automatic mode, with no site-specific prompt branches. No real website contents, selections, clipboard data, or microphone audio were read, and no credential was printed.

Representative reviewed results:

- Highlighted email + revised timing and budget: “Monday is more realistic. The total is still under 12,000.”
- Highlighted maintenance notice + shorten while preserving date: “Planned maintenance is postponed until Monday.”
- Unknown community site + decline invitation: “I won’t be able to make it, but I hope the event goes well!”
- Missing source + explain failure: “Please share the error or describe what failed.”

Earlier Qwen3.5 runs produced an invented currency and an overstated opinion. The prompt was strengthened and the final model moved to Qwen3.8; the final suite includes regression guards for those cases. These are bounded smoke checks, not a guarantee of perfect factual preservation on every request. Users should review generated text before pasting or sending it.

These live text checks do not establish microphone transcription quality or actual Safari/Chrome Accessibility URL availability. Those still require the manual checks below with permissions enabled.

| Scenario | Expected |
| --- | --- |
| Cursor: request a refactor and validation | Imperative engineering instruction copied, with no claim the work is done |
| Slack: “Tell him tomorrow morning is more realistic” | Natural reply copied |
| Social mode: rough opinion | Concise post copied |
| Selected paragraph: “Make this shorter” | Rewritten text copied |
| Accessibility disabled | App context, explicit writing requests, manual mode and speech still work; no website hint or selected text |
| Any website, Auto mode | The model receives the captured hostname when available and infers the requested writing form; overlay shows only status |
| Highlighted message + reply instruction | Relevant reply, not a rewrite or summary of the selected message |
| LLM error, empty result, or cancellation | Existing clipboard remains unchanged; no transcript fallback |
| Browser URL unavailable | App context and spoken intent still apply; choose a mode override or explicitly request a post |
| Another field/app focused during processing | Result copied; no automatic insertion anywhere |
| Clipboard held for more than two seconds | Generated result remains until the user copies something else |
| Earlier free quota exhausted | Gemini can still run independently of the previous free allowance |
| Paid provider returns 429 | Paid requests pause until the server cooldown expires |

## Voxen visual refresh (September 12)

- Release Swift build completed and both plist files passed syntax validation.
- 162 offline regression checks passed after the UI changes.
- All six phase presentations remain exactly 160 by 54 points including padding (visible capsule 144 by 38). Long error text cannot expand the overlay.
- Synthetic light/dark previews cover low/high audio levels, both processing phases, success and error. No private keys, selected content, or live API requests are used in these previews.
- Generated PNG and ICNS are bundled in the app and Xcode Resources phase. Display name is Voxen; existing internal identifiers/path are unchanged.
- Strict code-sign verification passed via launch.sh; the exact app executable was confirmed running after launch. Settings previews were inspected in both appearances with synthetic keys and the Save button disabled.
- Chrome selection capture still needs live verification after Accessibility reauthorization. The branding refresh does not establish end-to-end microphone/browser/API acceptance.

## Command center and response history (September 12)

- Release build succeeds as `build/Voxen.app`; strict signature verification and project/plist validation pass.
- 175 offline checks pass, including 13 new history checks: generated-only payload, no separate source/transcript storage, hostname/app labels, persistence, disabled capture, limit of 100, individual deletion, clear and corrupt-data fallback.
- Real launch smoke passes: visible command-center window measured 780 by 672 points including title bar; reopening keeps the same app instance and a visible window.
- Finder's icon readback was inspected and shows the generated Voxen logo, not the generic app placeholder.
- Synthetic Mode, History and Settings previews inspected in light/dark appearance, plus empty and error states. Draft fields use fake keys; history fixtures are synthetic. No live voice or LLM call was used for this UI update.
- Overlay remains 160 by 54 including padding, 144 by 38 visible; phase size regression passes.
- Menu source contains only Mode (short icon-labelled options), Settings and Quit. Command center retains cancellation and error details.
- History begins with new successful responses; previously discarded results cannot be recovered. History is local UserDefaults storage, not encrypted, and can be disabled or deleted. Raw speech and highlighted source are not independently archived.
- Previous app bundle preserved in `build/PreviousBuilds/Voice Intent Router.app` during scoped relaunch. Internal bundle ID/Keychain service unchanged. New bundle path/ad-hoc signature can require Accessibility reauthorization.

## Gemini and selective research (September 12)

- Default and displayed model changed to `google/gemini-3.1-flash-lite`; existing OpenRouter credentials and other preferences are reused.
- 193 offline checks passed, including structured planning, private selection excluded from planning/search, native-search payload, source annotation handling, no-source failure, no-search paths, and persisted rolling research limits.
- Targeted live checks passed for a developed coding-agent prompt, a developed public post, an unfamiliar native-app reply and native Google research. Only synthetic fixtures were sent; no audio, real browser selection or user clipboard was read. The earlier full-suite run has no retained completion result and is not claimed as passed.
- Live engineering output was about 120 words; the public post used several developed paragraphs. The research case returned Google grounding citation URLs. These smoke checks establish API plumbing and basic output shape, not guaranteed factual accuracy.
- Reviewing the research result exposed weak stable-versus-preview distinctions and repeated source sections. Prompts now require explicit release evidence and numbered citations, while code appends exact provider URLs. These final prompt adjustments have offline coverage but were not re-run against the paid API.
- Research is capped at 20 requests per rolling 24 hours, counting failures. This is not a dollar cap or a cap on Google's internal billable queries. Ordinary writing uses two calls; researched writing uses three. No automatic retries or external search-provider fallback.
- Actual microphone, hotkey-to-browser selection and paste acceptance still require manual checks; this provider change does not establish Chrome permission health.

## Ordinary writing and missing-source fallback

- Planner defaults to no research; brand/platform/model mentions, personal project updates and requests for more developed writing do not by themselves justify search. Only selection availability, not selected content, is added to planning context.
- A citation-free research response no longer throws the reported "No verified web sources" error. Its entire unsourced briefing and embedded links are discarded. The final writer receives the original input and an explicit unavailable-sources status, with search disabled.
- When supplied information is enough, writing continues. When current facts are essential, the prompt requires an honest limitation/source request instead of invented verification. Provider HTTP failures, cancellation and incomplete final output remain errors; no raw speech fallback was added.
- 200 offline checks passed, including no retry/search in fallback, no leaked unsourced claims or URLs, preserved original selection, completed LLM output and no fabricated source footer. Planner behavior remains model-based, not a deterministic guarantee.
- Live regression using the user's open-source LinkedIn project description passed with zero new research attempts. The first run avoided search but invented extra implementation details; after tightening factual-fidelity guidance, the final run returned only the supplied project facts and passed both no-search and unprovided-detail guards. This is a bounded example, not proof that all future phrasing is classified correctly.

## Writing preferences (September 13)

- Added a native Writing sidebar destination with Style, About you and Platforms tabs. It follows the existing system appearance, mint selection accent, aligned form labels and persistent Save footer. Duplicate native picker labels were caught in previews and removed.
- Global controls include detail, assumption policy, tone, format, emojis, hashtags, word target, language and extra preferences. Destination presets can inherit or override these values, with custom website, application and mode matching. X longer-post support is explicit, not inferred from the account.
- Personal profile and manually supplied samples are opt-in for API use, stored in local unencrypted UserDefaults, independently clearable and never imported from history. Preferences are snapshotted at recording start. Only resolved settings and an enabled profile go to the final writer; neither reaches research planning or search.
- 231 offline checks pass, including persistence, failed-save preservation, bounds/corruption, normalized host matching, suffix spoof rejection, destination precedence, X account choice, safe system instructions, profile opt-in/clear and exclusion from search. Final project/plist syntax validation passes. Full Xcode remains unavailable.
- Light/dark previews inspected for all Writing tabs using synthetic profile data. Previews do not interact with the user's fields, clipboard, microphone or saved profile. Native control interaction and VoiceOver behavior remain manual checks.
- Live synthetic runs demonstrated distinct precise and elaborate coding prompts, proposed feature/stack sections, and an X post within 280 characters with requested hashtags. An intermediate elaborate run missed its word-target/proposal check; the focused final elaborate run passed. Active saved settings are now reinforced with typed system instructions, not just supplied as JSON.
- Model compliance is approximate: a no-assumptions sample still suggested a due-date field, and word targets can vary. Character budgets are guidance, not platform-exact counting or truncation. No claim of guaranteed factual fidelity, exact length or account validation is made. Review generated text before using it.

## OpenRouter model picker (September 13)

- Added five curated writing models without adding a provider key or changing voice capture, clipboard output or Writing preferences. Native Settings picker uses the same Save/dirty-state behavior.
- Public OpenRouter catalog verified model IDs, token pricing and reasoning capabilities. Optional reasoning stays off; Gemini 3.5 Flash's mandatory reasoning uses minimal effort. Privacy routing remains `data_collection: deny` with no provider request fee and model-specific token ceilings.
- 314 offline checks pass. New tests cover each model's settings persistence, final-writer routing, token ceilings, reasoning payload and citation retention; planning/research remains on Gemini Flash-Lite. Unsupported old saved models safely resolve to the default.
- `bash scripts/verify-intent-live.sh --models` passed five live, one-request synthetic scheduling replies, one per model. No microphone, selected context, saved profile or clipboard contents were sent. These verify endpoint/parameter availability, not comparative writing quality or every model's factual accuracy.
- Settings light/dark previews rendered with synthetic keys; the light preview was inspected for control alignment and wrapping. The model picker shows token ceilings and makes Gemini helper/search usage explicit.

## Release limits

A user's manual paste is outside the app's control. There is no automatic insertion, command execution, or field targeting. Gemini requires OpenRouter credits.

Native window metadata checks do not establish pixel-perfect rendering or manually exercise every control. Shortcut choices currently use physical US keyboard positions.

Full Xcode build/archive validation requires Xcode. Developer ID signing, notarization, and DMG distribution remain deferred until live acceptance checks pass.
