//
//  Stage6CContrastTests.swift
//  Maths QuestTests
//
//  Stage 6C: everything drawn on the chosen background can be read on every background the shop sells, at every
//  strength, in light and dark mode. Colours are measured as they're seen: the shop colour at its strength over the
//  system's white or black, as every screen draws it.
//

import Foundation
import SwiftUI
import Testing
@testable import Maths_Quest

/// Every background a child can choose: each shop colour at each strength, and the starting colour as old saves wrote
/// it.
private let everyBackground: [ChosenBackground] =
    colours.flatMap { colour in colour.opacities.map { ChosenBackground(hex: colour.hexCode, opacity: $0.opacity) } }
    + [ChosenBackground(hex: "0000FF", opacity: 0.8)]

private let bothSchemes: [ColorScheme] = [.light, .dark]

/// The colour SwiftUI actually draws for `colour`, in sRGB.
private func drawn(_ colour: Color, in colorScheme: ColorScheme = .light, on chosen: ChosenBackground = ChosenBackground()) -> Contrast.RGB {
    var environment = EnvironmentValues()
    environment.colorScheme = colorScheme
    environment.chosenBackground = chosen
    let resolved = colour.resolve(in: environment)
    return Contrast.RGB(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
}

/// The colour SwiftUI draws for one of the readable styles, as a view would get it.
private func drawn(_ style: ReadableOnBackground, on chosen: ChosenBackground, in colorScheme: ColorScheme) -> Contrast.RGB? {
    var environment = EnvironmentValues()
    environment.colorScheme = colorScheme
    environment.chosenBackground = chosen
    let resolved = style.resolve(in: environment).resolve(in: environment)
    guard resolved.opacity > 0 else { return nil }
    return Contrast.RGB(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
}

private func close(_ a: Contrast.RGB, _ b: Contrast.RGB) -> Bool {
    abs(a.red - b.red) < 0.003 && abs(a.green - b.green) < 0.003 && abs(a.blue - b.blue) < 0.003
}

private func name(_ chosen: ChosenBackground, _ scheme: ColorScheme) -> String {
    "\(chosen.hex) \(Int((chosen.opacity * 100).rounded()))% \(scheme)"
}

@Suite("Stage 6C contrast on every background")
struct Stage6CBackgroundContrastTests {
    @Test func thereAreSixtyShopBackgroundsAndTheStartingOne() {
        #expect(everyBackground.count == 61)
        #expect(Set(everyBackground.map { "\(GameSettings.canonicalColourHex($0.hex))@\($0.opacity)" }).count == 60)
    }

    @Test func theFailuresBehindTheFix() {
        // Words and shapes were white on every background. White on the light ones is far below 4.5:1.
        let cyan = ChosenBackground(hex: "#00FFFF", opacity: 0.7).rgb(in: .light)
        let everglow = ChosenBackground(hex: "#FFD700", opacity: 0.7).rgb(in: .light)
        #expect(abs(Contrast.ratio(Contrast.white, cyan) - 1.23) < 0.01)
        #expect(abs(Contrast.ratio(Contrast.white, everglow) - 1.28) < 0.01)

        var failing = 0
        for chosen in everyBackground.dropLast() {
            for scheme in bothSchemes where Contrast.ratio(Contrast.white, chosen.rgb(in: scheme)) < 4.5 {
                failing += 1
            }
        }
        #expect(failing == 70)
    }

    @Test func wordsCanBeReadOnEveryBackground() {
        for chosen in everyBackground {
            for scheme in bothSchemes {
                let behind = chosen.rgb(in: scheme)
                let words = ReadableOnBackground.onBackground.rgb(on: chosen, colorScheme: scheme)!
                #expect(Contrast.ratio(words, behind) >= 4.5, "\(name(chosen, scheme))")
                // Only black or white, and white wherever white could already be read, as it always was.
                #expect(words == Contrast.white || words == Contrast.black)
                if Contrast.ratio(Contrast.white, behind) >= 4.55 {
                    #expect(words == Contrast.white, "\(name(chosen, scheme))")
                }
            }
        }
    }

    @Test func theStartingBlueKeepsItsWhiteWords() {
        for scheme in bothSchemes {
            for hex in ["#0000FF", "0000FF"] {
                let chosen = ChosenBackground(hex: hex, opacity: 0.8)
                #expect(ReadableOnBackground.onBackground.rgb(on: chosen, colorScheme: scheme) == Contrast.white)
            }
        }
    }

    @Test func diagramLinesCanBeSeenOnEveryBackground() {
        for chosen in everyBackground {
            for scheme in bothSchemes {
                let behind = chosen.rgb(in: scheme)
                let lines = ReadableOnBackground.linesOnBackground.rgb(on: chosen, colorScheme: scheme)!
                #expect(Contrast.ratio(lines, behind) >= 3, "\(name(chosen, scheme))")
                if Contrast.ratio(Contrast.black, behind) >= 3.05 {
                    #expect(lines == Contrast.black, "\(name(chosen, scheme))")
                }
            }
        }
    }

    @Test func greenAndRedMessagesCanBeReadOnEveryBackgroundAndStayGreenAndRed() {
        for chosen in everyBackground {
            for scheme in bothSchemes {
                let behind = chosen.rgb(in: scheme)
                let largeGreen = ReadableOnBackground.largeGreenOnBackground.rgb(on: chosen, colorScheme: scheme)!
                let largeRed = ReadableOnBackground.largeRedOnBackground.rgb(on: chosen, colorScheme: scheme)!
                let green = ReadableOnBackground.greenOnBackground.rgb(on: chosen, colorScheme: scheme)!
                #expect(Contrast.ratio(largeGreen, behind) >= 3, "\(name(chosen, scheme))")
                #expect(Contrast.ratio(largeRed, behind) >= 3, "\(name(chosen, scheme))")
                #expect(Contrast.ratio(green, behind) >= 4.5, "\(name(chosen, scheme))")
                // Made darker or lighter, never a different colour.
                #expect(largeGreen.green >= largeGreen.red && largeGreen.green >= largeGreen.blue)
                #expect(green.green >= green.red && green.green >= green.blue)
                #expect(largeRed.red >= largeRed.green && largeRed.red >= largeRed.blue)
            }
        }
    }

    @Test func theRedBarIsOutlinedOnlyWhereItCannotBeSeen() {
        var outlined: [String] = []
        for chosen in everyBackground {
            for scheme in bothSchemes {
                let behind = chosen.rgb(in: scheme)
                let red = Contrast.systemRed.rgb(in: scheme)
                if let outline = ReadableOnBackground.redBarOutline.rgb(on: chosen, colorScheme: scheme) {
                    outlined.append(name(chosen, scheme))
                    #expect(Contrast.ratio(red, behind) < 3.05)
                    #expect(Contrast.ratio(outline, behind) >= 3, "\(name(chosen, scheme))")
                } else {
                    #expect(Contrast.ratio(red, behind) >= 3.05, "\(name(chosen, scheme))")
                }
            }
        }
        // Red on the starting blue in light mode is only 1.94:1, so it's outlined there too. In dark mode it's 3.29:1.
        let startingBlue = ChosenBackground()
        #expect(abs(Contrast.ratio(Contrast.systemRed.light, startingBlue.rgb(in: .light)) - 1.94) < 0.01)
        #expect(outlined.contains("#0000FF 80% light"))
        #expect(!outlined.contains("#0000FF 80% dark"))
        #expect(outlined.contains("#FF0000 100% light"))
    }

    @Test func wheelPickersReadOnEveryBackground() {
        for chosen in everyBackground {
            for scheme in bothSchemes {
                let behind = chosen.rgb(in: scheme)
                let pickerScheme = ColorSchemeForBackground.scheme(for: chosen, in: scheme)
                // A wheel picker's words are black in light mode and white in dark mode.
                let words = pickerScheme == .dark ? Contrast.white : Contrast.black
                #expect(Contrast.ratio(words, behind) >= 4.5, "\(name(chosen, scheme))")
            }
        }
        // The starting blue's pickers are drawn as before: white words, as in dark mode.
        #expect(ColorSchemeForBackground.scheme(for: ChosenBackground(), in: .light) == .dark)
    }

    @Test func volumeEdgesAndLabelsCanBeReadOnTheFacesAndTheBackground() {
        var haloed = 0
        for chosen in everyBackground {
            for scheme in bothSchemes {
                let behind = chosen.rgb(in: scheme)
                let surfaces = VolumeShapeView.labelSurfaces(on: behind)
                let edges = ReadableOnBackground.onBackground.rgb(on: chosen, colorScheme: scheme)!
                // The edges are lines, so they need 3:1 with the background and every face, the front face too.
                let front = Contrast.composite(Contrast.systemGrey, opacity: 0.4, over: behind)
                #expect(Contrast.lowestRatio(edges, on: surfaces + [front]) >= 3, "\(name(chosen, scheme))")

                let labels = VolumeShapeView.labelColours(on: behind)
                if let outline = labels.outline {
                    haloed += 1
                    // Black words in a white outline, or the other way round: the words read on the outline, and
                    // the outline stands out on whatever it crosses.
                    #expect(Contrast.ratio(labels.text, outline) == 21)
                } else {
                    #expect(Contrast.lowestRatio(labels.text, on: surfaces) >= 4.5, "\(name(chosen, scheme))")
                }
            }
        }
        // Only where neither black nor white reaches 4.5:1 on every face.
        #expect(haloed > 0 && haloed < everyBackground.count * 2 / 4)
    }

    @Test func swiftUIDrawsTheColoursWorkedOut() {
        let styles: [ReadableOnBackground] = [
            .onBackground, .linesOnBackground, .largeGreenOnBackground, .largeRedOnBackground, .greenOnBackground,
            .redBarOutline,
        ]
        for chosen in everyBackground {
            for scheme in bothSchemes {
                for style in styles {
                    let expected = style.rgb(on: chosen, colorScheme: scheme)
                    let actual = drawn(style, on: chosen, in: scheme)
                    if let expected, let actual {
                        #expect(close(expected, actual), "\(name(chosen, scheme)) \(style.rule)")
                    } else {
                        #expect(expected == nil && actual == nil, "\(name(chosen, scheme)) \(style.rule)")
                    }
                }
            }
        }
    }

    @Test func theAnswerMessagesOutlineKeepsThemReadable() {
        // "Correct!" is green and every other message red, inside a solid black outline 2 points wide, so the letters
        // are read against the outline, whatever the background. That's 4.5:1 or more, as small words would need too.
        for scheme in bothSchemes {
            let green = drawn(.green, in: scheme)
            let red = drawn(.red, in: scheme)
            #expect(Contrast.ratio(green, Contrast.black) >= 4.5)
            #expect(Contrast.ratio(red, Contrast.black) >= 4.5)
        }
    }
}

@Suite("Stage 6C colours that don't depend on the background")
struct Stage6CFixedColourTests {
    @Test func whiteWordsCanBeReadOnEveryButtonBox() {
        for scheme in bothSchemes {
            for box in [Color.buttonBlue, .buttonRed, .buttonGreen, .buttonGrey] {
                #expect(Contrast.ratio(Contrast.white, drawn(box, in: scheme)) >= 4.5)
            }
        }
    }

    @Test func buttonBoxesKeepTheirColour() {
        // Each is the system colour made only as much darker as it needs to be.
        let pairs: [(Color, Contrast.RGB)] = [
            (.buttonBlue, Contrast.systemBlue.light), (.buttonRed, Contrast.systemRed.light),
            (.buttonGreen, Contrast.systemGreen.light), (.buttonGrey, Contrast.systemGrey),
        ]
        for (box, system) in pairs {
            let colour = drawn(box)
            #expect(Contrast.ratio(Contrast.white, colour) < 4.8)
            #expect(colour.red <= system.red + 0.003 && colour.green <= system.green + 0.003 && colour.blue <= system.blue + 0.003)
        }
        // Before: the system colours themselves, too light for white words.
        #expect(Contrast.ratio(Contrast.white, Contrast.systemGreen.light) < 2.3)
        #expect(Contrast.ratio(Contrast.white, Contrast.systemBlue.light) < 4.5)
        #expect(Contrast.ratio(Contrast.white, Contrast.systemRed.light) < 4.5)
    }

    @Test func answerBoxHintsCanBeReadInLightAndDarkMode() {
        for scheme in bothSchemes {
            #expect(Contrast.ratio(drawn(.placeholderGrey, in: scheme), Contrast.white) >= 4.5)
        }
    }

    @Test func theClocksMarkingsCanBeSeenOnItsWhiteFace() {
        for scheme in bothSchemes {
            // The minute ticks, the numerals and the minute hand.
            #expect(Contrast.ratio(drawn(.gray, in: scheme), Contrast.white) >= 3)
            #expect(Contrast.ratio(drawn(.black, in: scheme), Contrast.white) >= 4.5)
            #expect(Contrast.ratio(drawn(.blue, in: scheme), Contrast.white) >= 3)
        }
        // Before: half-strength grey ticks.
        #expect(Contrast.ratio(Contrast.composite(Contrast.systemGrey, opacity: 0.5, over: Contrast.white), Contrast.white) < 2)
    }
}

@Suite("Stage 6C saved backgrounds", .serialized)
@MainActor
struct Stage6CSavedBackgroundTests {
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        // Each suite leaves a plist in the test app's Preferences folder, so earlier runs' files are swept first.
        if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let folder = library.appendingPathComponent("Preferences")
            for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            where file.hasPrefix("MathsQuestTests.6C.") {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
            }
        }
        let suite = "MathsQuestTests.6C.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func theStartingColourIsTheSameHoweverItWasWritten() {
        let written = ["0000FF", "#0000FF", "#0000ff", "0000ff"]
        for scheme in bothSchemes {
            let seen = written.map { ChosenBackground(hex: $0, opacity: 0.8).rgb(in: scheme) }
            #expect(Set(seen.map { "\($0)" }).count == 1)
            for hex in written {
                let chosen = ChosenBackground(hex: hex, opacity: 0.8)
                #expect(ReadableOnBackground.onBackground.rgb(on: chosen, colorScheme: scheme) == Contrast.white)
                #expect(ColorSchemeForBackground.scheme(for: chosen, in: scheme) == .dark)
            }
        }
    }

    @Test func everySavedSelectionLoadsUnchangedAndReads() throws {
        for colour in colours {
            for option in colour.opacities {
                let defaults = makeDefaults()
                // Written as an older save might have: lower case, no "#", and the starting colour as "0000FF".
                let hex = String(colour.hexCode.dropFirst()).lowercased()
                let json = """
                {"points":40,"totalQuestionsAnswered":3,"sfxvolume":0.2,"username":"Sam","backgroundColourHex":"\(hex)",\
                "backgroundOpacity":\(option.opacity),"unlockedColours":{"0000FF":[0.8],"\(hex)":[\(option.opacity)]}}
                """
                defaults.set(Data(json.utf8), forKey: gameSettingsKey)
                let game = GameData(defaults: defaults)
                #expect(game.backgroundColourHex == colour.hexCode)
                #expect(game.backgroundOpacity == option.opacity)
                #expect(game.isColourSelected(colour.hexCode, opacity: option.opacity))
                #expect(game.isColourUnlocked(colour.hexCode, opacity: option.opacity))
                #expect(game.isColourUnlocked("#0000FF", opacity: 0.8))
                #expect(game.points == 40)

                let chosen = ChosenBackground(hex: game.backgroundColourHex, opacity: game.backgroundOpacity)
                for scheme in bothSchemes {
                    #expect(chosen.rgb(in: scheme) == ChosenBackground(hex: hex, opacity: option.opacity).rgb(in: scheme))
                    let words = try #require(ReadableOnBackground.onBackground.rgb(on: chosen, colorScheme: scheme))
                    #expect(Contrast.ratio(words, chosen.rgb(in: scheme)) >= 4.5)
                }
            }
        }
    }

    @Test func purchasedAndSelectedColoursAreKept() {
        let defaults = makeDefaults()
        let json = """
        {"points":500,"totalQuestionsAnswered":0,"sfxvolume":0.5,"username":"","backgroundColourHex":"#FFD700",\
        "backgroundOpacity":0.7,"unlockedColours":{"#0000FF":[0.8],"#FFD700":[0.7,1.0],"#00FFFF":[0.7]}}
        """
        defaults.set(Data(json.utf8), forKey: gameSettingsKey)
        let saved = defaults.data(forKey: gameSettingsKey)
        let game = GameData(defaults: defaults)
        #expect(game.backgroundColourHex == "#FFD700")
        #expect(game.backgroundOpacity == 0.7)
        #expect(game.unlockedColours == ["#0000FF": [0.8], "#FFD700": [0.7, 1.0], "#00FFFF": [0.7]])
        #expect(game.points == 500)
        // Working out colours from the background never rewrites the save.
        let chosen = ChosenBackground(hex: game.backgroundColourHex, opacity: game.backgroundOpacity)
        _ = ReadableOnBackground.onBackground.rgb(on: chosen, colorScheme: .light)
        #expect(defaults.data(forKey: gameSettingsKey) == saved)
        // Everglow 70% now gets black words.
        #expect(ReadableOnBackground.onBackground.rgb(on: chosen, colorScheme: .light) == Contrast.black)
    }
}

