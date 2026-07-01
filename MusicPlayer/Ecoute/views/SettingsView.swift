import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Location") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(viewModel.libraryPath ?? "Not set")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Change…") {
                            viewModel.pickAlbumFolder()
                        }
                        .controlSize(.small)
                    }
                }

                HStack(spacing: 8) {
                    Button("Rescan") { viewModel.rescanLibrary() }
                    Button("Rescan & Clear Cache") { viewModel.rescanLibraryClearingCache() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Section("Appearance") {
                Toggle("Night Mode", isOn: $viewModel.isNightMode)
            }

            Section("Now Playing") {
                Picker("Idle timeout", selection: $viewModel.nowPlayingIdleTimeout) {
                    Text("Never").tag(0)
                    Text("5 seconds").tag(5)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                }
            }

            Section("Last.fm") {
                lastFMContent
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }

    // MARK: - Last.fm

    @ViewBuilder
    private var lastFMContent: some View {
        if let username = viewModel.lastFMUsername {
            // Linked state
            LabeledContent("Account") {
                Text(username)
                    .foregroundStyle(.secondary)
            }
            Button("Unlink", role: .destructive) {
                viewModel.unlinkLastFM()
            }
            .controlSize(.small)
        } else if viewModel.lastFMAuthPending {
            // Pending state
            LabeledContent("Status") {
                Text("Authorize in browser, then click Complete.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Complete Linking") { viewModel.completeLastFMAuth() }
                Button("Cancel") { viewModel.unlinkLastFM() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            // Not linked state
            LabeledContent("Status") {
                Text("Not linked")
                    .foregroundStyle(.secondary)
            }
            Button("Link Account…") { viewModel.startLastFMAuth() }
                .controlSize(.small)
        }
    }
}
