import SwiftUI

@main
struct TrueBalanceApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("requireFaceID") private var requireFaceID = false
    @State private var locked = UserDefaults.standard.bool(forKey: "requireFaceID")

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    switch model.phase {
                    case .signedOut: LoginView()
                    case .signedIn: DashboardView()
                    }
                }
                .animation(.smooth, value: model.phase)
                // Hide amounts in the app switcher.
                .blur(radius: scenePhase == .active ? 0 : 18)

                if locked && requireFaceID && model.phase == .signedIn {
                    LockView { withAnimation { locked = false } }
                        .transition(.opacity)
                }
            }
            .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if !(locked && requireFaceID) { Task { await model.refreshIfStale() } }
            case .background:
                if requireFaceID { locked = true }
                model.scheduleBackgroundRefresh()
            default: break
            }
        }
        .onChange(of: locked) { _, isLocked in
            if !isLocked { Task { await model.refreshIfStale() } }
        }
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
            await model.backgroundRefresh()
        }
    }
}
