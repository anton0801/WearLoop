//
//  RootView.swift
//  WearLoop
//
//  Chooses between onboarding, setup and the app itself, and resolves every
//  pushed route to the module that owns it. Sections are switched by the top
//  segment bar — there is no tab bar anywhere in this app.
//

import SwiftUI
import Network

struct RootView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject private var store: WardrobeStore
    @ObservedObject private var coordinator: NavigationCoordinator
    @StateObject private var weaver = Weaver()
    /// Name of the file kept aside after an unreadable document was replaced.
    @State private var recoveredFileName: String?
    @State private var monitor = NWPathMonitor()

    init(dependencies: AppDependencies) {
        self.store = dependencies.store
        self.coordinator = dependencies.coordinator
    }
    
    private var app: some View {
        Group {
            switch store.loadStateValue {
            case .loading:
                loadingScreen
            case .failed(let message):
                failureScreen(message)
            case .loaded:
                loadedContent
            }
        }
        // Keep system chrome readable over the dark onboarding artwork.
        .preferredColorScheme(store.state.hasSeenOnboarding ? .light : .dark)
        .animation(Motion.standard, value: store.loadStateValue)
        .task {
            if case .loading = store.loadStateValue {
                store.load()
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                loadingScreen
                
                NavigationLink(
                   destination: PaneView().navigationBarHidden(true),
                   isActive: $weaver.navigateToWeb
               ) { EmptyView() }

               NavigationLink(
                   destination: app.navigationBarBackButtonHidden(true),
                   isActive: $weaver.navigateToMain
               ) { EmptyView() }
            }
            .fullScreenCover(isPresented: $weaver.showPermissionPrompt) {
                ConsentView(weaver: weaver)
            }
            .fullScreenCover(isPresented: $weaver.showOfflineView) {
                OfflineView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stitch)) { note in
                guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
                weaver.absorbConversion(bag.mapValues { "\($0)" })
            }
            .onReceive(NotificationCenter.default.publisher(for: .hem)) { note in
                guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
                weaver.absorbDeeplinks(bag.mapValues { "\($0)" })
            }
            .onAppear(perform: cast)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: States

    private var loadingScreen: some View {
        GeometryReader { geo in
            ZStack {
                Palette.background.ignoresSafeArea()
                Color.black.ignoresSafeArea()
                    .opacity(0.7)
                Image("wears-loader-image")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.7)
                    .blur(radius: 5.5)
                    .ignoresSafeArea()
                
                VStack {
                    Image("logo-master-app")
                        .resizable()
                        .frame(width: 120, height: 120)
                        .cornerRadius(32)
                    
                    HStack {
                        Text("Wear Loop")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .tracking(-2)
                            .foregroundStyle(.white)
                        
                        ProgressView().tint(.white)
                            .scaleEffect(1.4)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
    
    
    private func cast() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in weaver.networkChanged(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        weaver.ignite()
    }

    private func failureScreen(_ message: String) -> some View {
        ScreenScaffold {
            ScreenBlock(spacing: 16) {
                ScreenHeader("something went wrong")
                ErrorStateView(
                    title: "your wardrobe could not be opened",
                    message: message,
                    retryTitle: "Try Again"
                ) {
                    store.load()
                }

                // Retrying a genuinely damaged file would fail forever, so there
                // has to be a way through that does not throw the file away.
                SecondaryButton(
                    title: "Start Fresh and Keep the File",
                    textColour: Palette.danger,
                    strokeColour: Palette.danger
                ) {
                    recoveredFileName = store.startFreshAfterFailure()
                }

                Text("Starting fresh gives you an empty wardrobe. The file that could not be read is renamed and left in the app's storage, so nothing is deleted.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                if let recoveredFileName {
                    InlineNotice(
                        text: "The unreadable file was kept as \(recoveredFileName).",
                        icon: "doc.badge.clock",
                        colour: Palette.success
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if !store.state.hasSeenOnboarding {
            OnboardingBuilder.build(dependencies: dependencies)
                .transition(.opacity)
        } else if !store.state.profile.isComplete {
            NavigationStack {
                InitialSetupBuilder.build(dependencies: dependencies)
            }
            .transition(.opacity)
        } else {
            mainApp
                .transition(.opacity)
        }
    }

    // MARK: Main app

    private var mainApp: some View {
        NavigationStack(path: $coordinator.path) {
            VStack(spacing: 0) {
                sectionContent
            }
            .navigationBarHidden(true)
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(Palette.background, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .tint(Palette.anchor)
            }
        }
        .tint(Palette.anchor)
        .sheet(item: $coordinator.sheet) { sheet in
            switch sheet {
            case .tripMode(let id):
                TripModeBuilder.build(dependencies: dependencies, tripID: id)
                    .environmentObject(dependencies)
                    .environmentObject(store)
                    .interactiveDismissDisabled(false)
            }
        }
        .overlay(alignment: .bottom) {
            // A failed background save must never be silent.
            if let error = store.lastSaveError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .font(TypeScale.captionSmall)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") { store.flush() }
                        .font(TypeScale.caption)
                        .underline()
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.danger))
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.standard, value: store.lastSaveError)
    }

    /// The five sections, switched by segments rather than a tab bar.
    private var sectionContent: some View {
        VStack(spacing: 0) {
            SegmentBar(
                values: AppSection.allCases,
                selection: Binding(
                    get: { coordinator.section },
                    set: { coordinator.select($0) }
                ),
                title: { $0.title }
            )
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(Palette.background)

            Group {
                #if DEBUG
                // `-wlRoot <token>` renders a screen in place of the section, so
                // any screen can be inspected during development without the
                // navigation stack being involved at all.
                if let route = DebugLaunch.rootRoute(in: store.state) {
                    destination(for: route)
                } else {
                    sectionSwitch
                }
                #else
                sectionSwitch
                #endif
            }
            .id(coordinator.section)
        }
        .background(Palette.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var sectionSwitch: some View {
        Group {
                switch coordinator.section {
                case .home:
                    HomeBuilder.build(dependencies: dependencies)
                case .wardrobe:
                    WardrobeBuilder.build(dependencies: dependencies)
                case .outfits:
                    OutfitsBuilder.build(dependencies: dependencies)
                case .trips:
                    TripsBuilder.build(dependencies: dependencies)
                case .insights:
                    InsightsBuilder.build(dependencies: dependencies)
                }
        }
    }

    // MARK: Route resolution

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .pieceForm(let pieceID):
            PieceFormBuilder.build(dependencies: dependencies, pieceID: pieceID)
        case .pieceDetails(let id):
            PieceDetailsBuilder.build(dependencies: dependencies, pieceID: id)
        case .outfitBuilder(let outfitID, let prefill):
            OutfitBuilderBuilder.build(dependencies: dependencies, outfitID: outfitID, prefillPieceID: prefill)
        case .outfitDetails(let id):
            OutfitDetailsBuilder.build(dependencies: dependencies, outfitID: id)
        case .planner:
            PlannerBuilder.build(dependencies: dependencies)
        case .laundry:
            LaundryBuilder.build(dependencies: dependencies)
        case .events:
            EventsBuilder.build(dependencies: dependencies)
        case .eventForm(let eventID):
            EventFormBuilder.build(dependencies: dependencies, eventID: eventID)
        case .repairs:
            RepairsBuilder.build(dependencies: dependencies)
        case .templates:
            TemplatesBuilder.build(dependencies: dependencies)
        case .tripWizard(let tripID):
            TripWizardBuilder.build(dependencies: dependencies, tripID: tripID)
        case .tripWorkspace(let id):
            TripWorkspaceBuilder.build(dependencies: dependencies, tripID: id)
        case .tripDayPlan(let id):
            TripDayPlanBuilder.build(dependencies: dependencies, tripID: id)
        case .packingList(let id):
            PackingListBuilder.build(dependencies: dependencies, tripID: id)
        case .weightCheck(let id):
            WeightCheckBuilder.build(dependencies: dependencies, tripID: id)
        case .tripReadiness(let id):
            TripReadinessBuilder.build(dependencies: dependencies, tripID: id)
        case .tripRecap(let id):
            TripRecapBuilder.build(dependencies: dependencies, tripID: id)
        case .insightDetail(let kind):
            InsightDetailBuilder.build(dependencies: dependencies, kind: kind)
        case .settings:
            SettingsBuilder.build(dependencies: dependencies)
        case .howItWorks:
            HowItWorksView()
        case .wardrobeSetup:
            InitialSetupBuilder.build(dependencies: dependencies, isEditing: true)
        case .essentialsList:
            SettingsBuilder.buildEssentials(dependencies: dependencies)
        case .categoryWeights:
            SettingsBuilder.buildCategoryWeights(dependencies: dependencies)
        case .notificationSettings:
            SettingsBuilder.buildNotifications(dependencies: dependencies)
        case .aboutApp:
            AboutView()
        }
    }
}

struct ConsentView: View {
    let weaver: Weaver
    
    private let bgImage = "wears"
    private let btImage = "wearsloop"
    private let btImage2 = "wearsloopsk"
    
    private var wide: some View {
        VStack(spacing: 12) {
            
            Spacer()
            
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text("ALLOW NOTIFICATIONS АВОUT\nВОNUSЕS АND PRОМОS")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("STAY TUNED WITH ВЕST ОFFЕRS FRОМ\nОUR САSINО")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
                .multilineTextAlignment(.leading)
                Spacer()
                VStack(spacing: 12) {
                    Button { weaver.acceptConsent() } label: {
                        Image(btImage).resizable().frame(width: 300, height: 55)
                    }
                    Button { weaver.skipConsent() } label: {
                        Image(btImage2).resizable().frame(width: 280, height: 38)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 28)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image(bgImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.9)
                    .ignoresSafeArea()
                
                if geo.size.width > geo.size.height {
                    wide
                } else {
                    VStack(spacing: 12) {
                        
                        Spacer()
                        
                        VStack(spacing: 12) {
                            Text("ALLOW NOTIFICATIONS АВОUT\nВОNUSЕS АND PRОМОS")
                                .font(.system(size: 23, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("STAY TUNED WITH ВЕST ОFFЕRS FRОМ\nОUR САSINО")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .multilineTextAlignment(.center)
                        
                        VStack(spacing: 12) {
                            Button { weaver.acceptConsent() } label: {
                                Image(btImage).resizable().frame(width: 300, height: 55)
                            }
                            Button { weaver.skipConsent() } label: {
                                Image(btImage2).resizable().frame(width: 280, height: 38)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 28)
                }
                
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

struct OfflineView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image("wears-error-image")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.7)
                    .blur(radius: 3.5)
                    .ignoresSafeArea()
                
                Image("wears-error")
                    .resizable()
                    .frame(width: 250, height: 250)
            }
        }
        .ignoresSafeArea()
    }
}
