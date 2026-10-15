import AppKit

// MARK: - Auto update (GitHub Releases)
//
// Compares the latest GitHub release tag to the bundle version, downloads the
// .dmg asset, verifies it is signed by the same Developer ID team, swaps the
// app in place and relaunches. Publishing is `./release.sh X.Y "notes"`.

@MainActor final class Updater {
    static let shared = Updater()

    static let repo = "sammystech/Clack"
    static let teamID = "CH6CSBA54G"
    static let autoInstallKey = "autoInstallUpdates"
    private let lastCheckKey = "lastUpdateCheck"
    private let skipKey = "skipVersion"
    private var checking = false

    /// Install updates without asking (Settings › General). On by default.
    static var autoInstall: Bool {
        UserDefaults.standard.object(forKey: autoInstallKey) as? Bool ?? true
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Entry points

    /// Checks shortly after launch, then every 6 hours while running.
    func startBackgroundChecks() {
        Task {
            try? await Task.sleep(for: .seconds(8))
            while true {
                let last = UserDefaults.standard.double(forKey: lastCheckKey)
                if Date().timeIntervalSince1970 - last > 6 * 60 * 60 {
                    await check(interactive: false)
                }
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    /// From a menu or Settings: always reports the outcome, even "you're up to date".
    func checkNow() {
        Task { await check(interactive: true) }
    }

    // MARK: Check

    private func check(interactive: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let json: [String: Any]
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["tag_name"] is String else { throw URLError(.cannotParseResponse) }
            json = obj
        } catch {
            if interactive { alert("Couldn't check for updates", error.localizedDescription) }
            return
        }

        let tag = json["tag_name"] as! String
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let notes = (json["body"] as? String) ?? ""
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        let dmgURL = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))

        guard Self.isNewer(latest, than: currentVersion) else {
            if interactive { alert("You're up to date", "Clack \(currentVersion) is the latest version.") }
            return
        }
        guard let dmgURL else {
            if interactive { alert("Update available", "Version \(latest) is out, but it has no download yet.") }
            return
        }
        // Respect a previous "Skip This Version" unless they asked explicitly.
        if !interactive, UserDefaults.standard.string(forKey: skipKey) == latest { return }
        if !interactive, Self.autoInstall {
            await download(dmgURL, version: latest)
            return
        }
        offer(version: latest, notes: notes, dmg: dmgURL)
    }

    /// Numeric, component-wise compare so 1.10 > 1.9.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: UI

    private func alert(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.alertStyle = .informational
        NSApp.activate()
        a.runModal()
    }

    private func offer(version: String, notes: String, dmg: URL) {
        let a = NSAlert()
        a.messageText = "Clack \(version) is available"
        a.informativeText = notes.isEmpty
            ? "You have \(currentVersion). Install the update now?"
            : "You have \(currentVersion).\n\n\(notes.prefix(600))"
        a.addButton(withTitle: "Install and Relaunch")
        a.addButton(withTitle: "Later")
        a.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch a.runModal() {
        case .alertFirstButtonReturn: Task { await download(dmg, version: version) }
        case .alertThirdButtonReturn: UserDefaults.standard.set(version, forKey: skipKey)
        default: break
        }
    }

    // MARK: Download + install

    private var downloadTask: URLSessionDownloadTask?

    private func download(_ url: URL, version: String) async {
        // Clack has to be able to replace its own bundle; catch that before downloading.
        if let problem = Self.installLocationProblem() {
            alert("Can't update Clack here", problem)
            return
        }
        let progress = UpdateProgress.shared
        progress.begin(version: version) { [weak self] in self?.downloadTask?.cancel() }

        do {
            let dmg = try await fetch(url, version: version) { fraction in
                Task { @MainActor in progress.fraction = fraction }
            }
            progress.phase = .installing
            try install(dmg: dmg)
        } catch let error as URLError where error.code == .cancelled {
            progress.close()
        } catch {
            progress.close()
            alert("Update failed", error.localizedDescription)
        }
    }

    /// Downloads with byte-level progress into a stable temp path.
    private func fetch(_ url: URL, version: String, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("Clack-\(version).dmg")
        let delegate = DownloadDelegate(destination: dest, onProgress: onProgress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            let task = session.downloadTask(with: url)
            downloadTask = task
            task.resume()
        }
    }

    /// nil when this copy can update itself in place, else why not.
    private static func installLocationProblem() -> String? {
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") {
            return "Clack is running from the download, not your Applications folder. Drag Clack into Applications, open it from there, then check for updates again."
        }
        let parent = (path as NSString).deletingLastPathComponent
        if !FileManager.default.isWritableFile(atPath: parent) {
            return "Clack can't write to \(parent). Move Clack into your Applications folder and try again."
        }
        return nil
    }

    /// Hands the swap to a detached script: we can't replace our own bundle while running,
    /// so the script waits for this process to exit, verifies the new build, swaps it in
    /// atomically (the old copy is restored on any failure), and reopens Clack.
    private func install(dmg: URL) throws {
        let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Clack")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let script = """
        #!/bin/bash
        exec >>"\(logDir.path)/update.log" 2>&1
        echo "== $(date) update from \(currentVersion)"
        DMG="\(dmg.path)"
        APP="\(Bundle.main.bundlePath)"
        PID=\(ProcessInfo.processInfo.processIdentifier)
        MOUNT=$(mktemp -d /tmp/clack-update-XXXXXX)

        # Wait for the running copy to exit (max ~20s).
        for _ in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done

        reopen() { hdiutil detach "$MOUNT" -quiet -force 2>/dev/null; rm -rf "$MOUNT" "$DMG"; open "$APP"; exit "$1"; }

        hdiutil attach "$DMG" -nobrowse -noautoopen -quiet -mountpoint "$MOUNT" || { echo "attach failed"; reopen 1; }
        NEW=$(find "$MOUNT" -maxdepth 1 -name "*.app" -print -quit)
        [ -n "$NEW" ] || { echo "no app in DMG"; reopen 1; }
        codesign --verify --deep --strict "$NEW" || { echo "signature invalid"; reopen 1; }
        codesign -dv "$NEW" 2>&1 | grep -q "TeamIdentifier=\(Self.teamID)" || { echo "wrong team"; reopen 1; }

        STAGE="$APP.updating"
        rm -rf "$STAGE" "$APP.old"
        ditto "$NEW" "$STAGE" || { echo "copy failed"; rm -rf "$STAGE"; reopen 1; }
        xattr -dr com.apple.quarantine "$STAGE" 2>/dev/null
        mv "$APP" "$APP.old" || { echo "could not move old app"; rm -rf "$STAGE"; reopen 1; }
        if mv "$STAGE" "$APP"; then
          rm -rf "$APP.old"
          echo "installed $(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
        else
          echo "swap failed, restoring"; mv "$APP.old" "$APP"
        fi
        reopen 0
        """
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("clack-update.sh")
        try script.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)

        // Double-fork through nohup so the script outlives this process.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "nohup /bin/bash \"$0\" >/dev/null 2>&1 &", path.path]
        try task.run()
        task.waitUntilExit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            AppModel.shared.quitClosingSheets()
        }
    }
}

/// Bridges URLSession's delegate callbacks (progress + finished file) to async/await.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let onProgress: @Sendable (Double) -> Void
    var continuation: CheckedContinuation<URL, Error>?   // touched only on the session's serial queue

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns, so move it now.
        let fm = FileManager.default
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            continuation?.resume(throwing: URLError(.badServerResponse)); continuation = nil; return
        }
        do {
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error) }
        continuation = nil
    }
}
