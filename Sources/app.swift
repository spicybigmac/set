import SwiftUI
import AVFoundation

// MARK: - Customizable Configuration
enum Config {
    // Screen Base Dimensions (iPhone 16)
    static let baseWidth: CGFloat = 393
    static let baseHeight: CGFloat = 852
    static let macWindowHeight: CGFloat = 740

    // End screen text
    static let endScreenMessage: String = "All possible sets have been found!"
    static let playAgainButtonText: String = "Play Again"

    // Animation & Transition Rates (in seconds)
    static let backlightFadeDuration: Double = 0.12
    static let slideAnimationDuration: Double = 0.3
    static let endScreenFadeDuration: Double = 0.35

    // Card Sizing (Landscape cards: Width > Height)
    static let cardAspectRatio: CGFloat = 1.50
    static let symbolAspectRatio: CGFloat = 2.10

    // Proportional symbol sizing (% of card container)
    static let symbolWidthRatio: CGFloat = 0.20
    static let symbolHeightRatio: CGFloat = 0.58
    static let symbolSpacingRatio: CGFloat = 0.07
    static let outlineThickness: CGFloat = 3.2
    static let stripeSpacing: CGFloat = 4

    // Sound effect filenames
    static let correctSoundFilename: String = "correct.wav"
    static let incorrectSoundFilename: String = "incorrect.wav"

    // Default RGB Colors for Card Features (0.0 to 1.0)
    static let defaultColor1 = RGBColor(r: 0.90, g: 0.15, b: 0.20) // Red
    static let defaultColor2 = RGBColor(r: 0.10, g: 0.70, b: 0.30) // Green
    static let defaultColor3 = RGBColor(r: 0.50, g: 0.15, b: 0.85) // Purple
}

// MARK: - Audio Manager
class AudioManager {
    static let shared = AudioManager()
    private var player: AVAudioPlayer?

    func play(filename: String, volume: Float) {
        guard volume > 0 else { return }
        let url = URL(fileURLWithPath: filename)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.volume = volume
                player?.play()
            } catch {}
        }
    }
}

// MARK: - Models
struct RGBColor: Equatable, Codable {
    var r: Double
    var g: Double
    var b: Double

    var color: Color {
        Color(red: r, green: g, blue: b)
    }
}

enum Feature: Int, CaseIterable, Codable {
    case one = 1, two = 2, three = 3
}

struct Card: Identifiable, Equatable {
    let id = UUID()
    let count: Feature
    let shape: Feature
    let colorIndex: Feature
    let shading: Feature
}

struct ActiveCard: Identifiable, Equatable {
    let id: UUID
    let card: Card
    var slot: Int
    var isDeparting: Bool = false
    var isEntering: Bool = false

    init(card: Card, slot: Int, isEntering: Bool = false) {
        self.id = card.id
        self.card = card
        self.slot = slot
        self.isEntering = isEntering
    }
}

enum AnimationType: String, CaseIterable, Identifiable {
    case replace = "Replace"
    case slide = "Slide"
    var id: String { rawValue }
}

enum SortCriteria {
    case newestDate, oldestDate, fastestTime, slowestTime
}

struct GameRecord: Identifiable, Codable {
    let id: UUID
    let timeInSeconds: Int
    let setsFound: Int
    let date: Date

    var formattedTime: String {
        let h = timeInSeconds / 3600
        let m = (timeInSeconds % 3600) / 60
        let s = timeInSeconds % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - App State
class AppState: ObservableObject {
    @Published var currentPage: Page = .home
    @Published var isDarkMode: Bool = true
    @Published var focusMode: Bool = false
    @Published var sfxVolume: Float = 0.8
    @Published var animationType: AnimationType = .slide

    @Published var color1: RGBColor = Config.defaultColor1
    @Published var color2: RGBColor = Config.defaultColor2
    @Published var color3: RGBColor = Config.defaultColor3

    @Published var history: [GameRecord] = []

    func color(for index: Feature) -> Color {
        switch index {
        case .one: return color1.color
        case .two: return color2.color
        case .three: return color3.color
        }
    }
}

enum Page {
    case home, play, settings, history
}

// MARK: - Entry Point
@main
struct SetGameApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                (appState.isDarkMode ? Color(white: 0.08) : Color(white: 0.96))
                    .ignoresSafeArea()

                switch appState.currentPage {
                case .home:
                    HomeView()
                case .play:
                    PlayView()
                case .settings:
                    SettingsView()
                case .history:
                    HistoryView()
                }
            }
            #if os(macOS)
            .frame(width: Config.baseWidth, height: Config.macWindowHeight, alignment: .top)
            #else
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            #endif
            .environmentObject(appState)
            .preferredColorScheme(appState.isDarkMode ? .dark : .light)
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Home Page
struct HomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("SET")
                .font(.system(size: 64, weight: .black, design: .monospaced))
                .tracking(10)

