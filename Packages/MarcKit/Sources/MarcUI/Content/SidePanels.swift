import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// Summary and questions about the current page.
struct AssistantPanel: View {
    @Bindable var window: BrowserWindowModel
    @Bindable var assistant: AssistantModel
    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Mode", selection: $assistant.mode) {
                    Text("Summary").tag(AssistantModel.Mode.summary)
                    Text("Ask").tag(AssistantModel.Mode.ask)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button { window.assistant?.cancel()
                    window.assistant = nil
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close")
            }
            if let provider = assistant.providerName {
                Text("Using \(provider)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch assistant.mode {
                    case .summary:
                        if assistant.summary.isEmpty, assistant.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        MarkdownText(assistant.summary)
                        if !assistant.isRunning {
                            Button(assistant.summary.isEmpty ? "Summarize" : "Summarize Again") { assistant.summarize() }
                        }
                    case .ask:
                        ForEach(assistant.exchanges) { exchange in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(exchange.question).font(.system(size: 13, weight: .semibold))
                                if exchange.answer.isEmpty, assistant.isRunning {
                                    ProgressView().controlSize(.small)
                                }
                                MarkdownText(exchange.answer)
                            }
                        }
                    }
                    if assistant.wasTruncated {
                        Label("The page is long; only its first part was used.", systemImage: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let error = assistant.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if assistant.mode == .ask {
                HStack {
                    TextField("Ask about this page…", text: $assistant.draftQuestion, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1 ... 4)
                        .focused($questionFocused)
                        .onSubmit { assistant.ask() }
                    Button { assistant.ask() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)) }
                        .buttonStyle(.borderless)
                        .disabled(assistant.draftQuestion.trimmingCharacters(in: .whitespaces).isEmpty || assistant.isRunning)
                }
                .focusOnAppear($questionFocused)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Content.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page assistant")
    }
}

/// Renders streamed Markdown, falling back to plain text while it is incomplete.
struct MarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
            .font(.system(size: 13))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Boost editor for the current site.
struct BoostEditorPanel: View {
    @Bindable var window: BrowserWindowModel
    @Bindable var editor: BoostEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "paintbrush.pointed.fill").foregroundStyle(.tint)
                Text("Boost").font(.system(size: 15, weight: .bold))
                Spacer()
                Button { editor.discard() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            .padding(14)
            Form {
                Section {
                    TextField("Name", text: $editor.boost.name)
                    TextField("Site", text: $editor.boost.hostPattern)
                        .help("A host such as example.com, or *.example.com to include subdomains")
                    Toggle("Enabled", isOn: $editor.boost.isEnabled)
                }
                Section("Colors") {
                    LabeledContent("Hue") {
                        Slider(
                            value: Binding(
                                get: { editor.boost.style.hueRotation ?? 0 },
                                set: { editor.boost.style.hueRotation = $0 == 0 ? nil : $0 },
                            ),
                            in: -180 ... 180,
                        )
                    }
                    LabeledContent("Saturation") { Slider(value: $editor.boost.style.saturation, in: 0 ... 2) }
                    LabeledContent("Brightness") { Slider(value: $editor.boost.style.brightness, in: 0.5 ... 1.5) }
                    Toggle("Invert Colors", isOn: $editor.boost.style.invertsColors)
                }
                Section("Text") {
                    Picker(
                        "Font",
                        selection: Binding(
                            get: { editor.boost.style.fontFamily ?? "" },
                            set: { editor.boost.style.fontFamily = $0.isEmpty ? nil : $0 },
                        ),
                    ) {
                        Text("Site Default").tag("")
                        ForEach(Self.fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    LabeledContent("Size") { Slider(value: $editor.boost.style.fontScale, in: 0.75 ... 1.5) }
                }
                Section("Zap") {
                    Button(editor.isPicking ? "Stop Zapping" : "Zap Elements…") {
                        editor.isPicking ? editor.stopPicking() : editor.startPicking()
                    }
                    ForEach(editor.boost.zappedSelectors, id: \.self) { selector in
                        HStack {
                            Text(selector).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { editor.removeZappedSelector(selector) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                Section("Custom CSS") {
                    TextEditor(text: $editor.boost.customCSS)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minHeight: 80)
                }
                Section("Custom JavaScript") {
                    TextEditor(text: $editor.boost.customJavaScript)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minHeight: 80)
                    Text("Runs in an isolated world after the page loads.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !editor.isNew {
                    Button("Delete", role: .destructive) { editor.delete() }
                }
                Spacer()
                Button("Cancel") { editor.discard() }
                Button("Save") { editor.save() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Content.cornerRadius, style: .continuous))
    }

    private static let fontFamilies: [String] = {
        let preferred = [
            "Avenir Next",
            "Charter",
            "Georgia",
            "Helvetica Neue",
            "Iowan Old Style",
            "Menlo",
            "New York",
            "Palatino",
            "SF Pro",
            "Times New Roman",
        ]
        let available = Set(NSFontManager.shared.availableFontFamilies)
        return preferred.filter(available.contains) + NSFontManager.shared.availableFontFamilies
            .filter { !preferred.contains($0) && !$0.hasPrefix(".") }.prefix(60)
    }()
}

/// Read-only source viewer.
struct SourceViewerSheet: View {
    let model: SourceViewerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(model.title.isEmpty ? "Page Source" : model.title).font(.system(size: 13, weight: .semibold))
                    Text(model.url?.absoluteString ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.source, forType: .string)
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(model.source)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
