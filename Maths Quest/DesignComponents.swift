//
//  DesignComponents.swift
//  Maths Quest
//
//  The pieces the header, menus and forms share: cards, titles, the points chip and status messages. Each works out
//  its own colours for light and dark mode, so it reads the same on whichever background colour the child has chosen,
//  and each keeps the words VoiceOver reads.
//

import SwiftUI

/// Sizes the menus and forms share. (Not called `Layout`, which would hide SwiftUI's protocol of that name.)
enum Metrics {
    /// On iPad the menus, forms and questions sit in a centred column no wider than this, so rows of cards and lines
    /// of words stay a comfortable length. On iPhone the column is the screen's width.
    static let columnWidth: CGFloat = 600
    /// The smallest a button can be to tap, as Apple asks.
    static let minimumTapSize: CGFloat = 44
    static let cardCornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 12

    /// The width that sizes on the menus, forms and questions are worked out from: the screen's width, but no wider
    /// than the column, so words, cards and pictures don't grow too big on iPad. The header and the sidebar still
    /// span the screen.
    static var contentWidth: CGFloat {
        min(UIScreen.main.bounds.width, columnWidth)
    }
}

/// The colours of a card: white with black words in light mode, and dark grey with white words in dark mode. A card
/// brings its own background, so its words can be read whatever colour the child has chosen for the screen.
struct CardColour: ShapeStyle {
    enum Role: CaseIterable {
        /// The card itself.
        case surface
        /// Words: 21:1 on the card in light mode and about 14:1 in dark mode.
        case words
        /// Words that matter less, such as a description: over 7:1 in light and dark mode.
        case quietWords
        /// Icons: the system's blue, made darker or lighter until it reads at 4.5:1 on an icon's background, and so on
        /// the card too.
        case accent
        /// The pale square behind an icon: the system's blue, faint, on the card.
        case iconBackground
    }

    let role: Role

    func resolve(in environment: EnvironmentValues) -> Color {
        Color(Self.rgb(role, in: environment.colorScheme))
    }

    static func rgb(_ role: Role, in colorScheme: ColorScheme) -> Contrast.RGB {
        let dark = colorScheme == .dark
        switch role {
        case .surface:
            return dark ? Contrast.RGB(bytes: 44, 44, 46) : Contrast.white
        case .words:
            return dark ? Contrast.white : Contrast.black
        case .quietWords:
            return dark ? Contrast.RGB(bytes: 199, 199, 204) : Contrast.RGB(bytes: 84, 84, 88)
        case .accent:
            return Contrast.readable(Contrast.systemBlue.rgb(in: colorScheme), on: rgb(.iconBackground, in: colorScheme))
        case .iconBackground:
            return Contrast.composite(Contrast.systemBlue.rgb(in: colorScheme), opacity: 0.12,
                                      over: rgb(.surface, in: colorScheme))
        }
    }

    /// A colour such as green for "done", made darker or lighter until it reads at `minimum` on the card.
    static func readable(_ colour: Contrast.SystemColour, minimum: Double, in colorScheme: ColorScheme) -> Contrast.RGB {
        Contrast.readable(colour.rgb(in: colorScheme), on: rgb(.surface, in: colorScheme), minimum: minimum)
    }
}

extension ShapeStyle where Self == CardColour {
    /// A card's background. See `CardColour`.
    static var cardSurface: CardColour { CardColour(role: .surface) }
    /// Words on a card.
    static var cardWords: CardColour { CardColour(role: .words) }
    /// Words on a card that matter less, such as a description.
    static var cardQuietWords: CardColour { CardColour(role: .quietWords) }
    /// An icon on a card.
    static var cardAccent: CardColour { CardColour(role: .accent) }
    /// The square behind an icon on a card.
    static var cardIconBackground: CardColour { CardColour(role: .iconBackground) }
}

extension View {
    /// Puts the view on a card. See `CardColour`.
    func card(cornerRadius: CGFloat = Metrics.cardCornerRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.cardSurface)
                // A faint shadow keeps a white card apart from a pale background colour.
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
        }
    }

    /// On iPad, keeps a menu or form in a centred column no wider than `Metrics.columnWidth`.
    func readableColumn() -> some View {
        frame(maxWidth: Metrics.columnWidth)
            .frame(maxWidth: .infinity)
    }
}

