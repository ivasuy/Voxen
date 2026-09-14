import AppKit
import AVFoundation
import ApplicationServices
import os

enum RouterPhase: String {
    case idle = "Ready", listening = "Listening", transcribing = "Transcribing", transforming = "Transforming", done = "Done", error = "Error"
    var isBusy: Bool { self == .listening || self == .transcribing || self == .transforming }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var phase: RouterPhase = .idle
    @Published private(set) var detail = "Speak intent, not text."
    @Published private(set) var appName = ""
    @Published private(set) var mode: ContextMode = .generic
    @Published private(set) var hasSelection = false
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var websiteUnavailable = false
    @Published private(set) var contextAccessMissing = false
    let settings = AppSettings()
    let history = ResponseHistory()
    let writing = WritingPreferencesStore()
    let navigation = CommandNavigation()
    var onChange: (() -> Void)?
    var openSettings: (() -> Void)?
    private let recorder = AudioRecorder()
    private let output = ClipboardOutput()
    private var destination: ApplicationContext?
    private var writingSnapshot = WritingPreferences()
    private var captureTask: Task<CapturedContext, Never>?
    private var processingTask: Task<Void, Never>?
    private var levelTimer: Timer?
    private var startedAt: Date?
    private let log = Logger(subsystem: "dev.voiceintent.router", category: "Pipeline")

    func toggle() {
        if phase == .listening { finishRecording(); return }
        guard processingTask == nil else { return }
        startRecording()
    }

    private func startRecording() {
        do {
            guard settings.isConfigured else {
                openSettings?()
                throw RouterError.message("Add AssemblyAI and OpenRouter API keys in Settings.")
            }
            if OpenRouterProvider.isFreeModel(settings.model) { try FreeTierLimiter.shared.checkAvailability() }
            else { try FreeTierLimiter.shared.checkPaidAvailability() }
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                openSettings?()
                throw RouterError.message("Enable Microphone in Settings, then return to your app.")
            }
            let context = try ApplicationDetector().capture(override: settings.modeOverride)
            destination = context
            writingSnapshot = writing.saved
            appName = context.displayName
            websiteUnavailable = false
            contextAccessMissing = !AXIsProcessTrusted()
            mode = context.mode
            hasSelection = false
            try recorder.start()
            startedAt = Date()
            update(.listening, "\(settings.shortcut.label) to finish")
            // Audio starts immediately. The first browser capture may need Chromium's AX warm-up.
            captureTask = Task { [weak self] in
                let captured = await ApplicationDetector().captureDetails(context)
                if !Task.isCancelled, let self { self.showCapturedContext(captured) }
                return captured
            }
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.phase == .listening else { return }
                    self.audioLevel = self.recorder.level
                    if let startedAt = self.startedAt, Date().timeIntervalSince(startedAt) >= 120 { self.finishRecording() }
                }
            }
        } catch { clearCapture(); report(error) }
    }

    private func finishRecording() {
        levelTimer?.invalidate(); levelTimer = nil
        audioLevel = 0
        do {
            let audio = try recorder.stop()
            guard let destination else { throw RouterError.message("No destination application was captured.") }
            let pendingCapture = captureTask
            let preferences = writingSnapshot
            self.destination = nil
            let speech = AssemblyAIService(apiKey: settings.assemblyAIKey)
            let transformer = IntentTransformer(provider: OpenRouterProvider(apiKey: settings.openRouterKey, model: settings.model, limiter: .shared))
            update(.transcribing, "Writing…")
            processingTask = Task { [weak self] in
                guard let self else { return }
                defer { self.processingTask = nil; self.captureTask = nil }
                do {
                    let captured = await pendingCapture?.value ?? CapturedContext(application: destination, selectedText: nil,
                                                                                 accessibilityAvailable: AXIsProcessTrusted())
                    try Task.checkCancellation()
                    guard !captured.destinationChanged else {
                        throw RouterError.message("The page changed while capturing context. Keep the source highlighted and try again.")
                    }
                    let destination = captured.application
                    let transcript = try await speech.transcribe(audio: audio)
                    try Task.checkCancellation()
                    self.update(.transforming, "Writing…")
                    let generated = try await transformer.transformAndCopy(VoiceContext(
                        appName: destination.appName, bundleIdentifier: destination.bundleIdentifier,
                        mode: destination.mode, selectedText: captured.selectedText, transcript: transcript, website: destination.website,
                        modeIsOverride: destination.modeIsOverride, writingPreferences: preferences), to: self.output)
                    self.history.append(generated, appName: destination.appName,
                                        websiteHost: destination.website?.host, mode: destination.mode)
                    self.update(.done, "Press ⌘V to paste")
                } catch is CancellationError { self.update(.idle, "Cancelled") }
                catch { self.report(error) }
            }
        } catch { clearCapture(); report(error) }
    }

    func cancel() {
        clearCapture()
        if let processingTask { processingTask.cancel() }
        else { update(.idle, "Cancelled") }
    }

    func report(_ error: Error) {
        // Only our own sanitized messages reach UI; decoder errors may contain provider input.
        let message = (error as? RouterError)?.localizedDescription ?? (error as? HotkeyError)?.localizedDescription ?? (error as? APIHTTPError)?.localizedDescription
            ?? "The request could not be completed. Check your connection and Settings, then try again."
        log.error("Request failed (\(String(describing: type(of: error)), privacy: .public))")
        update(.error, message)
    }

    private func update(_ phase: RouterPhase, _ detail: String) {
        self.phase = phase; self.detail = detail
        onChange?()
    }

    private func showCapturedContext(_ capture: CapturedContext) {
        guard !capture.destinationChanged else { return }
        appName = capture.application.displayName
        hasSelection = capture.selectedText != nil
        contextAccessMissing = !capture.accessibilityAvailable
        websiteUnavailable = ApplicationDetector.isBrowser(bundleIdentifier: capture.application.bundleIdentifier)
            && capture.application.website == nil && !capture.application.modeIsOverride
        log.info("Context capture: accessibility=\(capture.accessibilityAvailable), website=\(capture.application.website != nil), selection=\(capture.selectedText != nil)")
        onChange?()
    }

    private func clearCapture() {
        recorder.cancel()
        captureTask?.cancel(); captureTask = nil
        levelTimer?.invalidate(); levelTimer = nil
        destination = nil; startedAt = nil; audioLevel = 0
    }

    func shutDown() { cancel() }
}
