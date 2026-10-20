import LocalAuthentication
import SwiftUI

/// Covers the app until Face ID / passcode succeeds.
struct LockView: View {
    var onUnlock: () -> Void
    @State private var failed = false

    var body: some View {
        VStack(spacing: 20) {
            Image("Logo")
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(.rect(cornerRadius: 17, style: .continuous))
                .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
                .accessibilityHidden(true)
            Text("True Balance is locked")
                .font(.title3.weight(.semibold))
            Button {
                Task { await authenticate() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(.headline)
                    .frame(minWidth: 180, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            if failed {
                Text("Couldn’t verify it’s you. Try again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AppBackground() }
        .task { await authenticate() }
    }

    private func authenticate() async {
        let context = LAContext()
        // Falls back to the device passcode when Face ID isn't available.
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                     localizedReason: String(localized: "Unlock to see your balance"))) ?? false
        if ok { onUnlock() } else { failed = true }
    }
}