            Spacer()

            VStack(spacing: 14) {
                Button("Play") { appState.currentPage = .play }
                    .buttonStyle(PrimaryButtonStyle())

                Button("Settings") { appState.currentPage = .settings }
                    .buttonStyle(SecondaryButtonStyle())

                Button("History") { appState.currentPage = .history }
                    .buttonStyle(SecondaryButtonStyle())
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Play Page
struct PlayView: View {
    @EnvironmentObject var appState: AppState

    @State private var deck: [Card] = []
    @State private var board: [ActiveCard] = []
    @State private var selectedCards: [Card] = []

    @State private var isAnimating: Bool = false
    @State private var setsFound: Int = 0
    @State private var timeElapsed: Int = 0
    @State private var timerActive: Bool = false
    @State private var isGameOver: Bool = false
    @State private var showExitAlert: Bool = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 52)

                // Playing Field
                GeometryReader { boardGeo in
                    let boardW = boardGeo.size.width
                    let boardH = boardGeo.size.height

                    let spawnPoint = CGPoint(x: -120, y: boardH / 2)
                    let discardPoint = CGPoint(x: boardW + 120, y: boardH / 2)

                    let paddingH: CGFloat = 16
                    let spacing: CGFloat = 10
                    let cardW = (boardW - (paddingH * 2) - (spacing * 2)) / 3
                    let cardH = cardW / Config.cardAspectRatio

                    // Active cards determine the grid row count
                    let maxSlot = board.filter { !$0.isDeparting }.map { $0.slot }.max() ?? 11
                    let rowCount = max(4, (maxSlot + 1 + 2) / 3)
                    let gridH = CGFloat(rowCount) * cardH + CGFloat(rowCount - 1) * spacing
                    let startY = max(8, (boardH - gridH) / 2)

                    ZStack {
                        ForEach(board) { item in
                            let row = item.slot / 3
                            let col = item.slot % 3
                            let slotX = paddingH + CGFloat(col) * (cardW + spacing) + cardW / 2
                            let slotY = startY + CGFloat(row) * (cardH + spacing) + cardH / 2

                            let offsetToDiscard = CGSize(width: discardPoint.x - slotX, height: discardPoint.y - slotY)
                            let offsetFromSpawn = CGSize(width: spawnPoint.x - slotX, height: spawnPoint.y - slotY)

                            CardView(card: item.card, isSelected: selectedCards.contains(item.card))
                                .frame(width: cardW, height: cardH)
                                .position(x: slotX, y: slotY)
                                .offset(item.isDeparting ? (isAnimating ? offsetToDiscard : .zero) :
                                        item.isEntering ? (isAnimating ? .zero : offsetFromSpawn) : .zero)
                                .opacity(item.isDeparting ? (isAnimating ? 0.0 : 1.0) :
                                         item.isEntering ? (isAnimating ? 1.0 : 0.0) : 1.0)
                                .onTapGesture {
                                    if !item.isDeparting && !item.isEntering {
                                        handleCardTap(item.card)
                                    }
                                }
                        }
                    }
                }

                // Bottom HUD
                HStack {
                    if !appState.focusMode {
                        Text(formatTimer(timeElapsed))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    }
                    Spacer()
                    if !appState.focusMode {
                        Text("Sets: \(setsFound)")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // End Screen Opaque Modal Overlay
            if isGameOver {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Text(Config.endScreenMessage)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)

                        VStack(spacing: 6) {
                            Text("Time: \(formatTimer(timeElapsed))")
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                            Text("Sets Found: \(setsFound)")
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.secondary)

                        Button(Config.playAgainButtonText) {
                            startNewGame()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(28)
                    .frame(maxWidth: 320)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(appState.isDarkMode ? Color(white: 0.16) : Color.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
                    )
                    Spacer()
                }
                .transition(.opacity.animation(.easeInOut(duration: Config.endScreenFadeDuration)))
            }

            // Pinned Top Bar
            HStack {
                Button(action: {
                    if isGameOver {
                        appState.currentPage = .home
                    } else {
                        showExitAlert = true
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(appState.isDarkMode ? Color(white: 0.18) : Color(white: 0.90))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        .alert("Leave Game?", isPresented: $showExitAlert) {
            Button("Leave", role: .destructive) { appState.currentPage = .home }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current progress will be lost.")
                .font(.system(.body, design: .monospaced))
        }
        .onAppear { startNewGame() }
        .onReceive(timer) { _ in
            if timerActive && !isGameOver {
                timeElapsed += 1
            }
        }
    }

    // MARK: - Game Logic
    private func startNewGame() {
        var newDeck: [Card] = []
        for count in Feature.allCases {
            for shape in Feature.allCases {
                for color in Feature.allCases {
                    for shading in Feature.allCases {
                        newDeck.append(Card(count: count, shape: shape, colorIndex: color, shading: shading))
                    }
                }
            }
        }
        deck = newDeck.shuffled()
        board = []
        selectedCards = []
        setsFound = 0
        timeElapsed = 0
        isGameOver = false
        timerActive = true

        dealInitialCards(12)
        ensureSetsAvailable(animated: false)
    }

    private func dealInitialCards(_ amount: Int) {
        let count = min(amount, deck.count)
        guard count > 0 else { return }
        let dealt = Array(deck.prefix(count))
        deck.removeFirst(count)
        board = dealt.enumerated().map { index, card in
            ActiveCard(card: card, slot: index, isEntering: false)
        }
    }

    private func dealAdditionalRow(animated: Bool) {
        let count = min(3, deck.count)
        guard count > 0 else { return }
        let dealt = Array(deck.prefix(count))
        deck.removeFirst(count)

        let startSlot = board.filter { !$0.isDeparting }.count
        let newItems = dealt.enumerated().map { i, card in
            ActiveCard(card: card, slot: startSlot + i, isEntering: animated && appState.animationType == .slide)
        }

        if animated && appState.animationType == .slide {
            board.append(contentsOf: newItems)
            isAnimating = false

            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: Config.slideAnimationDuration)) {
                    isAnimating = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Config.slideAnimationDuration + 0.05) {
                for i in board.indices {
                    board[i].isEntering = false
                }
                isAnimating = false
                ensureSetsAvailable(animated: true)
            }
        } else {
            board.append(contentsOf: newItems)
            ensureSetsAvailable(animated: false)
        }
    }

    private func ensureSetsAvailable(animated: Bool = true) {
        let activeCards = board.filter { !$0.isDeparting }.map { $0.card }
        if findValidSets(on: activeCards).isEmpty && !deck.isEmpty {
            dealAdditionalRow(animated: animated)
        } else if findValidSets(on: activeCards).isEmpty && deck.isEmpty {
            finishGame()
        }
    }

    private func handleCardTap(_ card: Card) {
        guard !isGameOver else { return }

        if let index = selectedCards.firstIndex(of: card) {
            selectedCards.remove(at: index)
            return
        }

        selectedCards.append(card)

        if selectedCards.count == 3 {
            evaluateSelectedCards()
        }
    }

    private func evaluateSelectedCards() {
        let c1 = selectedCards[0]
        let c2 = selectedCards[1]
        let c3 = selectedCards[2]

        if isValidSet(c1, c2, c3) {
            AudioManager.shared.play(filename: Config.correctSoundFilename, volume: appState.sfxVolume)
            setsFound += 1

            let activeCards = board.filter { !$0.isDeparting }
            let shouldShrink = activeCards.count > 12 || deck.isEmpty

            if appState.animationType == .replace {
                if shouldShrink {
                    board.removeAll { selectedCards.contains($0.card) }
                    for i in board.indices {
                        board[i].slot = i
                    }
                } else {
                    for selected in selectedCards {
                        if let index = board.firstIndex(where: { $0.card == selected }), !deck.isEmpty {
                            let currentSlot = board[index].slot
                            board[index] = ActiveCard(card: deck.removeFirst(), slot: currentSlot, isEntering: false)
                        }
                    }
                }
                selectedCards.removeAll()
                ensureSetsAvailable(animated: false)
            } else {
                if !shouldShrink {
                    // Replenishing cards: matched cards depart, new cards arrive at identical slots
                    for selected in selectedCards {
                        if let index = board.firstIndex(where: { $0.card == selected && !$0.isDeparting }) {
                            board[index].isDeparting = true
                            let slot = board[index].slot
                            if !deck.isEmpty {
                                let newCard = ActiveCard(card: deck.removeFirst(), slot: slot, isEntering: true)
                                board.append(newCard)
                            }
                        }
                    }
                    selectedCards.removeAll()
                    isAnimating = false

                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: Config.slideAnimationDuration)) {
                            isAnimating = true
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + Config.slideAnimationDuration + 0.05) {
                        board.removeAll { $0.isDeparting }
                        for i in board.indices {
                            board[i].isEntering = false
                        }
                        isAnimating = false
                        ensureSetsAvailable(animated: true)
                    }
                } else {
                    // Shrinking (End of Game): remaining cards glide smoothly into consolidated slots
                    for selected in selectedCards {
                        if let index = board.firstIndex(where: { $0.card == selected && !$0.isDeparting }) {
                            board[index].isDeparting = true
                        }
                    }
                    selectedCards.removeAll()
                    isAnimating = false

                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: Config.slideAnimationDuration)) {
                            var newSlot = 0
                            for i in board.indices {
                                if !board[i].isDeparting {
                                    board[i].slot = newSlot
                                    newSlot += 1
                                }
                            }
                            isAnimating = true
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + Config.slideAnimationDuration + 0.05) {
                        board.removeAll { $0.isDeparting }
                        isAnimating = false
                        ensureSetsAvailable(animated: true)
                    }
                }
            }
        } else {
            AudioManager.shared.play(filename: Config.incorrectSoundFilename, volume: appState.sfxVolume)
            selectedCards.removeAll()
        }
    }

    private func isValidSet(_ c1: Card, _ c2: Card, _ c3: Card) -> Bool {
        func check(_ a: Feature, _ b: Feature, _ c: Feature) -> Bool {
            (a == b && b == c) || (a != b && b != c && a != c)
        }
        return check(c1.count, c2.count, c3.count) &&
               check(c1.shape, c2.shape, c3.shape) &&
               check(c1.colorIndex, c2.colorIndex, c3.colorIndex) &&
               check(c1.shading, c2.shading, c3.shading)
    }

    private func findValidSets(on cards: [Card]) -> [[Card]] {
        var sets: [[Card]] = []
        guard cards.count >= 3 else { return [] }
        for i in 0..<(cards.count - 2) {
            for j in (i + 1)..<(cards.count - 1) {
                for k in (j + 1)..<cards.count {
                    if isValidSet(cards[i], cards[j], cards[k]) {
                        sets.append([cards[i], cards[j], cards[k]])
                    }
                }
            }
        }
        return sets
    }

    private func finishGame() {
        timerActive = false
        isGameOver = true
        let record = GameRecord(id: UUID(), timeInSeconds: timeElapsed, setsFound: setsFound, date: Date())
        appState.history.append(record)
    }

    private func formatTimer(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Card Component (Rotated 90° with Native Vertical Symbols)
struct CardView: View {
    @EnvironmentObject var appState: AppState
    let card: Card
    let isSelected: Bool

    var body: some View {
        GeometryReader { cardGeo in
            let cardW = cardGeo.size.width
            let cardH = cardGeo.size.height

            let maxH = cardH * Config.symbolHeightRatio
            let maxW = cardW * Config.symbolWidthRatio
            let symbolH = min(maxH, maxW * Config.symbolAspectRatio)
            let symbolW = symbolH / Config.symbolAspectRatio
            let hSpacing = cardW * Config.symbolSpacingRatio

            HStack(spacing: hSpacing) {
                ForEach(0..<card.count.rawValue, id: \.self) { _ in
                    SymbolView(
                        shape: card.shape,
                        shading: card.shading,
                        color: appState.color(for: card.colorIndex)
                    )
                    .frame(width: symbolW, height: symbolH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(appState.isDarkMode ? Color(white: 0.14) : Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue, lineWidth: isSelected ? 3 : 0)
        )
        .shadow(
            color: Color.blue.opacity(isSelected ? 0.9 : 0.0),
            radius: isSelected ? 10 : 0
        )
        .animation(.easeInOut(duration: Config.backlightFadeDuration), value: isSelected)
    }
}

// MARK: - Symbol Rendering
struct SymbolView: View {
    let shape: Feature
    let shading: Feature
    let color: Color

    var body: some View {
        ZStack {
            switch shape {
            case .one:
                renderShading(shape: Diamond(), verticalStripes: false)
            case .two:
                renderShading(shape: Capsule(), verticalStripes: false)
            case .three:
                // Rotates the authentic horizontal squiggle so it stands vertical
                GeometryReader { symGeo in
                    renderShading(shape: Squiggle(), verticalStripes: true)
                        .frame(width: symGeo.size.height, height: symGeo.size.width)
                        .rotationEffect(.degrees(90))
                        .position(x: symGeo.size.width / 2, y: symGeo.size.height / 2)
                }
            }
        }
    }

    @ViewBuilder
    private func renderShading<S: Shape>(shape: S, verticalStripes: Bool) -> some View {
        switch shading {
        case .one:
            shape.fill(color)
        case .two:
            ZStack {
                StripesPattern(color: color, vertical: verticalStripes)
                    .clipShape(shape)
                shape.stroke(color, style: StrokeStyle(lineWidth: Config.outlineThickness, lineCap: .round, lineJoin: .miter))
            }
        case .three:
            shape.stroke(color, style: StrokeStyle(lineWidth: Config.outlineThickness, lineCap: .round, lineJoin: .miter))
        }
    }
}

// MARK: - Striped Texture
struct StripesPattern: View {
    let color: Color
    var vertical: Bool = false

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let step = Config.stripeSpacing
                if vertical {
                    for x in stride(from: 0, through: geo.size.width, by: step) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                } else {
                    for y in stride(from: 0, through: geo.size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
            }
            .stroke(color, lineWidth: 1)
        }
    }
}

// MARK: - Custom Shapes
struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// Authentic Thick SET Squiggle with Inward-Curled Rock Horn Tips
struct Squiggle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Tip 1: Bottom-left hook curled slightly inward
        path.move(to: CGPoint(x: w * 0.10, y: h * 0.88))

        // Left lobe sweeping upward around the big bulb
        path.addCurve(
            to: CGPoint(x: w * 0.28, y: h * 0.04),
            control1: CGPoint(x: w * -0.06, y: h * 0.65),
            control2: CGPoint(x: w * 0.02, y: h * 0.04)
        )

        // Waist dip across the middle (thick body)
        path.addCurve(
            to: CGPoint(x: w * 0.68, y: h * 0.26),
            control1: CGPoint(x: w * 0.44, y: h * 0.04),
            control2: CGPoint(x: w * 0.52, y: h * 0.26)
        )

        // Rises into Tip 2 and hooks slightly inward toward the center
        path.addCurve(
            to: CGPoint(x: w * 0.90, y: h * 0.12),
            control1: CGPoint(x: w * 0.78, y: h * 0.26),
            control2: CGPoint(x: w * 0.95, y: h * 0.04)
        )

        // Right lobe sweeping downward around the big bulb
        path.addCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.96),
            control1: CGPoint(x: w * 1.06, y: h * 0.35),
            control2: CGPoint(x: w * 0.98, y: h * 0.96)
        )

        // Waist hump across the middle (thick body)
        path.addCurve(
            to: CGPoint(x: w * 0.32, y: h * 0.74),
            control1: CGPoint(x: w * 0.56, y: h * 0.96),
            control2: CGPoint(x: w * 0.48, y: h * 0.74)
        )

        // Closes into Tip 1, curling inward
        path.addCurve(
            to: CGPoint(x: w * 0.10, y: h * 0.88),
            control1: CGPoint(x: w * 0.22, y: h * 0.74),
            control2: CGPoint(x: w * 0.05, y: h * 0.96)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Settings Page (Monospaced typography, static layout)
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var activeColorTab: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button(action: { appState.currentPage = .home }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(appState.isDarkMode ? Color(white: 0.18) : Color(white: 0.90))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Settings")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Spacer()
                Color.clear.frame(width: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)

            // Direct content
            VStack(spacing: 20) {
                Toggle("Dark Mode", isOn: $appState.isDarkMode)
                    .toggleStyle(.switch)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))

                Toggle("Focus Mode", isOn: $appState.focusMode)
                    .toggleStyle(.switch)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SFX Volume")
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                        Spacer()
                        Text("\(Int(appState.sfxVolume * 100))%")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, design: .monospaced))
                    }
                    Slider(value: $appState.sfxVolume, in: 0...1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Animation")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                    Picker("", selection: $appState.animationType) {
                        ForEach(AnimationType.allCases) { type in
                            Text(type.rawValue)
                                .font(.system(size: 14, design: .monospaced))
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Color Customizer")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))

                    HStack {
                        Spacer()
                        VStack {
                            SymbolView(shape: .one, shading: .one, color: activeColorBinding.wrappedValue.color)
                                .frame(width: 24, height: 48)
                        }
                        .frame(width: 86, height: 56)
                        .background(appState.isDarkMode ? Color(white: 0.14) : Color.white)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        Spacer()
                    }

                    Picker("", selection: $activeColorTab) {
                        Text("Color 1").tag(1)
                        Text("Color 2").tag(2)
                        Text("Color 3").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    rgbSlider(label: "Red", value: activeColorBinding.r)
                    rgbSlider(label: "Green", value: activeColorBinding.g)
                    rgbSlider(label: "Blue", value: activeColorBinding.b)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var activeColorBinding: Binding<RGBColor> {
        switch activeColorTab {
        case 1: return $appState.color1
        case 2: return $appState.color2
        default: return $appState.color3
        }
    }

    private func rgbSlider(label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(value.wrappedValue * 255))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: 0...1)
        }
    }
}

