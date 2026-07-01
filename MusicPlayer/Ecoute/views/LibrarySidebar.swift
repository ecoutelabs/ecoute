import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        let color = colorScheme == .dark
            ? viewModel.browsingAlbumAccentColorDark
            : viewModel.browsingAlbumAccentColorLight
        if let color { return color }
        return colorScheme == .dark
            ? Color(red: 0.608, green: 0.455, blue: 0.729)
            : Color(red: 0.482, green: 0.353, blue: 0.639)
    }

    var body: some View {
        List {
            Section {
                SidebarRow(
                    label: "Search",
                    icon: "magnifyingglass",
                    isSelected: viewModel.selectedSection == .search,
                    accent: accent
                ) {
                    viewModel.selectSection(.search)
                }
            }

            Section("Library") {
                SidebarRow(
                    label: "Albums",
                    icon: "square.grid.2x2",
                    isSelected: viewModel.selectedSection == .albums,
                    accent: accent
                ) {
                    viewModel.selectSection(.albums)
                }

                SidebarRow(
                    label: "Artists",
                    icon: "music.mic",
                    isSelected: viewModel.selectedSection == .artists,
                    accent: accent
                ) {
                    viewModel.selectSection(.artists)
                }

                SidebarRow(
                    label: "Songs",
                    icon: "music.note.list",
                    isSelected: viewModel.selectedSection == .songs,
                    accent: accent
                ) {
                    viewModel.selectSection(.songs)
                }

                SidebarRow(
                    label: "Genres",
                    icon: "guitars",
                    isSelected: viewModel.selectedSection == .genres,
                    accent: accent
                ) {
                    viewModel.selectSection(.genres)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Row

private struct SidebarRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.body)
            }
            .foregroundStyle(isSelected ? accent : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected
                ? RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(0.12))
                    .padding(.horizontal, 6)
                : nil
        )
    }
}
