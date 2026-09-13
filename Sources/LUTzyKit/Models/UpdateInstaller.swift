import Foundation
import AppKit
import Security

/// Replaces the running app with the one inside a downloaded disk image, then relaunches.
///
/// There is no Sparkle here — zero third-party dependencies — so this is the whole mechanism,
/// and it is deliberately small:
///
/// 1. Download the DMG to a private temp directory.
/// 2. Mount it read-only with `hdiutil`, at a mount point of our choosing.
/// 3. **Verify the new app's code signature** against a requirement built from the running app:
///    Apple-anchored Developer ID, the same Team ID, the same bundle identifier, strict and nested.
///    A download that fails this is thrown away, whatever the feed said. This is the step that
///    makes "fetch a binary from the internet and run it" acceptable; an unsigned running app —
///    `swift run` — has no Team ID to check against and cannot install at all.
/// 4. Copy the app next to the current one (same volume, so the swap is two renames), swap, and
///    delete the old bundle. The running process keeps its unlinked files and is unaffected.
/// 5. Detach, then hand `open` to a shell that waits for this process to exit, and terminate.
///
/// Everything here is `nonisolated` and blocking-free from the caller's point of view: the
/// coordinator awaits it from the main actor while the sheet shows progress.
enum UpdateInstaller {

