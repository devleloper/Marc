import AppKit
import MarcCore
import MarcWebKit
import SwiftUI

/// A rich-text note. Text is stored as RTFD; standard formatting commands (⌘B, ⌘I, ⌘U, lists)
/// work through the text view.
struct NoteEditorView: View {
    @Bindable var window: BrowserWindowModel
    let noteID: Note.ID
    @State private var title = ""

    var body: some View {
        let note = window.session?.notes.notes[noteID]
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .bold))
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 8)
                .onSubmit { save(content: nil) }
                .onChange(of: title) { save(content: nil) }
                .accessibilityIdentifier("noteTitle")
            RichTextEditor(initialContent: note?.content ?? Data()) { data in
                save(content: data)
            }
            .padding(.horizontal, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { title = note?.title ?? "" }
    }

    private func save(content: Data?) {
        guard let notes = window.session?.notes, let note = notes.notes[noteID] else { return }
        notes.update(noteID, title: title, content: content ?? note.content)
    }
}

/// `NSTextView` with rich text, links and lists.
struct RichTextEditor: NSViewRepresentable {
    let initialContent: Data
    let onChange: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticDataDetectionEnabled = true
        textView.usesFindBar = true
        textView.usesInspectorBar = false
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.drawsBackground = false
        scrollView.drawsBackground = false
        if !initialContent.isEmpty, let attributed = NSAttributedString(rtfd: initialContent, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        }
        textView.typingAttributes[.font] = NSFont.systemFont(ofSize: 15)
        textView.typingAttributes[.foregroundColor] = NSColor.textColor
        textView.delegate = context.coordinator
        textView.setAccessibilityIdentifier("noteBody")
        return scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (Data) -> Void

        init(onChange: @escaping (Data) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let storage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            if let data = storage.rtfd(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
                onChange(data)
            }
        }
    }
}
