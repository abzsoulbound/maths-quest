# Maths Quest

An iPhone and iPad app for practising primary school maths, Years 1 to 6. Each year has three activities. Right answers earn points, and points buy background colours in the shop.

The app was called Maths Mania before it was renamed Maths Quest. Changing the bundle ID would make it a new App Store app, so that still says maths-mania, and so do a few names inside the Xcode project.

## Activities

| Year | Activities |
| --- | --- |
| 1 | Counting, Addition, Subtraction |
| 2 | Multiplication, Division, Shapes |
| 3 | Fractions, Measurement, Time |
| 4 | Decimals, Geometry, Money |
| 5 | Percentages, Statistics, Volume |
| 6 | Algebra, Probability, Ratios |

Questions are generated at random, and some of them are hands-on: measuring with an on-screen ruler, setting the hands on a clock, reading a bar graph. Most activities have a drawing pad for working out.

Six activities (Year 2 Multiplication and Division, Year 4 Geometry, Year 6 Algebra, Probability and Ratios) do more than say right or wrong. A wrong answer gets a hint about the mistake that doesn't give the answer away. A right answer shows the finished number sentence, like 4 × 5 = 20. Skipping a question shows a short worked solution.

## Accessibility

VoiceOver reads the maths as words, so 4 × 5 = 20 is read as "4 times 5 equals 20". Text scales with Dynamic Type, and text colour switches to stay readable on whatever background colour the player picks.

## Ads, purchases and data

Ads come from Google Mobile Ads, marked as child-directed with a General content rating. A full-screen ad can show at most once every three minutes, and only on a menu, never while a question is on screen. Skip Question plays a rewarded ad, but only after the child taps "Watch ad" on a screen that says what they get; saying no leaves them on the question. A one-off Remove Ads purchase (StoreKit 2) turns ads off.

There's no sign-in. Points and settings are saved on the device. The only thing sent anywhere is the text typed into the Feedback screen, which goes to Cloud Firestore. The app needs an internet connection and shows a no-internet screen without one.

## Firebase

[`firebase/firestore.rules`](firebase/firestore.rules) lets the app create a document in `feedbacks` with exactly two fields, `text` (a non-empty string) and `timestamp`. Every other read and write is refused. `GoogleService-Info.plist` is Firebase's client config and ships inside the app anyway, so the rules are what protect the data.

The rules have 34 tests. They run against a local Firestore emulator under a `demo-` project ID, so they can't reach the live project:

```bash
node firebase/tests/firestore-rules.test.mjs
```

This needs Node 18+, Java 11+ and the emulator, which `npx firebase-tools setup:emulators:firestore` downloads.

## Building

You need Xcode 16 or later. The app targets iOS 17.0.

Open `Maths Quest.xcodeproj`. Xcode fetches Firebase and Google Mobile Ads through Swift Package Manager. Then run the Maths Quest scheme on a simulator. The scheme uses `Maths QuestTests/RemoveAds.storekit`, so the Remove Ads purchase works in the simulator without App Store Connect.

## Tests

There are over 600 unit tests (Swift Testing) and 170 UI tests (XCTest). They check the maths behind the questions, scoring, saved progress, ad and purchase behaviour, layout and accessibility. Run them with ⌘U in Xcode, or:

```bash
xcodebuild test -project "Maths Quest.xcodeproj" -scheme "Maths Quest" -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```
