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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button(action: action) {
                HStack {
                    Spacer()
                    if isLoading { ProgressView().controlSize(.small) }
                    Text(actionTitle).fontWeight(.semibold).lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(accent.opacity(isDisabled ? 0.25 : 1))
                .foregroundStyle(isDisabled ? .secondary : Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(isDisabled || isLoading)
        }
        .padding(14)
        .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}
