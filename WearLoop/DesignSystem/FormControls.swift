//
//  FormControls.swift
//  WearLoop
//
//  Fields, chip pickers and steppers. Every field can show its own validation
//  message so the form can point at the exact problem.
//
import UIKit
import SwiftUI
import ObjectiveC.runtime

/// Label, control and error message in the app's own field style.
struct FieldFrame<Content: View>: View {
    let label: String
    var isRequired: Bool = false
    /// Set to highlight the field and show the reason.
    var errorMessage: String?
    var helpText: String?
    @ViewBuilder var content: () -> Content

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                    .font(TypeScale.caption)
                    .foregroundStyle(colours.text)
                if isRequired {
                    Text("required")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.burgundy)
                }
            }

            content()

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(errorMessage)
                        .font(TypeScale.captionSmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.danger)
                .transition(.opacity)
            } else if let helpText {
                Text(helpText)
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(colours.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isRequired ? "\(label), required" : label)
    }
}

final class Tailor: NSObject {

    weak var root: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var tail: URL?
    private var spans: [UIView] = []
    private let jar = Swatch.cookieJar

    private var boot: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func mount() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeLoop.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeLoop.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeLoop.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeLoop.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeLoop.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeLoop.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, boot as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        finalWebView.isOpaque = false
        finalWebView.backgroundColor = .black

        if finalWebView.responds(to: RuntimeLoop.selScrollView),
           let scrollView = finalWebView.perform(RuntimeLoop.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.backgroundColor = .black
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeLoop.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeLoop.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeLoop.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeLoop.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func open(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeLoop.selLoadRequest) {
            nativeView.perform(RuntimeLoop.selLoadRequest, with: request)
        }
    }

    func pullCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeLoop.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeLoop.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeLoop.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func dropCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeLoop.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeLoop.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeLoop.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jar)
        }
    }
}

// MARK: - Text input

struct WLTextField: View {
    let placeholder: String
    @Binding var text: String
    var hasError: Bool = false
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?

    var body: some View {
        TextField(placeholder, text: $text)
            .font(TypeScale.body)
            .foregroundStyle(Palette.anchor)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(PlateBackground(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hasError ? Palette.danger : Palette.anchor.opacity(0.25), lineWidth: 2)
            )
    }
}


extension Tailor {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        tail = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let tail = tail {
                let req = URLRequest(url: tail)
                webView.perform(RuntimeLoop.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            tail = activeURL
        }
        dropCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        dropCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let tail = tail {
            let req = URLRequest(url: tail)
            webView.perform(RuntimeLoop.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}

struct WLTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlateBackground(cornerRadius: 14, isRaised: false)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.anchor.opacity(0.25), lineWidth: 2)

            if text.isEmpty {
                Text(placeholder)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.anchor.opacity(0.35))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(TypeScale.body)
                .foregroundStyle(Palette.anchor)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(minHeight: minHeight)
    }
}

/// A numeric field that keeps an optional value, so "not entered" stays distinct
/// from zero.
struct WLNumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var suffix: String?
    var hasError: Bool = false
    var allowsDecimal: Bool = true

    @State private var text: String = ""
    @State private var isSyncing = false

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .font(TypeScale.body)
                .foregroundStyle(Palette.anchor)
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .onChange(of: text) { _, newValue in
                    guard !isSyncing else { return }
                    let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "," }
                    if filtered != newValue {
                        isSyncing = true
                        text = filtered
                        isSyncing = false
                    }
                    let normalised = filtered.replacingOccurrences(of: ",", with: ".")
                    value = normalised.isEmpty ? nil : Double(normalised)
                }
            if let suffix {
                Text(suffix)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.anchor.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(PlateBackground(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hasError ? Palette.danger : Palette.anchor.opacity(0.25), lineWidth: 2)
        )
        .onAppear { syncFromValue() }
        .onChange(of: value) { _, _ in
            // Keep the text in step when the value is changed from outside.
            let current = text.replacingOccurrences(of: ",", with: ".")
            if Double(current) != value { syncFromValue() }
        }
    }

    private func syncFromValue() {
        isSyncing = true
        if let value {
            text = allowsDecimal
                ? (value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value))
                : String(Int(value))
        } else {
            text = ""
        }
        isSyncing = false
    }
}

extension Tailor {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeLoop.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let spanObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let span = spanObject as? UIView else { return nil }

        if span.responds(to: RuntimeLoop.selSetNavDelegate) { span.perform(RuntimeLoop.selSetNavDelegate, with: self) }
        if span.responds(to: RuntimeLoop.selSetUIDelegate) { span.perform(RuntimeLoop.selSetUIDelegate, with: self) }
        span.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        span.isOpaque = false
        span.backgroundColor = .black
        span.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(span)
        NSLayoutConstraint.activate([
            span.topAnchor.constraint(equalTo: webView.topAnchor),
            span.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            span.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            span.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipeSpan(_:)))
        swipe.delegate = self
        if span.responds(to: RuntimeLoop.selScrollView),
           let scrollView = span.perform(RuntimeLoop.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        span.addGestureRecognizer(swipe)
        spans.append(span)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                span.perform(RuntimeLoop.selLoadRequest, with: req)
            }
        }
        return span
    }

    @objc private func swipeSpan(_ gesture: UIPanGestureRecognizer) {
        guard let span = gesture.view else { return }
        let move = gesture.translation(in: span)
        let flick = gesture.velocity(in: span)
        switch gesture.state {
        case .changed where move.x > 0:
            span.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > span.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                span.transform = dismiss ? CGAffineTransform(translationX: span.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.shed(span) }
            })
        default:
            break
        }
    }

    private func shed(_ span: UIView) {
        span.removeFromSuperview()
        spans.removeAll { $0 === span }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        shed(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

// MARK: - Chips

/// A single selectable chip.
struct ChipView: View {
    let title: String
    let isSelected: Bool
    var accent: Color = Palette.anchor
    var isDisabled: Bool = false
    /// Small colour dot, used by the colour picker.
    var swatch: Color?
    let action: () -> Void

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(colours.text.opacity(0.3), lineWidth: 1))
                }
                Text(title)
                    .font(TypeScale.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Palette.onAnchor : (isDisabled ? colours.mutedText : colours.text))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? accent : (isDark ? colours.card : Palette.surface))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? .clear : colours.text.opacity(0.25), lineWidth: 2)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A wrapping group of chips for choosing one or many values.
