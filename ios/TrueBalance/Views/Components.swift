import SwiftUI

/// The card that carries a screen's main number: the cell colour with a soft
/// wash of `tint` and larger corners than the rows, so it reads as the top of
/// the hierarchy without shouting. Adapts to dark mode through the cell colour.
struct HeroCard<Content: View>: View {
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        shape.fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.03)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay { shape.strokeBorder(tint.opacity(0.14), lineWidth: 1) }
            }
            .animation(.smooth, value: tint)
    }
}

extension View {
    /// A list row that shows only its own card: no cell behind it, aligned
    /// with the other rows.
    func cardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    /// Opens `destination` when the row is tapped, without the chevron a
    /// NavigationLink adds (the card draws its own).
    func pushes<Destination: View>(@ViewBuilder _ destination: @escaping () -> Destination) -> some View {
        ZStack {
            NavigationLink(destination: destination) { EmptyView() }.opacity(0)
            self
        }
    }
}

/// Section title with an optional "See all" on the same line, so lists end
/// on their last item instead of an extra row.
struct SectionHeader<Destination: View>: View {
    var title: LocalizedStringKey
    var destination: (() -> Destination)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            if let destination {
                NavigationLink(destination: destination) {
                    Text("See all")
                        .font(.subheadline.weight(.medium))
                }
                .textCase(nil)
            }
        }
    }
}

extension SectionHeader where Destination == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.title = title
        self.destination = nil
    }
}

extension SectionHeader {
    init(_ title: LocalizedStringKey, seeAll: Bool, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.destination = seeAll ? destination : nil
    }
}

/// A small labelled amount, for the figures under a hero number.
struct Figure: View {
    var label: String
    var amount: Double
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(amount.shekels)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
        }
    }
}

/// Behind every screen: in dark mode a deep night blue instead of pure black,
/// in light mode the usual grey; both with a soft glow of `tint` at the top so
/// the screen has some colour without competing with the content.
struct AppBackground: View {
    var tint: Color = .accentColor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            if dark {
                LinearGradient(colors: [Color(hex: "#101A36"), Color(hex: "#080C18")], startPoint: .top, endPoint: .bottom)
            } else {
                Color(.systemGroupedBackground)
            }
            RadialGradient(colors: [tint.opacity(dark ? 0.32 : 0.13), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color.indigo.opacity(dark ? 0.22 : 0.07), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 440)
        }
        .animation(.smooth(duration: 0.6), value: tint)
        .ignoresSafeArea()
    }
}

extension View {
    /// Lists and forms on `AppBackground` instead of the flat system colour.
    func appBackground(_ tint: Color = .accentColor) -> some View {
        scrollContentBackground(.hidden)
            .background { AppBackground(tint: tint) }
    }
}