@Suite("Stage 6C shop display")
struct Stage6CShopDisplayTests {
    @Test func theFreeColourSaysFree() {
        #expect(ShopView.priceText(0) == "Free")
        #expect(ShopView.lockedDescription(price: 0) == "Locked, free")
    }

    @Test func everyOtherPriceIsShownAsItsNumber() {
        for colour in colours {
            for option in colour.opacities where option.price > 0 {
                #expect(ShopView.priceText(option.price) == "\(option.price)")
                #expect(ShopView.lockedDescription(price: option.price) == "Locked, \(option.price) points")
            }
        }
    }

    @Test func pricesAreUnchangedAndOnlyBlue80IsFree() {
        let free = colours.flatMap { colour in colour.opacities.filter { $0.price == 0 }.map { (colour.name, $0.opacity) } }
        #expect(free.count == 1)
        #expect(free.first?.0 == "Blue" && free.first?.1 == 0.8)
        for colour in colours {
            let expected = colour.name == "Blue" ? [25, 0, 75, 100] : [25, 50, 75, 100]
            #expect(colour.opacities.map(\.price) == expected)
            #expect(colour.opacities.map(\.opacity) == [0.7, 0.8, 0.9, 1.0])
        }
    }

    @Test @MainActor func aFreeColourStillUnlocksForNothing() {
        let suite = "MathsQuestTests.6C.free.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let game = GameData(defaults: defaults)
        // The starting colour is always unlocked, so buying it costs nothing and changes nothing.
        #expect(game.purchaseColour(hex: "#0000FF", opacity: 0.8, price: 0) == .alreadyUnlocked)
        #expect(game.points == 0)
        defaults.removePersistentDomain(forName: suite)
    }
}
