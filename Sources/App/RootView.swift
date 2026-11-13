import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(UILanguage.key) private var uiLanguage = ""

    var body: some View {
        Group {
            if !UILanguage.chosen {
                LanguageChoiceView()
            } else {
                switch state.phase {
                case .loading:
                    VStack(spacing: 16) {
                        LogoMark(size: 64)
                        ProgressView().tint(Theme.black)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.white)
                case .signedOut:
                    WelcomeView()
                case .signedIn:
                    HomeView()
                }
            }
        }
        // Every screen is rebuilt when the interface language changes.
        .id(uiLanguage)
        .task { await state.start() }
    }
}

/// The very first screen: choose the interface language. Many diaspora phones are set to
/// English, so the phone's own setting is not a good guess.
struct LanguageChoiceView: View {
    @AppStorage(UILanguage.key) private var uiLanguage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Spacer()
            LogoMark(size: 72)
            Text("ቋንቋ ይምረጡ").font(Theme.title).foregroundStyle(Theme.black)
            Text("Choose your language").font(Theme.heading).foregroundStyle(Theme.muted)
            ForEach(UILanguage.allCases) { language in
                Button(language.name) {
                    Haptics.tap()
                    uiLanguage = language.rawValue
                }
                .buttonStyle(language == .am ? AnyButtonStyle(PrimaryButtonStyle())
                                              : AnyButtonStyle(SecondaryButtonStyle()))
                .accessibilityIdentifier("language-" + language.rawValue)
            }
            Text("በኋላ በመለያ ገጽ መቀየር ይችላሉ። You can change this later in Account.")
                .font(Theme.small).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, Theme.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.white)
    }
}

/// Lets one call site pick between two button styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
