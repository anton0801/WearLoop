//
//  OnboardingView.swift
//  WearLoop
//

import SwiftUI

struct OnboardingView: View {
    @StateObject var presenter: OnboardingPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: "#18070B").ignoresSafeArea()
                CoinOnboardingBackdrop(page: presenter.viewState.index)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    content(heroHeight: min(max(geometry.size.height * 0.24, 90), 340))
                    controls
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { presenter.onAppear() }
    }

    private var header: some View {
        HStack {
            Text("wear loop")
                .font(.system(size: 20, weight: .black))
                .tracking(-1)
                .foregroundStyle(Palette.gold)
                .shadow(color: .black.opacity(0.8), radius: 4)
            Spacer()
            Button("Skip") { presenter.didTapSkip() }
                .buttonStyle(CompactOutlineButtonStyle(stroke: Palette.gold))
                .frame(minHeight: 44)
                .accessibilityHint("Skips the introduction and goes to setup")
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func content(heroHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Flexible artwork space scrolls away on short or landscape screens.
                Color.clear
                    .frame(height: heroHeight)
                    .accessibilityHidden(true)

                if let page = presenter.viewState.current {
                    VStack(alignment: .leading, spacing: 18) {
                        ScreenHeader(page.title)
                            .id(page.id)

                        Text(page.body)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.anchor.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(page.points.enumerated()), id: \.offset) { _, point in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "sparkle")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Palette.burgundy)
                                        .frame(width: 14)
                                        .padding(.top, 4)
                                        .accessibilityHidden(true)
                                    Text(point)
                                        .font(TypeScale.body)
                                        .foregroundStyle(Palette.anchor)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Palette.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Palette.plateFace)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Palette.medallionRim, lineWidth: 2)
                            }
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, 12)
                }
            }
            .animation(Motion.respecting(reduceMotion, Motion.standard), value: presenter.viewState.index)
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(presenter.viewState.pages) { page in
                    Button {
                        presenter.didSelectPage(page.id)
                    } label: {
                        Capsule()
                            .fill(page.id == presenter.viewState.index ? Palette.gold : Color.white.opacity(0.4))
                            .frame(width: page.id == presenter.viewState.index ? 28 : 10, height: 8)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .animation(Motion.respecting(reduceMotion, Motion.segment), value: presenter.viewState.index)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(page.id + 1), \(page.title)")
                    .accessibilityAddTraits(page.id == presenter.viewState.index ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Text(presenter.viewState.progressText)
                    .font(TypeScale.captionSmall)
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.8))
            }

            HStack(spacing: 10) {
                if presenter.viewState.index > 0 {
                    SecondaryButton(title: "Back") { presenter.didTapBack() }
                        .frame(maxWidth: 120)
                }
                PrimaryButton(
                    title: presenter.viewState.isLast ? "Start Setup" : "Continue"
                ) {
                    presenter.didTapNext()
                }
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 16)
        .padding(.top, 4)
        .background {
            Color(hex: "#18070B").opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
