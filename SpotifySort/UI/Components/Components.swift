import SwiftUI

struct ProviderCard: View {
    let title: String
    let subtitle: String
    let assetName: String
    let accent: Color
    let actionTitle: String
    let isLoading: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    private let r: CGFloat = 18

    var body: some View {
        ZStack {
            // match SwipeCard background language
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: r).stroke(.white.opacity(0.15), lineWidth: 1))
                .overlay(BrickOverlay().blendMode(.overlay))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .cornerRadius(6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline.weight(.semibold)).foregroundStyle(.white)
                        Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                }

                Button(action: action) {
                    HStack(spacing: 8) {
                        Spacer()
                        if isLoading { ProgressView().controlSize(.small) }
                        Text(actionTitle)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(accent.opacity(isDisabled ? 0.25 : 1), in: Capsule())
                    .foregroundStyle(isDisabled ? .black.opacity(0.6) : .black)
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .disabled(isDisabled || isLoading)
            }
            .padding(14)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
    }
}
