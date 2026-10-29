import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(viewModel.libraryPath ?? "Not set")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Change…") {
                            viewModel.pickAlbumFolder()
                        }
                    }
                } label: {
                    SettingsLabel("Location", icon: "folder.fill", color: .blue)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Rescan") { viewModel.rescanLibrary() }
                    Button("Rescan & Clear Cache") { viewModel.rescanLibraryClearingCache() }
                }
            }

            Section("Appearance") {
                Toggle(isOn: $viewModel.isNightMode) {
                    SettingsLabel("Night Mode", icon: "moon.fill", color: .indigo)
                }
                .toggleStyle(.switch)
            }

            Section("Now Playing") {
                Picker(selection: $viewModel.nowPlayingIdleTimeout) {
                    Text("Never").tag(0)
                    Text("5 seconds").tag(5)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                } label: {
                    SettingsLabel("Idle timeout", icon: "timer", color: .orange)
                }
            }

            Section("Last.fm") {
                lastFMContent
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        // No "Ecoute Settings" title or title bar; the form runs to the top.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    // MARK: - Last.fm

    @ViewBuilder
    private var lastFMContent: some View {
        if let username = viewModel.lastFMUsername {
            // Linked state
            LabeledContent {
                HStack(spacing: 8) {
                    Text(username)
                        .foregroundStyle(.secondary)
                    Button("Unlink", role: .destructive) {
                        viewModel.unlinkLastFM()
                    }
                }
            } label: {
                SettingsLabel("Account", icon: "person.crop.circle.fill", color: .red)
            }
        } else if viewModel.lastFMAuthPending {
            // Pending state
            LabeledContent {
                Text("Authorize in browser, then click Complete.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } label: {
                SettingsLabel("Status", icon: "person.crop.circle.fill", color: .red)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { viewModel.unlinkLastFM() }
                Button("Complete Linking") { viewModel.completeLastFMAuth() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            // Not linked state
            LabeledContent {
                HStack(spacing: 8) {
                    Text("Not linked")
                        .foregroundStyle(.secondary)
                    Button("Link Account…") { viewModel.startLastFMAuth() }
                }
            } label: {
                SettingsLabel("Status", icon: "person.crop.circle.fill", color: .red)
            }
        }
    }
}

/// A row title with a System Settings–style colored icon tile.
private struct SettingsLabel: View {
    let title: String
    let icon: String
    let color: Color

    init(_ title: String, icon: String, color: Color) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
        }
    }
}