// MARK: - History Page (Monospaced typography)
struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var sortCriteria: SortCriteria = .newestDate

    var sortedHistory: [GameRecord] {
        switch sortCriteria {
        case .newestDate:
            return appState.history.sorted { $0.date > $1.date }
        case .oldestDate:
            return appState.history.sorted { $0.date < $1.date }
        case .fastestTime:
            return appState.history.sorted { $0.timeInSeconds < $1.timeInSeconds }
        case .slowestTime:
            return appState.history.sorted { $0.timeInSeconds > $1.timeInSeconds }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button(action: { appState.currentPage = .home }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(appState.isDarkMode ? Color(white: 0.18) : Color(white: 0.90))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("History")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Spacer()
                Color.clear.frame(width: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Column Sorting Header
            HStack {
                Button(action: toggleTimeSort) {
                    HStack(spacing: 4) {
                        Text("Time")
                        if sortCriteria == .fastestTime { Image(systemName: "arrow.up") }
                        if sortCriteria == .slowestTime { Image(systemName: "arrow.down") }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Sets")
                    .frame(width: 60, alignment: .center)

                Button(action: toggleDateSort) {
                    HStack(spacing: 4) {
                        Text("Date")
                        if sortCriteria == .newestDate { Image(systemName: "arrow.down") }
                        if sortCriteria == .oldestDate { Image(systemName: "arrow.up") }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            // Records List
            if sortedHistory.isEmpty {
                Spacer()
                Text("No games completed yet")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(sortedHistory) { record in
                            HStack {
                                Text(record.formattedTime)
                                    .font(.system(size: 15, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(record.setsFound)")
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .frame(width: 60, alignment: .center)

                                Text(record.formattedDate)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(appState.isDarkMode ? Color(white: 0.12) : Color.white)
                            .cornerRadius(8)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func toggleTimeSort() {
        sortCriteria = (sortCriteria == .fastestTime) ? .slowestTime : .fastestTime
    }

    private func toggleDateSort() {
        sortCriteria = (sortCriteria == .newestDate) ? .oldestDate : .newestDate
    }
}

// MARK: - Reusable Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue.opacity(configuration.isPressed ? 0.75 : 1.0))
            .cornerRadius(12)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .monospaced))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(configuration.isPressed ? 0.25 : 0.12))
            .cornerRadius(12)
    }
}