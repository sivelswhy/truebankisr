import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model

    @State private var leumi = Credentials(username: "", password: "")
    @State private var max = Credentials(username: "", password: "")
    @State private var errors: [Provider: BankError] = [:]
    @State private var connecting = false
    @FocusState private var focus: Field?
    @AppStorage("showBankPages") private var showBankPages = false

    enum Field: Hashable { case user(Provider), password(Provider) }

    private var complete: Bool {
        [leumi, max].allSatisfy { !$0.username.trimmingCharacters(in: .whitespaces).isEmpty && !$0.password.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                accountSection(.leumi, title: "Bank Leumi", hint: "The username and password you use on leumi.co.il.", credentials: $leumi)
                accountSection(.max, title: "Max", hint: "The username and password you use on max.co.il.", credentials: $max)

                Section {
                    Button(action: connect) {
                        HStack(spacing: 10) {
                            if connecting { ProgressView().tint(.white) }
                            Text(connecting ? "Connecting to Leumi and Max…" : "Connect")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .disabled(!complete || connecting)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(connecting
                        ? LocalizedStringKey(Format.progress(model.progressStep))
                        : "Your credentials are stored in this iPhone’s Keychain and never leave it, except to sign in to Leumi and Max.")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }

                Section {
                    Button("Try with sample data") { model.startDemo() }
                        .frame(maxWidth: .infinity)
                        .disabled(connecting)
                }
                .listRowBackground(Color.clear)

                Section {
                    Toggle("Show bank pages while signing in", isOn: $showBankPages)
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    Text("Shows Leumi and Max on screen during sign-in, so you can see what blocks and finish a step by hand if needed.")
                }
            }
            .appBackground()
            .disabled(connecting)
            .scrollDismissesKeyboard(.interactively)
            .onSubmit(advance)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(.rect(cornerRadius: 17, style: .continuous))
                .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
                .accessibilityHidden(true)
            Text("True Balance")
                .font(.largeTitle.bold())
            Text("See what you can really spend: your Leumi balance minus the Max charges still to come.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func accountSection(_ provider: Provider, title: LocalizedStringKey, hint: LocalizedStringKey,
                                credentials: Binding<Credentials>) -> some View {
        Section {
            LabeledContent("Username") {
                TextField("Required", text: credentials.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .user(provider))
            }
            LabeledContent("Password") {
                RevealableSecureField(text: credentials.password)
                    .submitLabel(provider == .max ? .go : .next)
                    .focused($focus, equals: .password(provider))
            }
        } header: {
            Text(title)
        } footer: {
            if let error = errors[provider] {
                BankErrorText(error: error, provider: provider)
            } else {
                Text(hint)
            }
        }
        .onChange(of: credentials.wrappedValue) { errors[provider] = nil }
    }

    private func advance() {
        switch focus {
        case .user(let p): focus = .password(p)
        case .password(.leumi): focus = .user(.max)
        default: connect()
        }
    }

    private func connect() {
        guard complete, !connecting else { return }
        focus = nil
        connecting = true
        errors = [:]
        let leumi = Credentials(username: leumi.username.trimmingCharacters(in: .whitespaces), password: leumi.password)
        let max = Credentials(username: max.username.trimmingCharacters(in: .whitespaces), password: max.password)
        Task {
            let result = await model.signIn(leumi: leumi, max: max)
            connecting = false
            errors = result
            if let first = Provider.allCases.first(where: { result[$0] != nil }) {
                focus = .user(first)
            }
        }
    }
}

/// SecureField with an eye button to show what was typed.
struct RevealableSecureField: View {
    @Binding var text: String
    @State private var revealed = false

    var body: some View {
        HStack {
            Group {
                if revealed {
                    TextField("Required", text: $text)
                } else {
                    SecureField("Required", text: $text)
                }
            }
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(revealed ? Text("Hide password") : Text("Show password"))
        }
    }
}