/// A screen's title in plain bold words, with no underline, and an optional line under it, such as the ages for a
/// year. The title is a heading for VoiceOver. The two are separate, so each is read as it's written.
struct ScreenTitle: View {
    let title: String
    var subtitle: String? = nil
    /// How VoiceOver reads the subtitle, where that differs from how it's written, such as "Ages 5 to 6".
    var spokenSubtitle: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .scaledFont(size: Metrics.contentWidth * 0.1)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .scaledFont(size: 18, maximum: 28)
                    .fontWeight(.semibold)
                    .accessibilityLabel(spokenSubtitle ?? subtitle)
            }
        }
        .foregroundStyle(.onBackground)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The child's points, on a chip at the top right of every screen. The star says "points" to a child who can't read
/// the word yet. VoiceOver reads it as one item, "Points: 30". `height` is the height of the buttons beside it: the
/// chip stays its own size, but the item VoiceOver finds is as tall as they are, so it's reached between Home and
/// Settings, in the order they're seen.
///
/// `narrow` leaves out the star and some of the margin, for a header too narrow for the whole chip beside its buttons
/// at the largest text sizes. The words stay the same size, and are the words the header showed before the chip.
struct PointsChip: View {
    let points: Int
    var height: CGFloat? = nil
    var narrow = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            if !narrow {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color(CardColour.readable(Self.starColour, minimum: 3, in: colorScheme)))
            }
            Text("Points: \(points)")
                .fontWeight(.bold)
                .foregroundStyle(.cardWords)
        }
        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
        .padding(.horizontal, narrow ? 8 : 12)
        .padding(.vertical, 6)
        .background(.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(minHeight: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Points: \(points)"))
        .accessibilityAddTraits(.isStaticText)
    }

    /// The system's orange, which reads better than yellow once it's made dark enough for a white card.
    static let starColour = Contrast.SystemColour(light: Contrast.RGB(bytes: 255, 149, 0),
                                                  dark: Contrast.RGB(bytes: 255, 159, 10))
}

/// A message about what just happened, such as "Not enough points!", on a card. It stays until the child does
/// something else, rather than disappearing on a timer. The icon and the words both say whether it went well, so the
/// colour is never the only sign, and VoiceOver reads the message out as it appears.
struct StatusBanner: View {
    enum Tone {
        case success, problem, information

        /// A tick, a warning sign or an "i", so the colour is never the only sign of how it went.
        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .problem: "exclamationmark.triangle.fill"
            case .information: "info.circle.fill"
            }
        }

        /// The icon's colour, before it's made readable on the card.
        var colour: Contrast.SystemColour {
            switch self {
            case .success: Contrast.systemGreen
            case .problem: Contrast.systemRed
            case .information: Contrast.systemBlue
            }
        }
    }

    let message: String
    let tone: Tone
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: tone.symbol)
                .foregroundStyle(Color(CardColour.readable(tone.colour, minimum: 3, in: colorScheme)))
            Text(message)
                .foregroundStyle(.cardWords)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scaledFont(size: 18, maximum: 28)
        .fontWeight(.semibold)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isStaticText)
        .onAppear { announce(message) }
        .onChange(of: message) { _, newMessage in announce(newMessage) }
    }
}

/// A button with white words on a filled, rounded box: blue for Enter, green to buy and grey for the rest, each dark
/// enough for white words at 4.5:1. The whole box can be tapped, and it's never smaller than 44 points.
struct FilledButtonStyle: ButtonStyle {
    var colour: Color = .buttonBlue

    func makeBody(configuration: Configuration) -> some View {
        FilledButtonLabel(label: configuration.label, colour: colour, isPressed: configuration.isPressed)
    }
}

