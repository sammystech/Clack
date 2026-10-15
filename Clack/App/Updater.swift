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

    private func download(_ url: URL, version: String) async {
        do {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("Clack-\(version).dmg")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            install(dmg: dest)
        } catch {
            alert("Download failed", error.localizedDescription)
        }
    }

    /// Hands the swap to a detached script: we can't replace our own bundle
    /// while running, so the script waits for us to quit, copies, and reopens.
    private func install(dmg: URL) {
        let appPath = Bundle.main.bundlePath
        let script = """
        #!/bin/bash
        DMG="\(dmg.path)"
        APP="\(appPath)"
        MOUNT=$(mktemp -d /tmp/clack-update-XXXXXX)

        # Wait for the running copy to exit (max ~10s).
        for _ in $(seq 1 50); do
          pgrep -f "$APP/Contents/MacOS/" >/dev/null || break
          sleep 0.2
        done

        hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MOUNT"
        NEW=$(find "$MOUNT" -maxdepth 1 -name "*.app" -print -quit)
        # Only install a build that is intact and signed by the same Developer ID team.
        if [ -n "$NEW" ] \\
           && codesign --verify --deep --strict "$NEW" 2>/dev/null \\
           && codesign -dv "$NEW" 2>&1 | grep -q "TeamIdentifier=\(Self.teamID)"; then
          rm -rf "$APP"
          cp -R "$NEW" "$APP"
          xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
        fi
        hdiutil detach "$MOUNT" -quiet || true
        rm -rf "$MOUNT" "$DMG"
        open "$APP"
        """
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("clack-update.sh")
        do {
            try script.write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [path.path]
            try task.run()
        } catch {
            alert("Update failed", error.localizedDescription)
            return
        }
        NSApp.terminate(nil)
    }
}
