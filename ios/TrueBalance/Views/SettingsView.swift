import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false
    @AppStorage("showBankPages") private var showBankPages = false
    @AppStorage("alertThreshold") private var alertThreshold = 0.0
    @AppStorage("requireFaceID") private var requireFaceID = false
    @AppStorage("hideAmounts") private var hideAmounts = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Bank", value: "Leumi")
                    LabeledContent("Card", value: "Max")
                } header: {
                    Text("Accounts")
                } footer: {
                    Text(model.isDemo
                        ? "You’re using sample data."
                        : "You stay signed in. Your credentials are kept in this iPhone’s Keychain.")
                }

                Section {
                    LabeledContent("Automatic refresh", value: String(localized: "When you open the app, and in the background"))
                } footer: {
                    Text("iOS decides when background refresh runs. You can also pull down to refresh at any time.")
                }

                Section {
                    Stepper(value: $alertThreshold, in: 0...20_000, step: 100) {
                        LabeledContent("Alert me below") {
                            Text(alertThreshold.formatted(.currency(code: "ILS").precision(.fractionLength(0))))
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(alertThreshold == 0
                        ? "You’ll be notified if your true balance goes below zero."
                        : "You’ll be notified when your true balance goes below this amount.")
                }

                Section {
                    Toggle("Lock with Face ID", isOn: $requireFaceID)
                    Toggle("Hide amounts", isOn: $hideAmounts)
                } header: {
                    Text("Privacy")
                }

                Section {
                    Button("Language") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text("English and French are available. Choose the app’s language in Settings.")
                }

                Section {
                    Toggle("Show bank pages while signing in", isOn: $showBankPages)
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    Text("Shows Leumi and Max on screen during sign-in, so you can see what blocks and finish a step by hand if needed.")
                }

                Section {
                    Button(model.isDemo ? "Exit demo" : "Disconnect accounts", role: .destructive) {
                        confirmingSignOut = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Disconnect accounts?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Disconnect and forget credentials", role: .destructive) {
                    dismiss()
                    model.signOut()
                }
            } message: {
                Text("Your Leumi and Max credentials and the saved balance will be deleted from this iPhone.")
            }
        }
    }
}
