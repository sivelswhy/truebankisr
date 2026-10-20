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
    @AppStorage("firstName") private var firstName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        ProfileAvatar(name: firstName, size: 84)
                        TextField("Your first name", text: $firstName)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .textContentType(.givenName)
                            .submitLabel(.done)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Used to greet you on the home screen.")
                        .frame(maxWidth: .infinity)
                }

                Section {
                    LabeledContent("Bank", value: "Leumi")
                    LabeledContent("Card", value: "Max")
                    NavigationLink {
                        EuroBanksSettingsView()
                    } label: {
                        LabeledContent("Other banks", value: model.euroConnections.isEmpty
                            ? String(localized: "No bank yet")
                            : model.euroConnections.map(\.bank.name).formatted(.list(type: .and)))
                    }
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
                        .onChange(of: hideAmounts) { model.updateWidgets() }
                } header: {
                    Text("Privacy")
                }

                Section {
                    Button("Language") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text("Available in English, French, Hebrew, Russian and Arabic. Choose the app’s language in Settings.")
                }

                Section {
                    Toggle("Show bank pages while signing in", isOn: $showBankPages)
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    Text("Shows Leumi and Max on screen during sign-in, so you can see what blocks and finish a step by hand if needed.")
                }

                Section {
                    ShareLink(item: LogFile(header: LogFile.header(model: model)), preview: SharePreview("True Balance log")) {
                        Label("Export the log", systemImage: "doc.text.magnifyingglass")
                    }
                    Button("Clear the log", role: .destructive) { Log.clear() }
                } footer: {
                    Text("What the app did when updating: steps, retries, errors. No passwords or amounts. It stays on this iPhone until you share it.")
                }

                Section {
                    Button(model.isDemo ? "Exit demo" : "Disconnect accounts", role: .destructive) {
                        confirmingSignOut = true
                    }
                }
            }
            .appBackground()
            .navigationTitle("Profile")
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
                Text("Your Leumi and Max credentials, the other banks’ access and the saved balances will be deleted from this iPhone.")
            }
        }
    }
}
