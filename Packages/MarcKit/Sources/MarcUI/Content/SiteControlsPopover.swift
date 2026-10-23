import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI
import WebKit

/// Per-site controls: quick actions, permissions, content blocking, zoom and data.
struct SiteControlsPopover: View {
    @Bindable var window: BrowserWindowModel
    let tab: WebTab
    @State private var refresh = 0

    var body: some View {
        let host = tab.url?.host(percentEncoded: false) ?? ""
        let profileID = tab.context.profileID
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                actionButton("square.and.arrow.up", "Share") { window.perform(.share) }
                actionButton("paintbrush.pointed", "Boost") { window.perform(.boostSite) }
                actionButton("printer", "Print") { window.perform(.printPage) }
                actionButton("doc.on.doc", "Copy Link") { window.copyCurrentURL() }
            }

            if tab.context.profileID != nil {
                ExtensionActionsRow(window: window, tab: tab)
            }

            if let session = window.session, let profileID, let services = session.profileServices(for: profileID) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings for \(tab.url?.displayHost ?? host)").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Toggle("Block Ads and Trackers", isOn: Binding(
                        get: { session.sitePreferences.settings(for: host, profileID: profileID).isContentBlockingEnabled ?? true },
                        set: { enabled in
                            var settings = session.sitePreferences.settings(for: host, profileID: profileID)
                            settings.isContentBlockingEnabled = enabled ? nil : false
                            session.sitePreferences.update(settings, profileID: profileID, repository: services.siteData)
                            tab.reload()
                            refresh += 1
                        },
                    ))
                    .disabled(!session.settings.settings.isContentBlockingEnabled)
                    ForEach([SitePermissionKind.camera, .microphone, .autoplay, .externalApps], id: \.self) { kind in
                        permissionRow(kind, host: host, profileID: profileID, session: session, services: services)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
                .id(refresh)
            }

            HStack {
                Text("Zoom").font(.system(size: 12))
                Spacer()
                Button { window.adjustZoom(.out) } label: { Image(systemName: "minus") }
                Text("\(Int((tab.zoom * 100).rounded()))%").font(.system(size: 12).monospacedDigit()).frame(width: 44)
                Button { window.adjustZoom(.in) } label: { Image(systemName: "plus") }
            }
            .buttonStyle(.pressable)

            Divider()

            HStack {
                Label(tab.hasOnlySecureContent ? "Secure" : "Not Secure", systemImage: tab.hasOnlySecureContent ? "lock.fill" : "lock.open")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary))
                Spacer()
                Menu {
                    Button("Clear Cookies and Reload") { window.perform(.clearCookiesAndReload) }
                    Button("Clear Cache and Reload") { window.perform(.clearCacheAndReload) }
                    Button("Forget This Site's Settings") { forgetSite(host: host, profileID: profileID) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private func actionButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(title)
        .accessibilityLabel(title)
    }

    private func permissionRow(
        _ kind: SitePermissionKind,
        host: String,
        profileID: Profile.ID,
        session: BrowserSession,
        services: ProfileServices,
    ) -> some View {
        HStack {
            Text(kind.displayName)
            Spacer()
            Picker(kind.displayName, selection: Binding(
                get: { session.sitePreferences.decision(for: host, kind: kind, profileID: profileID) },
                set: { decision in
                    session.sitePreferences.setDecision(
                        decision,
                        for: host,
                        kind: kind,
                        profileID: profileID,
                        repository: services.siteData,
                    )
                    refresh += 1
                },
            )) {
                Text("Ask").tag(PermissionDecision?.none)
                Text("Allow").tag(PermissionDecision?.some(.allow))
                Text("Deny").tag(PermissionDecision?.some(.deny))
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func forgetSite(host: String, profileID: Profile.ID?) {
        guard let session = window.session, let profileID, let services = session.profileServices(for: profileID) else { return }
        session.sitePreferences.clear(host: host, profileID: profileID, repository: services.siteData)
        tab.setZoom(1)
        refresh += 1
    }
}
