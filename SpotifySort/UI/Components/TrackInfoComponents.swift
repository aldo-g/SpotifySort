import SwiftUI

// Lightweight building blocks used by SwipeCard (and reusable elsewhere).

struct BrickTile<Content: View>: View {
    @ViewBuilder var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
    }
}

struct MetaRow: View {
    let system: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: system).font(.caption2).foregroundStyle(.white)
            Text(text).font(.caption).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

struct Pill: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
            .foregroundStyle(.white)
            .lineLimit(1)
    }
}

/// Simple left→right fill bar used for popularity.
struct PopularityBar: View {
    let value: Double   // 0...1
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 3).fill(.white)
                    .frame(width: max(0, min(1, value)) * w)
            }
        }
        .frame(height: 6)
    }
}

struct InfoBlock: View {
    let track: Track
    let genreChips: [String]
    let addedInfoLine: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(track.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if track.explicit == true {
                    Image(systemName: "e.square.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Explicit")
                }
            }
            Text(track.artists.map { $0.name }.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            let albumName = track.album.name
            if !albumName.isEmpty {
                Text(albumSubtitle(from: albumName, date: track.album.release_date))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            if !genreChips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(genreChips, id: \.self) { g in Pill(text: g.capitalized) }
                }
                .padding(.top, 2)
            }
            if let info = addedInfoLine { MetaRow(system: "clock", text: info) }
        }
    }
    private func albumSubtitle(from name: String, date: String?) -> String {
        let year = (date ?? "").prefix(4)
        return year.isEmpty ? name : "\(name) • \(year)"
    }
}
