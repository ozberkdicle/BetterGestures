import AppKit
import GestureCore
import os
import ServiceManagement

@MainActor
@Observable
final class AppState {
    private static let log = Logger(subsystem: DebugLogger.subsystem, category: "app")

    /// one row of the gesture history in the ui.
    struct LogEntry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let gesture: Gesture
        let recognized: Bool
        let detail: String
        let sent: Bool
    }

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "enabled"); sync() }
    }
    var isDebug: Bool {
        didSet { UserDefaults.standard.set(isDebug, forKey: "debug"); sync() }
    }
    /// while gestures are on, swallow scrolls with 3+ fingers so three fingers only mean a gesture.
    var blocksMultiFingerScroll: Bool {
        didSet { UserDefaults.standard.set(blocksMultiFingerScroll, forKey: "blocksMultiFingerScroll"); sync() }
    }
    /// keep listening while the settings window is open (live view, row highlights).
    var isSettingsOpen = false {
        didSet { if isSettingsOpen != oldValue { sync() } }
    }
    /// no shortcuts are sent while the settings window is in front, gestures only light up.
    var isSettingsKey = false {
        didSet { if isSettingsKey != oldValue { sync() } }
    }

    private(set) var config = GestureConfig.default
    private(set) var bindings: [Gesture: KeyShortcut] = [:]
    private(set) var configWarnings: [String] = []
    private(set) var configError: String?
    private(set) var lastError: String?
    /// set when the event filter (scroll blocking, click gestures) couldn't be installed.
    private(set) var inputFilterError: String?
    private(set) var isAccessibilityTrusted = Accessibility.isTrusted
    private(set) var loginItemStatus = SMAppService.mainApp.status
    private(set) var devices: [TouchSource.Device] = []
    private(set) var history: [LogEntry] = []
    /// last recognized gesture, for the row highlight and the menu.
    private(set) var lastRecognized: LogEntry?
    let isMultitouchSupported = TouchSource.isSupported

    @ObservationIgnored private let pipeline = TouchPipeline()
    @ObservationIgnored private lazy var source = TouchSource { [pipeline] in pipeline.handle($0) }
    @ObservationIgnored private lazy var inputFilter = InputFilter(
        fingerState: { [pipeline] in pipeline.fingerState() },
        onClick: { [pipeline] in pipeline.click() })
    @ObservationIgnored private let logger = DebugLogger()
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var rescanWork: DispatchWorkItem?
    /// if the file failed to parse, back it up before the first save so a change in the ui doesn't
    /// silently wipe hand-written mappings.
    @ObservationIgnored private var backupBeforeSave = false

    init() {
        UserDefaults.standard.register(defaults: ["enabled": true, "debug": false, "blocksMultiFingerScroll": true])
        isEnabled = UserDefaults.standard.bool(forKey: "enabled")
        blocksMultiFingerScroll = UserDefaults.standard.bool(forKey: "blocksMultiFingerScroll")
        isDebug = UserDefaults.standard.bool(forKey: "debug")
            || ProcessInfo.processInfo.arguments.contains("--debug")
        setvbuf(stdout, nil, _IOLBF, 0)

        pipeline.setEventHandler { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(event) }
            }
        }
        source.observeDeviceChanges { [weak self] in self?.scheduleRescan() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRescan() }
        }

        reloadConfig()
        if !isAccessibilityTrusted { Accessibility.request() }

        // there's no notification for accessibility changes, a cheap poll is enough.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
    }

    // MARK: - mappings and thresholds

    /// set a shortcut from the ui, or remove it with `nil`. written to the config file right away.
    func setShortcut(_ shortcut: KeyShortcut?, for gesture: Gesture) {
        config.gestures[gesture.rawValue] = shortcut?.text
        applyConfig()
        saveConfig()
    }

    /// applied live while sliders move; written to the file with `saveConfig()`.
    var tuning: RecognizerTuning {
        get { config.tuning }
        set {
            config.tuning = newValue
            applyConfig()
        }
    }

    func saveConfig() {
        do {
            if backupBeforeSave {
                try ConfigStore.backup()
                backupBeforeSave = false
            }
            try ConfigStore.save(config)
            configError = nil
        } catch {
            configError = String(localized: "Config yazılamadı: \(error.localizedDescription)")
        }
    }

    func reloadConfig() {
        do {
            config = try ConfigStore.load()
            configError = nil
            backupBeforeSave = false
        } catch {
            backupBeforeSave = true
            // keep the previous mappings if the file is broken.
            configError = String(localized: "Config okunamadı: \(error.localizedDescription)")
        }
        applyConfig()
        let summary = "\(bindings.count) gestures loaded"
        for line in [summary] + configWarnings + [configError].compactMap({ $0 }) {
            print("[config] \(line)")
            Self.log.notice("\(line, privacy: .public)")
        }
    }

    func revealConfig() {
        _ = try? ConfigStore.load()
        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
    }

    func openConfig() {
        _ = try? ConfigStore.load()
        NSWorkspace.shared.open(ConfigStore.fileURL)
    }

    private func applyConfig() {
        let resolved = config.resolve()
        bindings = resolved.bindings
        configWarnings = resolved.warnings.map(\.text)
        sync()
    }

    // MARK: - permissions and login item

    var launchAtLogin: Bool {
        get { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                lastError = nil
            } catch {
                lastError = String(localized: "Girişte başlat: \(error.localizedDescription)")
                Self.log.error("\(self.lastError ?? "", privacy: .public)")
            }
            loginItemStatus = SMAppService.mainApp.status
        }
    }

    func requestAccessibility() {
        Accessibility.request()
        refreshStatus()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func refreshStatus() {
        let trusted = Accessibility.isTrusted
        if trusted != isAccessibilityTrusted {
            isAccessibilityTrusted = trusted
            sync()  // install the event filter if the permission was just granted
        }
        let status = SMAppService.mainApp.status
        if status != loginItemStatus { loginItemStatus = status }
    }

    // MARK: - touch source

    /// latest frame of each device (the live view reads it every frame).
    func latestFrames() -> [UInt64: TouchFrame] {
        pipeline.latestFrames()
    }

    func clearHistory() {
        history = []
    }

    private func receive(_ event: TouchPipeline.Event) {
        let entry = LogEntry(date: .now, gesture: event.gesture, recognized: event.recognized,
                             detail: event.detail, sent: event.sent)
        history.insert(entry, at: 0)
        if history.count > 80 { history.removeLast(history.count - 80) }
        if event.recognized { lastRecognized = entry }
    }

    /// pass settings to the touch side and start or stop listening as needed.
    private func sync() {
        pipeline.apply(.init(enabled: isEnabled, debug: isDebug, previewing: isSettingsKey,
                             bindings: bindings, tuning: config.tuning))
        syncInputFilter()
        let shouldListen = isEnabled || isDebug || isSettingsOpen
        if shouldListen, !source.isListening {
            startListening()
        } else if !shouldListen, source.isListening {
            source.stop()
            pipeline.reset()
            devices = []
        }
    }

    private func syncInputFilter() {
        // unmapped click gestures don't swallow the click anyway, so no separate setting.
        let options = InputFilter.Options(blockScroll: isEnabled && blocksMultiFingerScroll, captureClicks: isEnabled)
        let wanted = options != InputFilter.Options()
        if wanted, !inputFilter.isInstalled, !inputFilter.install() {
            inputFilterError = String(localized: "Kaydırma ve tıklama yakalanamıyor: Erişilebilirlik izni gerekli.")
        } else if inputFilter.isInstalled || !wanted {
            inputFilterError = nil
        }
        inputFilter.setOptions(options)
    }

    private func startListening() {
        pipeline.reset()
        devices = source.start()
        for d in devices {
            logger.emit(String(format: "[device] %@ %@ family=%d %.0fx%.0fmm", DebugLogger.label(d.id),
                               d.builtIn ? "built-in" : "external", d.familyID, d.width, d.height))
        }
        if devices.isEmpty { logger.emit("[device] no multitouch device found") }
    }

    /// device plugged/unplugged or woke from sleep: rescan. a bluetooth device can show up in iokit
    /// before multitouchsupport is ready for it, hence the short delay.
    private func scheduleRescan() {
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.source.isListening else { return }
                self.startListening()
            }
        }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}
