import SwiftUI

struct PlaylistPickerView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI

    @State private var isLoading = false
    @State private var likedCount: Int? = nil
    @State private var isLoadingLiked = false

    var ownedPlaylists: [Playlist] {
        guard let me = api.user?.id else { return [] }
        return api.playlists.filter { $0.owner.id == me && $0.tracks.total > 0 }
    }

    var body: some View {
        List {
            Section("Your Playlists") {
                NavigationLink(value: "liked-songs") {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.purple.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "heart.fill").foregroundStyle(.purple)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Liked Songs").fontWeight(.semibold)
                            Text(likedSubtitleText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(ownedPlaylists) { pl in
                    NavigationLink(value: pl) {
                        HStack(spacing: 12) {
                            RemoteImage(url: pl.images?.first?.url)
                                .frame(width: 48, height: 48)
                                .cornerRadius(6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name).fontWeight(.semibold)
                                Text("\(pl.tracks.total) items")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .task { await loadData() }
    }

    private var likedSubtitleText: String {
        if isLoadingLiked { return "Loading…" }
        if let c = likedCount { return "\(c) items" }
        return "Saved tracks"
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        try? await api.loadMe(auth: auth)
        try? await api.loadPlaylists(auth: auth)
        await fetchLikedCount()
    }

    private func fetchLikedCount() async {
        guard !isLoadingLiked else { return }
        isLoadingLiked = true
        defer { isLoadingLiked = false }

        guard
            let token = auth.accessToken,
            var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")
        else { return }

        comps.queryItems = [URLQueryItem(name: "limit", value: "1")]
        guard let url = comps.url else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let total = obj["total"] as? Int {
                likedCount = total
            }
        } catch {
            likedCount = nil
            print("Failed to fetch liked count: \(error)")
        }
    }
}
