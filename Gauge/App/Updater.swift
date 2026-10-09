import SwiftUI
import Sparkle

/// In-app updates via Sparkle. The feed (`appcast.xml`) lives in the GitHub repo; each release's DMG is a
/// GitHub release asset, and every update is verified against the EdDSA public key in Info.plist.
@MainActor
final class UpdateController: ObservableObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheck = false
    @Published var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    @Published var automaticallyDownloads: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticallyDownloads }
    }

    init() {
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloads = controller.updater.automaticallyDownloadsUpdates
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main).assign(to: &$canCheck)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }
}

struct UpdatesTab: View {
    @ObservedObject var updater: UpdateController
    private var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }
    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version", value: version)
                LabeledContent("Last checked", value: updater.lastCheck.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                Button("Check for Updates Now", systemImage: "arrow.triangle.2.circlepath") { updater.checkForUpdates() }
                    .buttonStyle(.glassProminent).disabled(!updater.canCheck)
            }
            Section("Automatic updates") {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloads)
                    .disabled(!updater.automaticallyChecks)
                Text("Gauge follows its GitHub repository (cowens321-bit/Gauge). New releases are verified with an EdDSA signature before they are installed, so you never need to download a DMG again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
