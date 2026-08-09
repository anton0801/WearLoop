//
//  InfoViews.swift
//  WearLoop
//
//  The two static explanation screens. They are reachable from Home and from
//  Settings, and neither of them is a dead end.
//

import SwiftUI

// MARK: - How it works

struct HowItWorksView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    private struct Step: Identifiable {
        var id: Int
        var title: String
        var body: String
    }

    private let steps: [Step] = [
        Step(
            id: 1,
            title: "wardrobe",
            body: "A piece is entered once with a photograph, its colours, the seasons it suits and the occasions you wear it for. Everything else in the app refers back to it."
        ),
        Step(
            id: 2,
            title: "outfits",
            body: "Pieces are laid out by layer into an outfit. One piece can live in as many outfits as you like, and each outfit carries its own temperature range."
        ),
        Step(
            id: 3,
            title: "plan",
            body: "Assign an outfit to a day or to an event. The app checks it against the weather you entered and the dress code, and says what does not match."
        ),
        Step(
            id: 4,
            title: "trips",
            body: "A trip gets its own days, outfits and packing list. The bag is weighed against your limit and the app names what to leave behind rather than telling you to pack light."
        ),
        Step(
            id: 5,
            title: "wear",
            body: "Nothing is ever counted as worn on its own. You confirm it, and only then does the wearing reach the statistics."
        ),
        Step(
            id: 6,
            title: "wash",
            body: "A piece sent to the wash leaves rotation at once. Its outfits say so and show the return date, and it cannot be packed until it is back."
        ),
        Step(
            id: 7,
            title: "insights",
            body: "After enough real records the app can show what you wear every week, what has sat untouched for a year, and how much one wearing of each piece costs."
        )
    ]

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader(
                    "how it works",
                    subtitle: "A closed loop: piece → outfit → plan → wear → wash → back in rotation."
                )
            }

            ScreenBlock(spacing: 12) {
                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(step.id)")
                                .font(.system(size: 34, weight: .black).monospacedDigit())
                                .foregroundStyle(Palette.amber)
                            SectionHeader(step.title)
                        }
                        Text(step.body)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.anchor.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .fill(Palette.surface)
                    )
                }
            }

            ScreenBlock(spacing: 10) {
                SectionHeader("what it does not do", accent: Palette.berry)
                Panel {
                    bullet("It never marks anything as worn for you.")
                    bullet("It never deletes or retires a piece on its own.")
                    bullet("It never sends your wardrobe anywhere. There is no account, and the only thing that ever leaves the device is a location for a weather lookup.")
                    bullet("It never tints or recolours your photographs — the colour of a garment is data.")
                }
            }

            ScreenBlock(spacing: 10) {
                PrimaryButton(title: "Add a Piece") {
                    dependencies.coordinator.jump(to: .wardrobe, then: .pieceForm(pieceID: nil))
                }
                SecondaryButton(title: "Back") {
                    dependencies.coordinator.pop()
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Palette.berry)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.anchor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("about wear loop", subtitle: "A working wardrobe, kept on your own device.")
            }

            ScreenBlock(spacing: 12) {
                Panel {
                    FactRow(label: "Version", value: versionText)
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Account", value: "None required")
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Network", value: "Weather lookups only")
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Storage", value: "This device only")
                }

                Panel {
                    Text("Your data")
                        .font(TypeScale.bodyBold)
                        .foregroundStyle(Palette.anchor)
                    Text("Everything you enter — pieces, photographs, outfits, trips and records — is written to a single file inside the app's own storage. Nothing is uploaded, shared or analysed elsewhere. Export gives you that file whenever you want it.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.anchor.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Panel {
                    Text("Weather")
                        .font(TypeScale.bodyBold)
                        .foregroundStyle(Palette.anchor)
                    Text("Weather can be typed in by hand, or fetched for the place you are in. Only a location — a coordinate or a city name — leaves the device, never anything about your wardrobe. A fetched reading is used for the day it belongs to, and editing any value makes it yours again.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.anchor.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ScreenBlock {
                SecondaryButton(title: "Back") { dependencies.coordinator.pop() }
            }
        }
    }
}
