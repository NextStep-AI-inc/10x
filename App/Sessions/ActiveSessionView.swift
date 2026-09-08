import SwiftUI

enum FlyerOverlayLayoutEvent {
    case stackFrame(CGRect)
    case transcriptFrame(CGRect)
    case clearanceFrame(CGRect)
    case jumpFrame(CGRect)
}

private struct FlyerOverlayLayoutObserverKey: EnvironmentKey {
    static let defaultValue: (@MainActor (FlyerOverlayLayoutEvent) -> Void)? = nil
}

extension EnvironmentValues {
    var flyerOverlayLayoutObserver: (@MainActor (FlyerOverlayLayoutEvent) -> Void)? {
        get { self[FlyerOverlayLayoutObserverKey.self] }
        set { self[FlyerOverlayLayoutObserverKey.self] = newValue }
    }
}

struct ActiveSessionView: View {
    let controller: SessionController
    var controls: ComposerControlsModel?
    var commands: ComposerCommandModel?
    var onReviewPrompt: (() -> Void)? = nil
    var sessionMapModel: SessionMapPaneModel?
    var sessionMapPresentation: SessionMapPanePresentation?
    var isSessionMapVisible = false
    var onToggleSessionMap: (() -> Void)?
    var onResizeSessionMap: ((CGFloat) -> Void)?
    var flyerCenter: FlyerCenter?
    var flyerSessionKey: String?
    var onFlyerAction: ((Flyer.Key, String) -> Void)?
    var onFlyerDismiss: ((Flyer.Key) -> Void)?