    enum InstallError: LocalizedError {
        case notAnAppBundle
        case runningAppUnsigned
        case noDiskImage
        case mountFailed(String)
        case noAppInImage
        case signatureRejected(String)
        case destinationNotWritable(URL)
        case swapFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAnAppBundle:
                return "This build is not an app bundle, so it cannot replace itself. Download the release instead."
            case .runningAppUnsigned:
                return "This copy of LUTzy is not signed, so a downloaded update cannot be verified against it."
            case .noDiskImage:
                return "The release has no disk image to install from."
            case .mountFailed(let detail):
                return "The disk image could not be opened. \(detail)"
            case .noAppInImage:
                return "The disk image does not contain an app."
            case .signatureRejected(let detail):
                return "The downloaded app failed signature verification and was discarded. \(detail)"
            case .destinationNotWritable(let url):
                return "LUTzy cannot write to \(url.path). Move the app somewhere you own, or install the update by hand."
            case .swapFailed(let detail):
                return "The update could not be put in place. \(detail)"
            }
        }
    }

    /// The identity the running app was signed with, or `nil` when it is unsigned or not a bundle.
    struct SigningIdentity: Sendable, Equatable {
        let teamID: String
        let bundleID: String
    }

    static func signingIdentity(of bundleURL: URL) -> SigningIdentity? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let team = dict[kSecCodeInfoTeamIdentifier as String] as? String,
              let bundle = dict[kSecCodeInfoIdentifier as String] as? String
        else { return nil }
        return SigningIdentity(teamID: team, bundleID: bundle)
    }

    /// The running app, if it is a real bundle: `swift run` yields a bare executable whose
    /// `bundleURL` is a directory of build products, not an `.app`.
    static var runningAppBundle: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// True when this process could replace itself: a signed `.app`.
    static var canInstallInPlace: Bool {
        guard let app = runningAppBundle else { return false }
        return signingIdentity(of: app) != nil
    }

    // MARK: - Steps

    static func download(_ url: URL, session: URLSession = .shared) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LUTzy Update \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (temp, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ReleaseFeed.FeedError.badStatus(http.statusCode)
        }
        let dmg = dir.appendingPathComponent(url.lastPathComponent.isEmpty ? "update.dmg" : url.lastPathComponent)
        try FileManager.default.moveItem(at: temp, to: dmg)
        return dmg
    }

    /// Mount read-only at a fresh mount point and return it.
    static func mount(_ dmg: URL) async throws -> URL {
        let point = dmg.deletingLastPathComponent().appendingPathComponent("mount", isDirectory: true)
        let result = try await run("/usr/bin/hdiutil", [
            "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-noverify",
            "-mountpoint", point.path,
        ])
        guard result.status == 0 else { throw InstallError.mountFailed(result.output) }
        return point
    }

    static func detach(_ mountPoint: URL) async {
        _ = try? await run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
    }

    static func findApp(in mountPoint: URL) throws -> URL {
        let entries = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
        guard let app = entries.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.noAppInImage
        }
        return app
    }

    /// Check the new bundle against the running app's identity. The requirement language is
    /// Apple's own (`man csreq`): a Developer ID chain, this team, this bundle identifier.
    static func verify(_ appURL: URL, against identity: SigningIdentity) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            throw InstallError.signatureRejected("The app could not be read.")
        }
        let text = "anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6]"      // Developer ID CA
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"  // Developer ID Application
            + " and certificate leaf[subject.OU] = \"\(identity.teamID)\""
            + " and identifier \"\(identity.bundleID)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            throw InstallError.signatureRejected("The verification requirement could not be built.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        var errors: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, req, &errors)
        if status != errSecSuccess {
            let detail = errors?.takeRetainedValue().localizedDescription ?? "OSStatus \(status)"
            throw InstallError.signatureRejected(detail)
        }
    }

    /// Put `newApp` where `currentApp` is. Copy first (cross-volume), then two renames.
    static func swap(newApp: URL, into currentApp: URL) throws {
        let fm = FileManager.default
        let parent = currentApp.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else {
            throw InstallError.destinationNotWritable(parent)
        }
        let token = UUID().uuidString
        let staged = parent.appendingPathComponent(".LUTzy-update-\(token).app")
        let retired = parent.appendingPathComponent(".LUTzy-old-\(token).app")
        do {
            try fm.copyItem(at: newApp, to: staged)
        } catch {
            throw InstallError.swapFailed(error.localizedDescription)
        }
        do {
            try fm.moveItem(at: currentApp, to: retired)
        } catch {
            try? fm.removeItem(at: staged)
            throw InstallError.swapFailed(error.localizedDescription)
        }
        do {
            try fm.moveItem(at: staged, to: currentApp)
        } catch {
            try? fm.moveItem(at: retired, to: currentApp)
            try? fm.removeItem(at: staged)
            throw InstallError.swapFailed(error.localizedDescription)
        }
        try? fm.removeItem(at: retired)
    }

    /// Relaunch once this process has gone. `open` is deferred to a shell that polls the PID, so
    /// there is never a moment with two copies running and Launch Services always starts the new
    /// bundle rather than reusing this one.
    ///
    /// **Quitting is not left to `NSApp.terminate` alone** — measured, not assumed. In the first
    /// end-to-end run the swap landed, the shell was waiting, and the old process stayed up behind
    /// its "Installing…" sheet: `terminate(_:)` sent from under a presented SwiftUI sheet did not
    /// end the app. So the caller dismisses the sheet first, and if the process is still here a
    /// second after `terminate`, it exits outright. There is nothing to save — preferences are
    /// already with `cfprefsd` — and the whole point of this call is to stop existing.
    @MainActor
    static func relaunch(_ appURL: URL) {
        let script = "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, appURL.path, String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
        UpdateCoordinator.log.info("relaunch helper started; terminating")
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UpdateCoordinator.log.info("terminate was ignored; exiting")
            exit(0)
        }
    }

    // MARK: - The whole thing

    /// Download, verify and swap. Returns the path of the installed app; the caller relaunches.
    static func install(_ release: Release) async throws -> URL {
        guard let currentApp = runningAppBundle else { throw InstallError.notAnAppBundle }
        guard let identity = signingIdentity(of: currentApp) else { throw InstallError.runningAppUnsigned }
        guard let dmgURL = release.diskImageURL else { throw InstallError.noDiskImage }

        let dmg = try await download(dmgURL)
        UpdateCoordinator.log.info("downloaded \(dmg.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: dmg.deletingLastPathComponent()) }
        let mountPoint = try await mount(dmg)
        UpdateCoordinator.log.info("mounted at \(mountPoint.path)")
        do {
            let newApp = try findApp(in: mountPoint)
            try verify(newApp, against: identity)
            UpdateCoordinator.log.info("signature verified for team \(identity.teamID)")
            try swap(newApp: newApp, into: currentApp)
            UpdateCoordinator.log.info("swapped into \(currentApp.path)")
        } catch {
            await detach(mountPoint)
            throw error
        }
        await detach(mountPoint)
        return currentApp
    }

    // MARK: - Process helper

    private struct RunResult: Sendable {
        let status: Int32
        let output: String
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws -> RunResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { p in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: RunResult(status: p.terminationStatus, output: text))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
