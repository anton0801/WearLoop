//
//  OnboardingView.swift
//  WearLoop
//

import SwiftUI

struct OnboardingView: View {
    @StateObject var presenter: OnboardingPresenter

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                content
                Spacer(minLength: 0)
                controls
            }
        }
        .onAppear { presenter.onAppear() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("wear loop")
                .font(.system(size: 20, weight: .black))
                .tracking(-1)
                .foregroundStyle(Palette.anchor)
            Spacer()
            Button("Skip") { presenter.didTapSkip() }
                .buttonStyle(CompactOutlineButtonStyle())
                .accessibilityHint("Skips the introduction and goes to setup")
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: Page

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if let page = presenter.viewState.current {
                    ScreenHeader(page.title)
                        .id(page.id)

                    Text(page.body)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.anchor.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(page.points.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Palette.amber)
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 6)
                                Text(point)
                                    .font(TypeScale.body)
                                    .foregroundStyle(Palette.anchor)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .fill(Palette.surface)
                            .halftoneBacking(opacity: 0.18, focus: .bottomTrailing, spacing: 30)
                            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    )
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .animation(Motion.standard, value: presenter.viewState.index)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            // Page dots double as a way to jump between pages.
            HStack(spacing: 8) {
                ForEach(presenter.viewState.pages) { page in
                    Button {
                        presenter.didSelectPage(page.id)
                    } label: {
                        Capsule()
                            .fill(page.id == presenter.viewState.index ? Palette.anchor : Palette.anchor.opacity(0.2))
                            .frame(width: page.id == presenter.viewState.index ? 28 : 10, height: 10)
                            .animation(Motion.segment, value: presenter.viewState.index)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(page.id + 1), \(page.title)")
                }
                Spacer()
                Text(presenter.viewState.progressText)
                    .font(TypeScale.captionSmall)
                    .monospacedDigit()
                    .foregroundStyle(Palette.anchor.opacity(0.5))
            }

            HStack(spacing: 10) {
                if presenter.viewState.index > 0 {
                    SecondaryButton(title: "Back") { presenter.didTapBack() }
                        .frame(width: 120)
                }
                PrimaryButton(
                    title: presenter.viewState.isLast ? "Start Setup" : "Continue"
                ) {
                    presenter.didTapNext()
                }
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 20)
        .padding(.top, 16)
    }
}