/// How a `FilledButtonStyle` button looks. A view of its own, so it can see when the button is turned off, as the
/// Remove Ads buttons are while the App Store is busy.
private struct FilledButtonLabel: View {
    let label: ButtonStyleConfiguration.Label
    let colour: Color
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .scaledFont(size: 20, maximum: 30)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(minWidth: 88, minHeight: Metrics.minimumTapSize)
            .background(colour, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isPressed ? 0.75 : isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    /// The white box a form's words are typed in, the same on every form and in dark mode: black words and a grey
    /// edge, at least 44 points tall, and a tap anywhere on it puts the cursor in it.
    func formTextBox() -> some View {
        textFieldStyle(.plain)
            .foregroundStyle(.black)
            .answerBoxMargin(12, tapHeight: Metrics.minimumTapSize)
            .frame(minHeight: Metrics.minimumTapSize)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.cardQuietWords, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            // Light mode inside the box, so the cursor, the grey hint and the edge are the ones made for white.
            .drawnOnWhite()
    }
}

/// What a menu card shows beside its name: an SF Symbol, or a few characters of maths, such as "0.5", where no symbol
/// says it as well.
enum CardIcon: Equatable {
    case symbol(String)
    case glyph(String)
}

/// The label of a button on a menu: a card with the name in bold and a line under it, such as the ages for a year or
/// what an activity asks. A card can have an icon at its left, with a chevron at its right to say it opens a screen, or
/// a row of small symbols for what it leads to. Every card on a menu is given the same smallest height, so they line
/// up, and fills the height it's given, so an `EqualCardGrid` can make them all the same size.
struct MenuCard: View {
    let title: String
    let subtitle: String
    var icon: CardIcon? = nil
    /// Small symbols for what the card leads to, such as + and − for Year 1. They're left out at the accessibility text
    /// sizes, where the room is needed for the words.
    var contents: [CardIcon] = []
    let titleSize: CGFloat
    let minHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Self.iconView(icon, symbolSize: 26, glyphSize: 22)
                    .frame(width: 52, height: 52)
                    .background(.cardIconBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .scaledFont(size: titleSize)
                    .fontWeight(.bold)
                    .foregroundStyle(.cardWords)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .scaledFont(size: 17, maximum: 24)
                    .fontWeight(.medium)
                    .foregroundStyle(.cardQuietWords)
                    .fixedSize(horizontal: false, vertical: true)
                if !contents.isEmpty && !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 6)
                    HStack(spacing: 6) {
                        ForEach(contents.indices, id: \.self) { index in
                            Self.iconView(contents[index], symbolSize: 16, glyphSize: 15)
                                .fixedSize()
                                .padding(.horizontal, 5)
                                .frame(minWidth: 32, minHeight: 30)
                                .background(.cardIconBackground,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            if icon != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.cardQuietWords)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
    }

    private static func iconView(_ icon: CardIcon, symbolSize: CGFloat, glyphSize: CGFloat) -> some View {
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: symbolSize, weight: .semibold))
            case .glyph(let characters):
                Text(characters)
                    .font(.system(size: glyphSize, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(.cardAccent)
        .accessibilityHidden(true)
    }
}

/// A card on a menu that opens `screen`. VoiceOver reads the name as the button's label, so it's found by the name on
/// the card, and then the line under it.
struct MenuCardButton: View {
    let screen: Screen
    let title: String
    let subtitle: String
    var spokenSubtitle: String? = nil
    var icon: CardIcon? = nil
    var contents: [CardIcon] = []
    let titleSize: CGFloat
    let minHeight: CGFloat

    var body: some View {
        ScreenButton(to: screen) {
            MenuCard(title: title, subtitle: subtitle, icon: icon, contents: contents, titleSize: titleSize,
                     minHeight: minHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(spokenSubtitle ?? subtitle)
    }
}

/// Lays out cards in `columns` equal columns, with every card as tall as the tallest, so all the cards on a menu are
/// the same size whatever their words, at every text size.
struct EqualCardGrid: Layout {
    var columns: Int
    var spacing: CGFloat = Metrics.cardSpacing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? idealWidth(of: subviews)
        let cell = cellSize(width: width, subviews: subviews)
        let rows = (subviews.count + columns - 1) / columns
        return CGSize(width: width, height: CGFloat(rows) * cell.height + CGFloat(rows - 1) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = cellSize(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let row = CGFloat(index / columns)
            let column = CGFloat(index % columns)
            subview.place(at: CGPoint(x: bounds.minX + column * (cell.width + spacing),
                                      y: bounds.minY + row * (cell.height + spacing)),
                          proposal: ProposedViewSize(cell))
        }
    }

    private func cellSize(width: CGFloat, subviews: Subviews) -> CGSize {
        let cellWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: cellWidth, height: height)
    }

    private func idealWidth(of subviews: Subviews) -> CGFloat {
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return widest * CGFloat(columns) + CGFloat(columns - 1) * spacing
    }
}

/// A menu's content at the top of the room below the header when it fits there, and in a scroll view when it doesn't,
/// such as at the largest text sizes on a small iPhone. Only for screens without a text field: a text field would lose
/// the keyboard if the keyboard's arrival made the content switch to scrolling.
struct ScrollsIfNeeded<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
                .frame(maxHeight: .infinity, alignment: .top)
            ScrollView {
                content
            }
        }
    }
}

/// Marks the part of a form that holds its Enter button: the whole card, so the card's own padding is the gap left
/// under Enter. When the keyboard comes up, `FormScreen` scrolls it to just above the keyboard.
enum FormSubmitRow: Hashable {
    case id
}

extension View {
    /// Marks the card that holds a form's Enter button. See `FormSubmitRow`.
    func formSubmitRow() -> some View {
        id(FormSubmitRow.id)
    }
}

