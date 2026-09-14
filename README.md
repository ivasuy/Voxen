# Voxen

**Don't dictate text. Speak intent.**

A context-aware voice intent layer for macOS, built for the AssemblyAI Voice Agent Hackathon.

Press your shortcut, speak an intention, and press it again. The app combines the AssemblyAI transcript with your current application, a best-effort website hint, and optional selected text, then copies the appropriate result. Paste it yourself with **Command–V**.

## Download

[Download Voxen for macOS](https://github.com/ivasuy/Voxen/releases/latest/download/Voxen-macOS-arm64.zip) from the latest GitHub Release. Voxen requires macOS 14 or newer on Apple Silicon.

1. Unzip the download and move **Voxen.app** to Applications.
2. On first launch, Control-click **Voxen.app**, choose **Open**, then confirm **Open**.
3. Add your AssemblyAI and OpenRouter API keys in Settings and grant Microphone permission. Accessibility is optional and enables selected-text and website context.

GitHub builds are ad-hoc signed and are not Apple-notarized, so macOS displays an unidentified-developer warning on first launch. If you prefer to build from source, follow [Build from source](#build-from-source).

## Why it exists

Ordinary dictation cleans up what you said. Voxen also asks where you're working and what you're trying to accomplish. The same spoken instruction can become a coding-agent prompt, a conversational reply, a social post, or an explanation.

| Context | What you say | What gets copied |
| --- | --- | --- |
| Cursor | “Simplify this without changing behavior and run the relevant tests.” | An actionable engineering instruction |
| Slack | “Tell him tomorrow morning is more realistic.” | A short conversational reply |
| Any social site, Auto | “Write a short post about benchmarks missing real coding usefulness.” | A concise social post |
| Terminal, error selected | “Explain why this is happening.” | A technical explanation |
| Selected paragraph | “Make this shorter and clearer.” | A rewritten paragraph |
| Notes | Ordinary speech with filler | Clean prose |

Wording varies by model. The app writes instructions for a coding agent; it does not report that changes or tests have already been completed.

## Current interaction: clipboard only

The app never clicks a field, sends Command–V, or presses Return. Generated text stays on the clipboard until you copy something else. There is no delayed restoration of old clipboard contents.

After the overlay says **Copied**, focus your chosen field and press **Command-V**. This also lets you choose a different destination after recording. The destination app is pinned when recording starts. Audio begins immediately while browser context is collected; keep the same page and highlight while speaking.

The overlay is a 144-by-38-point charcoal capsule: one icon and one status, **Listening**, **Writing**, **Copied**, or **Error**. No subheading, destination metadata, shortcut badge, or provider names. The mint waveform reflects microphone level; reduced motion disables transitions. Error details are available in the command center and the overlay's accessibility value. The command center follows system light/dark appearance.

Local builds produce **build/Voxen.app**, including its generated icon. The internal bundle identifier remains unchanged to preserve keys and preferences. The generated logo and native UI design notes are in [BRAND.md](BRAND.md).

## Command center

- **Mode:** icon, short heading and one-line description. Auto adapts to captured context; manual modes remain available.
- **Writing:** Style, About you and Platforms tabs. Saved writing preferences are captured at recording start and supplied only to the final writer.
- **History:** the last 100 generated responses with their captured app or website hostname and timestamp. Copy a response again, delete one, or clear all. History starts with new responses after this update; previous results were not retained.
- **Settings:** both API keys and links to obtain them, an OpenRouter writing-model picker with token-price ceilings, shortcut configuration and permissions. Save is disabled after success until another edit. Draft keys and model choice survive switching sidebar pages.

The menu bar contains only **Mode**, **Settings**, and **Quit**. Mode items have short names and icons. Recording still uses the global shortcut; an active request can be cancelled inside the command center.

The former automatic-paste flow is removed. Its two-second clipboard restoration could replace the generated text with stale contents before a manual paste.

## Setup

### Writing preferences

Open **Writing** in the command center:

- **Style:** Precise, Balanced or Elaborate detail; No assumptions, Suggest options or Explore possibilities; Natural, Professional, Conversational, Humorous, Quirky or Direct tone; adaptive format, paragraphs, bullets or numbered steps; emojis, hashtags, language, extra preferences and a 0–1,500 word target (0 means adaptive).
- **About you:** optional name, role, work/interests, audience, preferred stack, things to avoid and up to 6,000 characters of manually pasted writing samples. Profile use is off by default. Samples inform style, not new factual claims. Enable the profile and Save to include it in future voice requests. Clear profile, then Save to remove its stored fields.
- **Platforms:** enable presets for places you use, customize their style or inherit global defaults. Add arbitrary websites, app names/bundle identifiers or modes. Matching uses hostname boundaries, then native apps, then modes; the most specific matching hostname wins. Unavailable browser context falls back to app/mode/global preferences, never an assumed website.

The Coding prompts preset can allow clearly labelled feature/stack proposals without making every social post speculative. Spoken instructions override saved stylistic defaults. Proposed requirements must not be represented as existing features, completed work, personal history or verified news. Preferences do not trigger web search.

X's preset uses **280 characters**, or **25,000** when you explicitly enable longer posts; the app does not inspect subscriptions. LinkedIn's post preset uses **3,000 characters**. See [X post types](https://help.x.com/en/using-x/types-of-posts) and [LinkedIn post limits](https://www.linkedin.com/help/linkedin/answer/a528176/). Instagram starts with an editable 2,200-character caption budget; other destinations can have custom budgets. These are model instructions, not deterministic enforcement or account verification. Word targets are approximate; character budgets outrank them for applicable posts/captions. Links, emoji, citations and different composer types can affect actual limits. Review the result in the platform before posting; Voxen does not truncate, publish or create threads automatically.

Save is disabled after a successful save and enabled by edits. Discard restores saved values; drafts survive changing tabs or sidebar pages. Writing preferences and profile fields are stored locally in UserDefaults, **not encrypted**. Enabled profile data is sent to OpenRouter and the selected writing-model provider only with explicitly triggered writing requests, never to research planning or Google search. Disabling profile use stops sending it but retains the fields locally until cleared and saved. Nothing is imported from social accounts, inferred from history or used to train a custom model.

### API keys and permissions

Requires macOS 14+, Apple Silicon, internet access, an AssemblyAI API key, and an [OpenRouter API key](https://openrouter.ai/settings/keys).

1. Open **Voxen.app**, then choose Settings in the sidebar.
2. Enter both keys in Settings. Choose a writing model; Gemini 3.1 Flash-Lite remains the default and the existing OpenRouter key works for every choice.
3. Click **Save**. It becomes grey/disabled after success and blue/enabled when you edit a value.
4. Enable Microphone. Selected-text access is optional.
5. Return to your app. Press **Option–Space** to record and again to finish, then paste with **Command–V**.

Settings contains keys, a writing-model picker, a shortcut picker, permissions, and Save. Labels and controls share consistent columns. Keys are held in macOS Keychain. You can choose a modifier combination and Space or a letter for the shortcut. Save applies it immediately; an unavailable shortcut leaves the previous binding active.

Opening the app brings the command center forward. The menu's Settings action selects its Settings page. Closing the window leaves the waveform menu-bar icon available.

From a terminal, `bash scripts/launch.sh` verifies the app signature and opens the correct bundle, including its spaces.

## Text models and cost

Choose a writing model in Settings, then Save. All choices use the existing OpenRouter key and share writing preferences and context. These are the app's **maximum provider-routing token prices**, not quotes or spending caps:

| Writing model | Input ceiling / 1M tokens | Output ceiling / 1M tokens |
| --- | ---: | ---: |
| [Gemini 3.1 Flash-Lite](https://openrouter.ai/google/gemini-3.1-flash-lite), default | $0.30 | $1.60 |
| [Qwen3.8 Flash](https://openrouter.ai/qwen/qwen3.8-flash) | $0.20 | $0.60 |
| [DeepSeek V4.1 Flash](https://openrouter.ai/deepseek/deepseek-v4.1-flash) | $0.35 | $1.30 |
| [Gemini 3.5 Flash](https://openrouter.ai/google/gemini-3.5-flash) | $1.60 | $9.50 |
| [Claude Haiku 4.5](https://openrouter.ai/anthropic/claude-haiku-4.5) | $1.10 | $5.20 |

Gemini 3.1 Flash-Lite remains the planning and native-search helper for every writing model. Only the final response uses your selected writer, so models without native search still receive sourced context. Helper token usage and Google search are charged separately from writing. Native search is listed at $14 per 1,000 search calls; it is not free or included in token prices. OpenRouter credits are required.

Writing uses temperature 0.3 and a 4,000-token generation allowance. Optional reasoning is disabled; Gemini 3.5 Flash requires reasoning and uses its supported minimal effort, which can consume some of that allowance. All requests retain the no-data-collection routing filter and zero provider request-fee ceiling. Routing ceilings do **not** cap Google search charges or total spend. No automatic fallback to a different writing model is configured. Prices and provider availability can change; if no provider matches the selected model's ceilings/privacy filter, the request fails clearly.

Supported model choices persist across launches. Missing or unsupported old selections resolve to Gemini Flash-Lite without changing keys, shortcuts, writing preferences or response history.

Requests honor server 429 cooldowns, persist them across restarts, and never retry automatically. Gemini is independent of the earlier free-model allowance. Server limits remain authoritative across apps and devices. See [OpenRouter limits](https://openrouter.ai/docs/api/reference/limits).

## Selective native web research

Gemini first receives a small structured planning request containing speech, the current date and a selection-availability boolean, but no selected text or app metadata. No search is the default. Ordinary replies, rewrites, captions, coding prompts and descriptions of the user's own projects should not search. Merely mentioning a model, platform or place is not a search trigger. Explicit public research and requests that materially need unknown current facts can produce a public-topic query.

When needed, a separate Gemini request enables OpenRouter's web plugin with `engine: native`, using only that query and date. There is no Tavily/Exa fallback or extra API key. The original highlighted content is never included in this search-enabled request. Planning is model-based; avoid speaking secrets into a public research instruction. Email-like or oversized queries are rejected before search.

The final writing request combines the original context with a cited research briefing, with search disabled. Provider-returned HTTP(S) citation URLs are retained with the finished text and therefore in copied/history responses. If research returns no citation URLs, the unsourced briefing is discarded and the writer receives an explicit unavailable-sources status. It can still complete writing from the original content; if current facts are essential, it must acknowledge that they could not be verified and request a source. There is no raw-transcript fallback or second search attempt. Citations establish provenance, not guaranteed truth; users should review claims and event dates.

Ordinary writing uses two model requests; researched writing uses three. At most 20 research requests are permitted per rolling 24 hours on this app, including failures. This is **not a dollar ceiling**: Google can issue multiple billable queries per research request. Ask for writing 'without web search' when current facts are unnecessary. No background browsing occurs.

Writing now uses adaptive depth: substantive posts and coding-agent prompts are developed rather than compressed into one-liners. Explicit brevity, simple replies and destination length limits still take priority. Relevant sourced facts may enrich a post; invented experiences, commitments or unsupported claims remain prohibited.

AssemblyAI speech usage is separate.

## Architecture

~~~mermaid
flowchart TD
    H[Global shortcut] --> C[Foreground app + optional website host + selected text]
    C --> A[AVAudioEngine: in-memory recording]
    A --> S[AssemblyAI: upload, transcribe, poll]
    C --> M[Mode resolver or manual override]
    S --> I[IntentTransformer]
    M --> I
    I --> D[Gemini: speech-only research plan]
    D -->|Public facts needed| W[Native Google search: public query only]
    D -->|No research needed| R[Selected OpenRouter model: contextual writing]
    W --> R
    I -->|Original context| R
    R --> P[Clean plain text → clipboard]
    P --> U[User pastes with Command–V]
~~~

Native SwiftUI and AppKit, Carbon hotkey registration, AVAudioEngine, URLSession, and Keychain. No third-party dependencies, screen capture, database, or cloud application infrastructure.

~~~text
VoiceIntentRouter/
├── VoiceIntentRouter.xcodeproj/
├── VoiceIntentRouter/
│   ├── App/           # Menu bar and request lifecycle
│   ├── Audio/         # Recording, levels, WAV encoding
│   ├── Speech/        # AssemblyAI / SpeechTranscribing
│   ├── Context/       # App mapping and Accessibility selection
│   ├── Intent/        # Prompts, OpenRouter, rate limits
│   ├── Input/         # Configurable native shortcut
│   ├── Output/        # Plain-text clipboard output
│   ├── Permissions/   # Microphone and optional Accessibility
│   ├── UI/            # Compact settings and floating overlay
│   └── Models/        # Settings, Keychain, HTTP errors
├── Tests/
└── scripts/
~~~

## AssemblyAI usage

AssemblyAI performs transcription for every voice request. The app records first for reliability, uploads an in-memory WAV through [POST /v2/upload](https://www.assemblyai.com/docs/pre-recorded-audio/api-reference/files/upload), then [submits a transcript](https://www.assemblyai.com/docs/pre-recorded-audio/api-reference/transcripts/submit) using Universal-3 Pro with Universal-2 fallback.

Recording stops at two minutes. Polling has a 90-second deadline, potentially extended by an in-flight network request. Empty speech, connection errors, and provider failures produce an overlay error. Known transcription jobs receive a best-effort delete request after processing.

## Supported contexts

| Mode | Applications |
| --- | --- |
| Coding | Cursor, VS Code, Xcode, Windsurf, Zed |
| Messaging | Slack, Discord, Messages, WhatsApp, Telegram |
| Terminal | Terminal, iTerm2, Warp |
| Document | Notion, Notes, Pages, Obsidian |
| Social | Optional manual preference; automatic social interpretation is handled by the LLM |
| Generic | Automatic contextual writing for browser destinations and other apps |

There is no website-to-mode registry or platform-specific writing recipe. User-enabled writing presets match saved destinations and supply style/length preferences; they do not classify every website. The final selected-model writing request receives the actual hostname, app name, selected text and spoken intent, plus resolved preferences, an enabled personal profile and public research when performed. It infers the writing form and audience for unfamiliar sites. Native categories remain soft hints; explicit overrides are marked separately. A generic hint does not force dictation.

The native Accessibility reader checks the focused window's document URL or its active web area. When a document selection does not own keyboard focus, a bounded search of native window containers locates the outer web area. It stops at web areas and never traverses their page children, reads the address field, enumerates tabs, or guesses the website from a title. A window title is held briefly in memory only to reject navigation during capture; it is not sent or logged. The [document URL attribute](https://developer.apple.com/documentation/applicationservices/kaxdocumentattribute?language=objc) is supplied by the destination app, so availability varies by browser and focus location.

On the first Chromium capture, the app requests web Accessibility activation and allows for [Chromium's two-second activation debounce](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/chrome_browser_application_mac.mm). The request is made once per browser process, not on each retry. Capture is bounded, runs alongside recording, and is awaited before transcription/generation. Changing the foreground app, window, or page title during this preparation rejects the capture instead of mixing destinations. The app never disables another assistive tool's Accessibility mode.

Enable **Website & selected text** in Settings and choose **Mode → Auto** for automatic detection. The overlay shows only status. If the browser does not expose its URL, website-specific writing preferences cannot match; app/mode/global defaults still work. Choose Social from the menu or explicitly say “Write a post…” when needed. Reset the mode to Auto afterward.

The shared [system prompt](VoiceIntentRouter/Intent/PromptTemplates.swift) defines writing tasks, not platform recipes. Every selected model receives the same destination and writing-preference instructions. Flexible depth guidance, source/intent separation, factual-preservation constraints and a final-text-only contract guide output. This is prompt tuning, not model fine-tuning.

To reply to a particular post or email, highlight its text and trigger recording while the highlight is still active. Say what you want the reply to convey. To edit the highlighted text instead, ask for a rewrite. After Copied, move to the desired composer and paste. The app does not know unselected page contents and should request missing context rather than invent it.

Selected-text retrieval tries the focused element, its ancestors, the active web area, opaque browser text-marker ranges for multi-node selections, and a bounded [selection-range substring](https://developer.apple.com/documentation/applicationservices/kaxstringforrangeparameterizedattribute). It never reads entire field values or page children as a fallback. Secure fields, unavailable selection, invalid ranges, and broken ancestor chains are handled without failing the voice request.

Only `IntentTransformer` can construct `GeneratedText`, and `ClipboardOutput` accepts that type rather than arbitrary strings. The production pipeline waits for the model, validates/cleans its response, checks cancellation, then copies. Provider errors, empty/incomplete responses, and cancellations leave the clipboard unchanged; raw transcription is never substituted. A model can still return wording similar to speech when appropriate, but that is a model response, not a bypass of refinement.

## Permissions and privacy

Microphone permission is required. Accessibility is used for selected text and best-effort active-website detection. It is optional: without it, recording, explicit spoken writing instructions, manual modes, and clipboard output still work.

Settings provides permission buttons. For website/selected-text context, enable **Voxen.app** in System Settings → Privacy & Security → Accessibility. You may need to add the exact app bundle or relaunch after changing permissions.

Local builds are ad-hoc signed. Rebuilding or moving the app can invalidate the previous macOS Accessibility grant even if an older running instance still shows Enabled. Quit the old instance, open the new build, and toggle its Accessibility grant off/on (or remove and re-add the exact built `.app`). No valid development-signing identity is installed on this machine. Check the Website & selected text permission row in Settings; the overlay intentionally shows only status.

Only an explicit voice trigger starts audio and reads context. No continuous screen inspection, OCR, automatic copying of source content, or transcript history is used.

Audio stays in memory and goes to AssemblyAI. OpenRouter and its model provider receive the transcript, app name, bundle identifier, mode hint/override source, optional website hostname, selection availability, and up to 12,000 selected characters. Website paths, query strings, fragments, titles, unselected page contents, and browsing history are not sent. Secure text fields are skipped. Requests exclude providers marked as collecting input data; account settings and provider retention policies still apply. Best-effort transcript deletion does not guarantee zero provider retention.

Public research queries also reach Google's native search service, without the original selection or app metadata. Research source links remain part of the generated result.

No keys, website hosts, full selected content, or transcripts are logged. UserDefaults stores model, shortcut, mode, rate-limit timestamps and, when enabled, the last 100 generated responses with their app name, hostname, mode and date. History is local, not encrypted, and may contain sensitive information included in generated writing. It does not separately save audio, raw speech transcripts, selected source content or captured page URLs. Turn off **Keep history on this Mac** to stop adding entries; existing entries remain until deleted or cleared. History is not sent back to the LLM. Generated text also remains on the clipboard and may be retained by clipboard managers or the destination app.

Existing AssemblyAI/OpenRouter keys are reused from this app's Keychain entries. Old OpenAI credentials, if present, remain untouched and unused.

## Build from source

~~~sh
bash scripts/build.sh
bash scripts/launch.sh
bash scripts/test.sh
~~~

Create the same ZIP used by GitHub Releases with:

~~~sh
bash scripts/package-release.sh v0.1.0
~~~

The version argument must match `CFBundleShortVersionString` in `VoiceIntentRouter/Info.plist`. The archive and SHA-256 checksum are written to the ignored `release/` directory. Maintainers publish a release by pushing a matching `v*` tag; the GitHub Actions workflow tests, builds, packages, and attaches both files automatically.

The command-line build produces an ad-hoc-signed arm64 app using Apple's Command Line Tools. Full Xcode is not installed on the development machine. The included Xcode project and shared scheme can be opened in Xcode to build for My Mac.

The offline tests use mock HTTP responses, an isolated pasteboard, and temporary shortcut registrations. They exercise model requests, free and paid cooldowns, saved-state behavior, shortcut conflict recovery, clipboard persistence, history retention, deletion and disabled-history behavior. They do not send live API requests or keystrokes.

`bash scripts/preview-command-center.sh` renders Mode, History, Settings, empty and error states with synthetic keys and response fixtures. `bash scripts/relaunch.sh` restarts only this project's app and preserves the former named bundle in `build/PreviousBuilds` when present.

`bash scripts/preview-overlay.sh` renders synthetic light/dark overlay previews without recording or reading private content. The opt-in `bash scripts/verify-intent-live.sh` runs 16 Gemini examples (normally 33 model calls including one native research request) using the saved OpenRouter key. Fixtures include the user's non-sensitive project-description regression and synthetic writing preferences. Pass a case-name filter (such as `Writing`) to run only matching cases. It never reads the current browser, clipboard or saved writing profile, stops on failure, and checks developed writing alongside factual research and existing contextual cases.

See [VALIDATION.md](VALIDATION.md) for current verification and live checks.

## Demo

1. Cursor: select code, speak a refactoring instruction, then paste the copied engineering prompt into chat.
2. Slack: speak a conversational reply, then paste it into the composer.
3. X: with Website access enabled and Auto mode, speak a rough opinion and paste the resulting post. If context is unavailable, use Social mode or explicitly request a post.
4. Terminal: select an error, ask for an explanation, and paste the explanation into a note or appropriate text field.

**Same voice. Different context. Different intent.**

## Limitations and roadmap

Speech is configured for English. Recording before transcription and model planning add latency; research takes longer. Selected text and website detection depend on Accessibility and may be unavailable in Electron or web content. Website detection is bounded and best-effort, not full page understanding. The app records microphone audio, not browser-tab playback. Output quality depends on the selected model and the supplied evidence.

Shortcuts currently offer four modifier combinations and Space/A–Z using physical US keyboard key positions. macOS or other apps can reserve a combination. The app does not execute commands or verify a user's manual paste.

GitHub Releases are ad-hoc signed rather than Apple-notarized. A Developer ID certificate and Apple notarization are still required for a warning-free first launch. Future work can add notarized distribution, streaming transcription and broader shortcut-layout support without background surveillance. Response history is a local user-facing archive, not model conversation memory.

## License

Voxen is open-source software available under the [MIT License](LICENSE).
