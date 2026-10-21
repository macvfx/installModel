import AppKit
import SwiftUI

struct InstallModelCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About InstallModel") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .help) {
            Button("InstallModel Help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Link("InstallModel Documentation", destination: URL(string: "https://github.com/macvfx/installModel#readme")!)
            Link("code.matx.ca", destination: URL(string: "https://code.matx.ca")!)
        }
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "0.2.3"
        let build = info?["CFBundleVersion"] as? String ?? "5"
        return "Version \(marketing) (Build \(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
            }
            Text("InstallModel").font(.largeTitle.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Install and run the MLX MiniMax H3 video model on supported Apple Silicon Macs, with portable model storage and hardware-aware settings.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Link("code.matx.ca", destination: URL(string: "https://code.matx.ca")!)
                .font(.headline)
            Text("Copyright © 2026 MATX Software")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(30)
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("InstallModel Help").font(.largeTitle.bold())
                Text("InstallModel separates model setup from clip generation. Complete Setup first, then use Generate with the environment file written by the installer.")

                helpSection("Before setup", icon: "person.crop.circle.badge.checkmark") {
                    Text("Create a Hugging Face account, review and accept the MiniMax H3 license yourself, install Homebrew if needed, and run `hf auth login` in Terminal. InstallModel never requests or stores your token.")
                    Text("After Homebrew is available, Install / Repair installs or checks Python 3.12, FFmpeg, Git, the Hugging Face CLI, and `uv`. Account login and license review remain manual.")
                }

                helpSection("Prepare or set up a Mac", icon: "shippingbox") {
                    Text("In Setup, confirm the detected chip and memory, choose Stage 1 to prepare portable model files or Stage 2 to reuse them on a target Mac, select storage locations, and run Preview, Check, then Install / Repair.")
                    Text("Keep an external model drive connected under the same volume name. A target Mac still needs its own Homebrew components, authentication, runtime, and generated environment file.")
                    Text("The selected installation root, Models folder, workflow, and profile are remembered on this Mac. Free-space checks follow the actual selected internal or attached volume.")
                    Text("Check is read-only. Install / Repair can restore its managed runtime files after preserving a patch, reuse completed downloads, repair a missing checkpoint index, and run the runtime doctor.")
                }

                helpSection("Generate a clip", icon: "film.stack") {
                    Text("Open Generate and use Load / Recheck for `minimax-h3-paths.env`. The last environment-file location is remembered and revalidated when the tab reopens. Edit the prompt and output name, then adjust resolution, duration, quality steps, seed, and advanced memory settings if required.")
                    Text("The output name creates both an MP4 and a performance-profile JSON. Existing results are never overwritten. Keep the Mac awake, connected to power, and attached to the model drive until generation finishes.")
                }

                helpSection("If something fails", icon: "wrench.and.screwdriver") {
                    Text("Reveal and preserve the operation log before retrying. Run Check again after repairing Homebrew, Hugging Face access, storage, or a disconnected drive. Do not delete partial model downloads; the installer is designed to verify and reuse them.")
                    Text("If Generate still shows an earlier missing-file warning after repair, choose Load / Recheck. Install / Repair force-refreshes a missing `FL2VA/model_index.json` and refuses to report success unless the required model indexes are readable.")
                    Text("A completed generation still needs playback, audio, motion, prompt-adherence, `ffprobe`, and decode review before it is accepted as valid media.")
                }

                Divider()
                HStack(spacing: 18) {
                    Link("Complete User Guide", destination: URL(string: "https://github.com/macvfx/installModel/blob/main/docs/TESTING_USER_GUIDE.md")!)
                    Link("README", destination: URL(string: "https://github.com/macvfx/installModel#readme")!)
                    Link("Report an issue", destination: URL(string: "https://github.com/macvfx/installModel/issues")!)
                    Link("code.matx.ca", destination: URL(string: "https://code.matx.ca")!)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func helpSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.title2.bold())
            content().foregroundStyle(.secondary)
        }
    }
}
