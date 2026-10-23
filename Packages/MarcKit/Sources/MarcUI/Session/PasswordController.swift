import AppKit
import Foundation
import MarcCore
import MarcWebKit
import Observation

/// Connects login forms to the Keychain-backed credential store: offers to save submitted
/// logins and offers saved logins when a login field gets focus. Filling always requires the
/// user to pick a login, and optionally Touch ID.
@Observable
public final class PasswordController {
    @ObservationIgnored weak var session: BrowserSession?
    @ObservationIgnored private let authenticator: any UserAuthenticator
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    init(authenticator: any UserAuthenticator) {
        self.authenticator = authenticator
    }

    func handle(_ event: AutofillEvent, from tab: WebTab, in window: BrowserWindowModel) {
        guard let session, window.kind != .incognito,
              let profileID = tab.context.profileID ?? window.profile?.id,
              let services = session.profileServices(for: profileID)
        else { return }
        let context = OfferContext(tabID: tab.id, profileID: profileID, credentials: services.credentials, window: window)

        switch event {
        case let .submitted(origin, username, password):
            let settings = session.settings.settings
            guard settings.offersToSavePasswords, !settings.neverSavePasswordOrigins.contains(origin) else { return }
            Task { await offerToSave(origin: origin, username: username, password: password, context: context) }
        case let .fieldFocused(_, isNewPassword, rect):
            dismissTask?.cancel()
            guard let url = tab.url, let origin = Credential.origin(for: url) else { return }
            Task { await offerLogins(for: origin, isNewPassword: isNewPassword, rect: rect, context: context) }
        case .fieldBlurred:
            // Give a click on the offer popover time to land before hiding it.
            dismissTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                window.autofillOffer = nil
            }
        case .formsDetected:
            break
        }
    }

    private struct OfferContext {
        let tabID: SidebarItem.ID
        let profileID: Profile.ID
        let credentials: any CredentialStore
        let window: BrowserWindowModel
    }

    /// Offers to save new logins or update changed passwords; unchanged logins are only marked used.
    private func offerToSave(origin: String, username: String, password: String, context: OfferContext) async {
        let saved = await (try? context.credentials.credentials(for: origin)) ?? []
        let match = saved.first { $0.username == username }
        if let match, await (try? context.credentials.password(for: match)) == password {
            try? await context.credentials.markUsed(match, at: .now)
            return
        }
        context.window.passwordOffer = PasswordOffer(
            tabID: context.tabID,
            profileID: context.profileID,
            origin: origin,
            username: username,
            password: password,
            existing: match,
        )
    }

    /// Saved logins for a login field, or a generated password for a new-password field.
    private func offerLogins(for origin: String, isNewPassword: Bool, rect: CGRect, context: OfferContext) async {
        let saved = await isNewPassword ? [] : ((try? context.credentials.credentials(for: origin)) ?? [])
        let suggestion = isNewPassword ? PasswordGenerator().generate() : nil
        guard !saved.isEmpty || suggestion != nil else {
            context.window.autofillOffer = nil
            return
        }
        context.window.autofillOffer = AutofillOffer(
            tabID: context.tabID,
            profileID: context.profileID,
            rect: rect,
            credentials: saved,
            suggestedPassword: suggestion,
        )
    }

    /// Fills a saved login after the user picked it (and authenticated, if required).
    func fill(_ credential: Credential, offer: AutofillOffer, in window: BrowserWindowModel) {
        guard let session, let tab = session.runtime.tab(for: offer.tabID),
              let profile = session.store.workspace.profiles[offer.profileID] else { return }
        let services = session.profileServices(for: profile)
        let requiresAuthentication = session.settings.settings.requiresAuthenticationForPasswords
        window.autofillOffer = nil
        Task {
            if requiresAuthentication {
                guard await authenticator.authenticate(reason: "fill your password for \(credential.origin)") else { return }
            }
            guard let password = try? await services.credentials.password(for: credential),
                  tab.url.flatMap(Credential.origin(for:)) == credential.origin
            else { return }
            tab.fillCredential(username: credential.username, password: password)
            try? await services.credentials.markUsed(credential, at: .now)
        }
    }

    func fillGenerated(_ password: String, offer: AutofillOffer, in window: BrowserWindowModel) {
        guard let tab = session?.runtime.tab(for: offer.tabID) else { return }
        window.autofillOffer = nil
        tab.fillCredential(username: "", password: password, generated: true)
    }

    func save(_ offer: PasswordOffer, in window: BrowserWindowModel) {
        guard let session, let profile = session.store.workspace.profiles[offer.profileID] else { return }
        let credentials = session.profileServices(for: profile).credentials
        window.passwordOffer = nil
        Task {
            var credential = offer.existing ?? Credential(origin: offer.origin, username: offer.username)
            credential.username = offer.username
            credential.lastUsedAt = .now
            do {
                try await credentials.save(credential, password: offer.password)
                window.showToast("Password saved", symbol: "key")
            } catch {
                window.showToast("Could not save the password", symbol: "exclamationmark.triangle")
            }
        }
    }

    func neverSave(_ offer: PasswordOffer, in window: BrowserWindowModel) {
        window.passwordOffer = nil
        session?.settings.settings.neverSavePasswordOrigins.append(offer.origin)
    }
}
