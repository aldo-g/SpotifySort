import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var isStartingLogin = false

    var body: some View {
        ZStack {
            LinearGradient(colors: SelectrTheme.gradient,
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                VStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                    Text("Selectr")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Link your music")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Start by linking your Spotify account.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isStartingLogin = true
                    auth.login()
                } label: {
                    Image("Full_Logo_Green_RGB")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180)
                        .opacity(isStartingLogin ? 0.6 : 1.0)
                        .overlay {
                            if isStartingLogin {
                                ProgressView().tint(.white).scaleEffect(1.2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(isStartingLogin)
                .padding(.top, 10)

                Spacer()

                VStack(spacing: 6) {
                    Text("Permissions")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Selectr only reads your playlists and liked songs — nothing else.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            isStartingLogin = false
        }
    }
}
