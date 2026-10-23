import Foundation
import MarcCore
import WebKit

public extension WKContentWorld {
    /// Marc's own scripts (page observation, autofill, element picking). Page scripts cannot
    /// reach objects or message handlers in this world.
    static let marc = WKContentWorld.world(name: "Marc")
    /// User-authored Boost JavaScript, kept apart from both the page and Marc's scripts.
    static let marcBoosts = WKContentWorld.world(name: "MarcBoosts")
}

enum ScriptResource: String, CaseIterable {
    case pageObserver = "PageObserver"
    case autofill = "Autofill"
    case elementPicker = "ElementPicker"

    private static let cache: [ScriptResource: String] = Dictionary(uniqueKeysWithValues: allCases.map { resource in
        let url = Bundle.module.url(forResource: resource.rawValue, withExtension: "js")
        return (resource, url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
    })

    var source: String {
        Self.cache[self] ?? ""
    }
}

enum ScriptMessageName: String, CaseIterable {
    case page = "marcPage"
    case autofill = "marcAutofill"
    case boost = "marcBoost"
}

/// Breaks the retain cycle between `WKUserContentController` (which retains its handlers) and
/// the tab that handles messages.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

enum BoostScripts {
    /// Scripts injecting a boost's style sheet at document start and its JavaScript at document end.
    static func userScripts(for boosts: [Boost]) -> [WKUserScript] {
        boosts.flatMap { boost -> [WKUserScript] in
            var scripts: [WKUserScript] = []
            let css = boost.styleSheet
            if !css.isEmpty {
                scripts.append(WKUserScript(
                    source: styleInjection(css: css, id: boost.id),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true,
                    in: .marcBoosts,
                ))
            }
            if !boost.customJavaScript.isEmpty {
                scripts.append(WKUserScript(
                    source: boost.customJavaScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true,
                    in: .marcBoosts,
                ))
            }
            return scripts
        }
    }

    /// Re-applies (or removes, for an empty style sheet) a boost's CSS in an already loaded page.
    static func styleInjection(css: String, id: Boost.ID) -> String {
        let literal = jsonStringLiteral(css)
        let elementID = jsonStringLiteral("marc-boost-\(id.rawValue.uuidString)")
        return """
        (() => {
          const id = \(elementID);
          let style = document.getElementById(id);
          if (!style) {
            style = document.createElement("style");
            style.id = id;
            (document.head || document.documentElement).appendChild(style);
          }
          style.textContent = \(literal);
          if (!style.textContent) style.remove();
        })();
        """
    }

    static func jsonStringLiteral(_ string: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [string])) ?? Data("[\"\"]".utf8)
        return String(bytes: data.dropFirst().dropLast(), encoding: .utf8) ?? "\"\""
    }
}
