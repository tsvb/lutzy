import Foundation
import AppKit
import Observation

/// Owns the update flow: the daily background check, the manual one, the sheet, and the install.
///
/// Two checks with different manners. The **automatic** check runs at launch when a day has passed,
/// says nothing unless there is something newer than both the running version and a version the
/// user has chosen to skip, and swallows failures — a laptop without Wi-Fi does not need an alert
/// about GitHub. The **manual** check (LUTzy ▸ Check for Updates…) reports whatever it finds: newer,
/// up to date, skipped-but-newer, or the error.
///
/// The feed is injected as a closure so a test can drive every phase without a network; the
/// installer is injected the same way so a test never swaps a bundle. `AppVersion.current` is
/// injected too, because a test process has no `CFBundleShortVersionString`.
@Observable
@MainActor
final class UpdateCoordinator {

    enum Phase: Equatable {
        case checking
        case upToDate
        case available(Release)
        case downloading(Release)
        case installing(Release)
        case failed(String)
    }

    typealias Fetch = @Sendable () async throws -> Release
    typealias Install = @Sendable (Release) async throws -> URL

    private(set) var phase: Phase?
    var isSheetPresented = false

    /// Whether the sheet can offer "Install and Relaunch" or only the release page.
    let canInstallInPlace: Bool
    let currentVersion: AppVersion?

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let install: Install
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?

    static let automaticInterval: TimeInterval = 24 * 60 * 60

    init(
        currentVersion: AppVersion? = AppVersion.current,
        canInstallInPlace: Bool = UpdateInstaller.canInstallInPlace,
        defaults: UserDefaults = .standard,
        fetch: @escaping Fetch = { try await ReleaseFeed.fetchLatest() },
        install: @escaping Install = { try await UpdateInstaller.install($0) }
    ) {
        self.currentVersion = currentVersion
        self.canInstallInPlace = canInstallInPlace
        self.defaults = defaults
        self.fetch = fetch
        self.install = install
    }

    // MARK: - Preferences

    var checksAutomatically: Bool {
        get { defaults.bool(forKey: AppPreference.automaticUpdateChecks, default: true) }
        set { defaults.set(newValue, forKey: AppPreference.automaticUpdateChecks) }
    }

    var lastCheck: Date? {
        get { defaults.object(forKey: AppPreference.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: AppPreference.lastUpdateCheck) }
    }

    var skippedVersion: AppVersion? {
        get { defaults.string(forKey: AppPreference.skippedUpdateVersion).flatMap(AppVersion.init) }
        set { defaults.set(newValue?.description, forKey: AppPreference.skippedUpdateVersion) }
    }

    // MARK: - Checking

    /// True when the automatic check should run now: the preference is on, this is a packaged build
    /// with a version to compare, and the last check is older than a day (or never happened).
    var isAutomaticCheckDue: Bool {
        guard checksAutomatically, currentVersion != nil else { return false }
        guard let last = lastCheck else { return true }
        return Date().timeIntervalSince(last) >= Self.automaticInterval
    }

    /// The launch-time check. A no-op unless due; never shows anything but an available update.
    func checkAutomaticallyIfDue() {
        guard isAutomaticCheckDue else { return }
        check(userInitiated: false)
    }

    /// LUTzy ▸ Check for Updates…. Always reports.
    func checkNow() {
        check(userInitiated: true)
    }

    private func check(userInitiated: Bool) {
        if case .downloading = phase { return }
        if case .installing = phase { return }
        task?.cancel()
        if userInitiated {
            phase = .checking
            isSheetPresented = true
        }
        let fetch = self.fetch
        task = Task {
            let result: Result<Release, Error>
            do { result = .success(try await fetch()) } catch { result = .failure(error) }
            guard !Task.isCancelled else { return }
            lastCheck = Date()
            switch result {
            case .failure(let error):
                if userInitiated { phase = .failed(error.localizedDescription) }
                else { phase = nil }
            case .success(let release):
                if isNewer(release) {
                    if userInitiated || release.version != skippedVersion {
                        phase = .available(release)
                        isSheetPresented = true
                    } else {
                        phase = nil
                    }
                } else {
                    phase = userInitiated ? .upToDate : nil
                }
            }
        }
    }

    /// Newer than the running version. A build with no version — `swift run` — treats every release
    /// as newer so a manual check still shows what is out there.
    func isNewer(_ release: Release) -> Bool {
        guard let current = currentVersion else { return true }
        return release.version > current
    }

    // MARK: - Acting on it

    func skip(_ release: Release) {
        skippedVersion = release.version
        dismiss()
    }

    func remindLater() {
        dismiss()
    }

    func openReleasePage(_ release: Release) {
        NSWorkspace.shared.open(release.pageURL)
        dismiss()
    }

    /// Download, verify, swap, relaunch. The sheet stays up and shows each stage; on failure the
    /// message replaces it and nothing has changed on disk.
    func installAndRelaunch(_ release: Release) {
        guard canInstallInPlace else { return openReleasePage(release) }
        phase = .downloading(release)
        let install = self.install
        task = Task {
            do {
                let installed = try await install(release)
                guard !Task.isCancelled else { return }
                phase = .installing(release)
                // Let the sheet come down before asking the app to quit: see `relaunch`.
                isSheetPresented = false
                try? await Task.sleep(for: .milliseconds(300))
                UpdateInstaller.relaunch(installed)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func dismiss() {
        isSheetPresented = false
        phase = nil
    }
}
