import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// ⌘F find bar anchored to the top-trailing corner of the page.
struct FindBar: View {
    @Bindable var window: BrowserWindowModel
    let tab: WebTab
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find on page", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .focused($isFocused)
                .onSubmit { search(backwards: NSEvent.modifierFlags.contains(.shift), restart: false) }
                .onExitCommand(perform: close)
                .accessibilityIdentifier("findField")
            Text(matchLabel)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
            Button { search(backwards: true, restart: false) } label: { Image(systemName: "chevron.up") }
                .disabled(tab.find.matchCount == 0)
            Button { search(backwards: false, restart: false) } label: { Image(systemName: "chevron.down") }
                .disabled(tab.find.matchCount == 0)
            Button("Done", action: close)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .floatingSurface(cornerRadius: 9, material: .popover)
        .onAppear {
            query = tab.find.query
            isFocused = true
        }
        .onChange(of: window.findFocusRequest) { isFocused = true }
        .onChange(of: query) { search(backwards: false, restart: true) }
    }

    private var matchLabel: String {
        guard !query.isEmpty else { return "" }
        guard tab.find.matchCount > 0 else { return "No matches" }
        return "\(tab.find.currentMatch) of \(tab.find.matchCount)"
    }

    private func search(backwards: Bool, restart: Bool) {
        searchTask?.cancel()
        let text = query
        searchTask = Task {
            if restart {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
            await tab.find(text, backwards: backwards)
        }
    }

    private func close() {
        searchTask?.cancel()
        tab.endFind()
        if let webView = tab.webView { window.nsWindow?.makeFirstResponder(webView) }
    }
}

/// Shown instead of the page when navigation failed.
struct FailureView: View {
    let tab: WebTab
    let failure: NavigationFailure

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(isCertificate ? .orange : .secondary)
            Text(title).font(.system(size: 20, weight: .bold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 10) {
                switch failure {
                case .certificate:
                    Button("Go Back") { tab.goBack() }
                        .disabled(!tab.canGoBack)
                    Button("Visit Website Anyway") { tab.proceedDespiteCertificateError() }
                        .help("Your connection to this site will not be private.")
                case .blocked:
                    Button("Go Back") { tab.goBack() }
                        .disabled(!tab.canGoBack)
                default:
                    Button("Try Again") { tab.reload() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("failureView")
    }

    private var isCertificate: Bool {
        if case .certificate = failure {
            true
        } else {
            false
        }
    }

    private var symbol: String {
        switch failure {
        case .certificate: "lock.trianglebadge.exclamationmark"
        case .blocked: "hand.raised"
        case .webContentProcessTerminated: "exclamationmark.triangle"
        case .network: "wifi.exclamationmark"
        }
    }

    private var title: String {
        switch failure {
        case .certificate: "This Connection Is Not Private"
        case .blocked: "Marc Blocked This Page"
        case .webContentProcessTerminated: "This Page Stopped Responding"
        case let .network(_, code, _): code == NSURLErrorNotConnectedToInternet ? "You're Offline" : "Marc Can't Open This Page"
        }
    }

    private var message: String {
        switch failure {
        case let .certificate(_, host, description):
            "\(host) may be impersonating the site you want to visit. Information you enter could be stolen. \(description)"
        case let .blocked(url, reason):
            switch reason {
            case .scriptURL: "JavaScript URLs can't be opened from the address field."
            case .topLevelDataURL: "Pages can't navigate to data URLs."
            case .fileURLFromWebContent: "Web pages can't open files on your Mac."
            case .unsupportedAboutPage: "“\(url.absoluteString)” isn't a page Marc can show."
            case .internalPageFromWebContent: "Web pages can't open Marc's own pages."
            }
        case .webContentProcessTerminated:
            "The page used too much memory or crashed. Reload to try again."
        case let .network(url, _, description):
            "\(description)\(url.map { "\n\($0.displayString)" } ?? "")"
        }
    }
}

/// Camera / microphone request.
struct PermissionPromptView: View {
    let prompt: PermissionPrompt
    @State private var remember = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: prompt.kinds.contains(.camera) ? "video.fill" : "mic.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tint)
                Text("“\(URL(string: prompt.origin)?.displayHost ?? prompt.origin)” wants to use your \(kindsDescription).")
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Remember for this site", isOn: $remember)
                .font(.system(size: 12))
            HStack {
                Spacer()
                Button("Don't Allow") { prompt.respond(false, remember) }
                Button("Allow") { prompt.respond(true, remember) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 330)
        .floatingSurface(material: .popover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permission request")
    }

    private var kindsDescription: String {
        prompt.kinds.map { $0.displayName.lowercased() }.joined(separator: " and ")
    }
}

/// "Save password?" after a login form was submitted.
struct PasswordOfferBanner: View {
    @Bindable var window: BrowserWindowModel
    let offer: PasswordOffer

    private var host: String {
        URL(string: offer.origin)?.displayHost ?? offer.origin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.existing == nil ? "Save password?" : "Update password?")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(offer.username.isEmpty ? "No username" : offer.username) · \(host)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Never for This Site") { window.session?.passwords.neverSave(offer, in: window) }
                Spacer()
                Button("Not Now") { window.passwordOffer = nil }
                Button(offer.existing == nil ? "Save" : "Update") { window.session?.passwords.save(offer, in: window) }
                    .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 360)
        .floatingSurface(material: .popover)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Saved logins offered below a focused login field.
struct AutofillPopover: View {
    @Bindable var window: BrowserWindowModel
    let offer: AutofillOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let suggestion = offer.suggestedPassword {
                Button {
                    window.session?.passwords.fillGenerated(suggestion, offer: offer, in: window)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Use Strong Password", systemImage: "key.viewfinder").font(.system(size: 12, weight: .semibold))
                        Text(suggestion).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(offer.credentials) { credential in
                Button {
                    window.session?.passwords.fill(credential, offer: offer, in: window)
                } label: {
                    Label(credential.username.isEmpty ? "No username" : credential.username, systemImage: "person.crop.circle")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: max(offer.rect.width, 240))
        .floatingSurface(cornerRadius: 9, material: .popover)
        .offset(x: offer.rect.minX, y: offer.rect.maxY + 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transition(.opacity)
    }
}