/// A form screen, such as the Shop or Settings: the background colour, the same header as every other screen, and the
/// form in a centred column below it. Header and form are in one stack, so when the keyboard comes up it's the form's
/// room that gets shorter, never the header that moves, and nothing can be drawn over the points or the menu button.
///
/// A form with a text box scrolls, and scrolls its `formSubmitRow()` to just above the keyboard. A form that fits its
/// own room, such as Feedback, whose box gets shorter instead, passes `scrolls: false`. `reveal` is the id of a view,
/// such as a new message, to scroll into sight whenever it changes.
struct FormScreen<Content: View>: View {
    let selectedTab: String
    let scrolls: Bool
    let reveal: AnyHashable?
    let content: Content
    @State private var isSidebarOpen = false
    @EnvironmentObject private var gameData: GameData
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selectedTab: String, scrolls: Bool = true, reveal: AnyHashable? = nil, @ViewBuilder content: () -> Content) {
        self.selectedTab = selectedTab
        self.scrolls = scrolls
        self.reveal = reveal
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture { hideKeyboard() }

            VStack(spacing: 0) {
                NavigationBar(Back: false, Points: true, isSidebarOpen: $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .edgesIgnoringSafeArea(.top)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)

                if scrolls {
                    scrollingForm
                } else {
                    VStack(spacing: 16) {
                        content
                    }
                    .padding([.horizontal, .top])
                    // Keeps Enter off the edge of the keyboard.
                    .padding(.bottom, 12)
                    .readableColumn()
                    // A form taller than its room runs on down under the keyboard, never up under the header.
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .sidebarOverlay(isOpen: $isSidebarOpen, selectedTab: selectedTab)
        .navigationBarBackButtonHidden(true)
    }

    private var scrollingForm: some View {
        GeometryReader { space in
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 20) {
                        content
                    }
                    .padding()
                    .readableColumn()
                    .frame(minHeight: space.size.height, alignment: .top)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { hideKeyboard() }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    withAnimation(reduceMotion ? nil : .default) {
                        scroller.scrollTo(FormSubmitRow.id, anchor: .bottom)
                    }
                }
                .onChange(of: reveal) { _, target in
                    guard let target else { return }
                    // On the next turn, once the new message is laid out and has a place to scroll to.
                    DispatchQueue.main.async {
                        withAnimation(reduceMotion ? nil : .default) {
                            scroller.scrollTo(target, anchor: nil)
                        }
                    }
                }
            }
        }
    }
}

/// The ages of the children in each year, shown under the year's name.
enum SchoolYear {
    /// "Ages 5–6" for Year 1, as written on the cards.
    static func ages(_ year: Int) -> String {
        "Ages \(year + 4)–\(year + 5)"
    }

    /// "Ages 5 to 6", as VoiceOver reads it.
    static func spokenAges(_ year: Int) -> String {
        "Ages \(year + 4) to \(year + 5)"
    }
}

extension Activity {
    /// The line under the activity's name on its year's menu: what its questions ask, in words a child can follow.
    var summary: String {
        switch self {
        case .counting: "Find the missing number"
        case .addition: "Add two numbers up to 9"
        case .subtraction: "Take away numbers up to 9"
        case .multiplication: "The 2, 5 and 10 times tables"
        case .division: "Divide by 2, 5 and 10"
        case .shapes: "Sides, corners and shape names"
        case .fractions: "Simplify and find fractions"
        case .measurement: "Use a ruler and convert units"
        case .time: "Clocks, hours and minutes"
        case .decimals: "Add, subtract, multiply tenths"
        case .geometry: "Perimeter, area and angles"
        case .money: "Add, subtract and convert money"
        case .percentages: "Find a percentage of a number"
        case .statistics: "Mean, mode and bar charts"
        case .volume: "Cubes, cuboids and capacity"
        case .algebra: "Solve, simplify and expand"
        case .probability: "Dice, spinners, coins and more"
        case .ratios: "Simplify and share in a ratio"
        }
    }

    /// The icon beside the activity's name on its year's menu.
    var icon: CardIcon {
        switch self {
        case .counting: .symbol("textformat.123")
        case .addition: .symbol("plus")
        case .subtraction: .symbol("minus")
        case .multiplication: .symbol("multiply")
        case .division: .symbol("divide")
        case .shapes: .symbol("square.on.circle")
        case .fractions: .symbol("chart.pie")
        case .measurement: .symbol("ruler")
        case .time: .symbol("clock")
        case .decimals: .glyph("0.5")
        case .geometry: .symbol("angle")
        case .money: .symbol("sterlingsign.circle")
        case .percentages: .symbol("percent")
        case .statistics: .symbol("chart.bar")
        case .volume: .symbol("cube")
        case .algebra: .glyph("x")
        case .probability: .symbol("dice")
        case .ratios: .glyph("1:2")
        }
    }
}