    @State private var flyout: ComposerFlyout?
    @State private var mapToggleFocusRequest = 0
    @State private var paneWidthAtDragStart: CGFloat?
    @State private var flyerStackHeight: CGFloat = 0
    @State private var flyerDate = Date()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.flyerOverlayLayoutObserver) private var flyerOverlayLayoutObserver

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                conversation
                if isSessionMapVisible,
                   let sessionMapModel,
                   let sessionMapPresentation,
                   case .drawer = sessionMapPresentation {
                    sessionMapPane(sessionMapModel)
                }
            }
            if isSessionMapVisible,
               let sessionMapModel,
               let sessionMapPresentation,
               case .docked = sessionMapPresentation {
                paneDivider
                sessionMapPane(sessionMapModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // This view keeps its identity across session switches, so the shelf
        // would otherwise stay open over a transcript it no longer belongs to.
        .onChange(of: controller.id) { _, _ in flyout = nil }
        .onChange(of: isSessionMapVisible) { wasVisible, isVisible in
            if wasVisible && !isVisible { mapToggleFocusRequest &+= 1 }
        }
        .environment(\.fileReferenceBaseURL, controller.projectURL)
        .sheet(isPresented: logBinding) {
            ScrollView {
                Text(controller.logText)
                    .font(TenXTypography.mono(size: 11))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .frame(minWidth: 620, minHeight: 360)
        }
        .onExitCommand { flyout = nil }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            SessionHeaderView(
                controller: controller,
                isMapVisible: isSessionMapVisible,
                mapToggleFocusRequest: mapToggleFocusRequest,
                onToggleMap: onToggleSessionMap)

            transcriptWithFlyers

            if controller.isRecoveryPresented,
               case .stopped(let code, _) = controller.runtimeState {
                RuntimeRecoveryView(
                    exitCode: code,
                    onRestart: { Task { await controller.restart() } },
                    onOpenLog: controller.openLog,
                    onDismiss: controller.dismissRecovery)
                .frame(maxWidth: 780)
                .padding(.horizontal, 42)
                .padding(.bottom, 16)
            }

            if controller.sessionPath == nil, case .stopped = controller.runtimeState,
               !controller.draft.isEmpty, let onReviewPrompt {
                Button("Review stopped prompt", action: onReviewPrompt)
                    .buttonStyle(GhostActionStyle())
                    .padding(.bottom, 12)
            }

            if controller.isRecoveryPresented, case .failed = controller.runtimeState {
                RuntimeRecoveryView(exitCode: nil,
                    onRestart: { Task { await controller.restart() } },
                    onOpenLog: controller.openLog, onDismiss: controller.dismissRecovery,
                    failureDescription: controller.sessionPath == nil
                        ? "The session could not start. Review your preserved prompt before trying again."
                        : "The session command could not finish. Check the log before retrying; delivery may be unconfirmed.",
                    canRestart: controller.sessionPath != nil,
                    onReviewPrompt: controller.sessionPath == nil ? onReviewPrompt : nil)
                    .frame(maxWidth: 780)
                    .padding(.horizontal, 42)
                    .padding(.bottom, 16)
            }

            ComposerView(
                draft: Bindable(controller).draft,
                attachments: Bindable(controller).attachments,
                flyout: $flyout,
                presentation: .active(controller: controller),
                controls: controls,
                commands: commands,
                controlsMode: .activeSession,
                onSend: {
                    Task { await controller.sendPrompt() }
                })
            .frame(maxWidth: 780)
            .padding(.horizontal, 42)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptWithFlyers: some View {
        let flyers = flyerCenter?.visible(sessionKey: flyerSessionKey, at: flyerDate) ?? []
        let nextExpiration = flyerCenter?.nextExpiration(
            sessionKey: flyerSessionKey,
            after: flyerDate)
        return TranscriptView(
            controller: controller,
            bottomOverlayClearance: flyers.isEmpty ? 0 : flyerStackHeight)
            .id(controller.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if !flyers.isEmpty {
                    FlyerStackView(
                        flyers: flyers,
                        onAction: { key, actionID in onFlyerAction?(key, actionID) },
                        onDismiss: { key in onFlyerDismiss?(key) },
                        onHeightChange: { flyerStackHeight = $0 })
                        .frame(maxWidth: 780)
                        .onGeometryChange(for: CGRect.self) { geometry in
                            geometry.frame(in: .global)
                        } action: { frame in
                            flyerOverlayLayoutObserver?(.stackFrame(frame))
                        }
                        .padding(.horizontal, 42)
                }
            }
            .task(id: FlyerExpirySchedule(
                sessionKey: flyerSessionKey,
                expiration: nextExpiration,
                isActive: scenePhase == .active)) {
                guard scenePhase == .active, let nextExpiration else { return }
                let delay = max(0, nextExpiration.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                flyerCenter?.expire(at: Date())
                flyerDate = Date()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let date = Date()
                flyerCenter?.expire(at: date)
                flyerDate = date
            }
            .onChange(of: flyerSessionKey) { _, _ in
                flyerDate = Date()
            }
    }

    private func sessionMapPane(_ model: SessionMapPaneModel) -> some View {
        SessionMapPaneView(model: model, activity: model.activity)
            .focusable()
            .onExitCommand { model.close() }
    }

    private var paneDivider: some View {
        Rectangle()
            .fill(TenXPalette.color(TenXPalette.separatorHex))
            .frame(width: 1)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let sessionMapPresentation, let onResizeSessionMap else { return }
                    if paneWidthAtDragStart == nil {
                        paneWidthAtDragStart = sessionMapPresentation.width
                    }
                    guard let paneWidthAtDragStart else { return }
                    onResizeSessionMap(paneWidthAtDragStart - value.translation.width)
                }
                .onEnded { _ in paneWidthAtDragStart = nil })
            .accessibilityElement()
            .accessibilityLabel("Resize session map")
            .accessibilityValue("\(Int(sessionMapPresentation?.width ?? 0)) points")
            .accessibilityAdjustableAction { direction in
                guard let sessionMapPresentation, let onResizeSessionMap else { return }
                switch direction {
                case .increment:
                    onResizeSessionMap(sessionMapPresentation.width + 20)
                case .decrement:
                    onResizeSessionMap(sessionMapPresentation.width - 20)
                @unknown default:
                    break
                }
            }
    }

    private var logBinding: Binding<Bool> {
        Binding(
            get: { controller.isLogPresented },
            set: { isPresented in
                if !isPresented { controller.dismissLog() }
            })
    }
}

private struct FlyerExpirySchedule: Equatable {
    let sessionKey: String?
    let expiration: Date?
    let isActive: Bool
}
