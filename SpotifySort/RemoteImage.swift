import SwiftUI
import UIKit

struct RemoteImage: View {
    let url: String?
    @State private var img: Image? = nil

    var body: some View {
        ZStack {
            if let img {
                img
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.15))
                    .overlay(ProgressView())
            }
        }
        .clipped()
        .task(id: url) {
            guard let url, let u = URL(string: url) else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: u)
                if let ui = UIImage(data: data) {
                    await MainActor.run { self.img = Image(uiImage: ui) }
                }
            } catch {
                print("RemoteImage load failed: \(error)")
            }
        }
    }
}