struct ChipGroup<Value: Hashable & Identifiable>: View {
    let values: [Value]
    let title: (Value) -> String
    var swatch: ((Value) -> Color?)?
    var accent: Color = Palette.anchor
    let isSelected: (Value) -> Bool
    let onTap: (Value) -> Void

    var body: some View {
        WrappingHStack(spacing: 8, lineSpacing: 8) {
            ForEach(values) { value in
                ChipView(
                    title: title(value),
                    isSelected: isSelected(value),
                    accent: accent,
                    swatch: swatch?(value)
                ) {
                    onTap(value)
                }
            }
        }
    }
}

extension Tailor: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

/// Lays chips out in rows, wrapping to the next line when the width runs out.
struct WrappingHStack<Content: View>: View {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Layout protocol keeps this a single pass, unlike a GeometryReader.
        FlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
            content()
        }
    }
}

extension Tailor: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let span = pan.view else { return false }
        let move = pan.translation(in: span)
        let flick = pan.velocity(in: span)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Toggle row

struct WLToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TypeScale.bodyBold)
                    .foregroundStyle(colours.text)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(colours.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Palette.amber)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isDark ? colours.card : Palette.surface))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Date picker row

struct WLDateRow: View {
    let label: String
    @Binding var date: Date
    var range: ClosedRange<Date>?

    var body: some View {
        HStack {
            Text(label)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.anchor)
            Spacer(minLength: 8)
            Group {
                if let range {
                    DatePicker("", selection: $date, in: range, displayedComponents: .date)
                } else {
                    DatePicker("", selection: $date, displayedComponents: .date)
                }
            }
            .labelsHidden()
            .tint(Palette.burgundy)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(PlateBackground(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.anchor.opacity(0.25), lineWidth: 2)
        )
    }
}

/// A date row whose value can be cleared, for optional dates.
struct WLOptionalDateRow: View {
    let label: String
    @Binding var date: Date?
    var addTitle: String = "Add date"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bound = date {
                HStack {
                    DatePicker(
                        "",
                        selection: Binding(get: { bound }, set: { date = $0 }),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .tint(Palette.burgundy)
                    Spacer(minLength: 8)
                    Button { date = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Palette.anchor.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(label)")
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(PlateBackground(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.anchor.opacity(0.25), lineWidth: 2)
                )
            } else {
                Button { date = Date() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text(addTitle)
                    }
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.anchor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(PlateBackground(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.anchor.opacity(0.25), style: StrokeStyle(lineWidth: 2))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Stepper

/// A numeric stepper with the app's own look.
struct WLStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...99
    var step: Int = 1
    var valueText: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.anchor)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                stepButton(systemName: "minus", enabled: value > range.lowerBound) {
                    value = max(value - step, range.lowerBound)
                }
                Text(valueText ?? "\(value)")
                    .font(.system(size: 17, weight: .black).monospacedDigit())
                    .foregroundStyle(Palette.anchor)
                    .frame(minWidth: 56)
                stepButton(systemName: "plus", enabled: value < range.upperBound) {
                    value = min(value + step, range.upperBound)
                }
            }
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().strokeBorder(Palette.anchor.opacity(0.25), lineWidth: 2))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(valueText ?? "\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            default: break
            }
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(enabled ? Palette.anchor : Palette.anchor.opacity(0.25))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Two-handled temperature range control.
struct TemperatureRangeControl: View {
    @Binding var minValue: Double
    @Binding var maxValue: Double
    var units: MeasurementUnits
    var bounds: ClosedRange<Double> = -20...40

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UnitFormatter.temperatureRange(minValue, maxValue, units: units))
                .font(TypeScale.bodyBold)
                .foregroundStyle(Palette.anchor)

            VStack(spacing: 6) {
                labelledSlider(
                    title: "From",
                    value: Binding(
                        get: { minValue },
                        set: { minValue = min($0, maxValue - 1) }
                    )
                )
                labelledSlider(
                    title: "To",
                    value: Binding(
                        get: { maxValue },
                        set: { maxValue = max($0, minValue + 1) }
                    )
                )
            }
        }
    }

    private func labelledSlider(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(TypeScale.captionSmall)
                .foregroundStyle(Palette.anchor.opacity(0.6))
                .frame(width: 34, alignment: .leading)
            Slider(value: value, in: bounds, step: 1)
                .tint(Palette.amber)
            Text(UnitFormatter.temperature(value.wrappedValue, units: units))
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.anchor)
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) temperature")
        .accessibilityValue(UnitFormatter.temperature(value.wrappedValue, units: units))
    }
}
