import SwiftUI
import UIKit

/// A code editor made for a phone: line numbers, syntax colors, a row of coding keys
/// above the keyboard, and highlights for the running line and error line.
struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    var activeLine: Int?
    var errorLine: Int?
    var editable: Bool
    /// Characters at the start that can't be edited (the import header).
    var lockedLength: Int = 0
    /// Drone commands to offer on the key row.
    var commands: [String] = []

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CodeTextView {
        let tv = CodeTextView(usingTextLayoutManager: false)
        tv.delegate = context.coordinator
        tv.backgroundColor = UIColor(red: 0.07, green: 0.085, blue: 0.11, alpha: 1)
        tv.font = CodeStyle.font
        tv.textColor = CodeStyle.plain
        tv.tintColor = UIColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1)
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.keyboardType = .asciiCapable
        tv.keyboardAppearance = .dark
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 10, left: CodeTextView.gutter + 6, bottom: 24, right: 8)
        tv.lockedLength = lockedLength
        tv.inputAccessoryView = KeyRow(target: tv, commands: commands, onInsert: { [weak tv, weak coordinator = context.coordinator] in
            guard let tv else { return }
            coordinator?.textViewDidChange(tv)
        })
        tv.text = text
        context.coordinator.highlight(tv)
        return tv
    }

    func updateUIView(_ tv: CodeTextView, context: Context) {
        context.coordinator.parent = self
        tv.lockedLength = lockedLength
        if tv.text != text {
            tv.text = text
        }
        tv.isEditable = editable
        if !editable, tv.isFirstResponder { tv.resignFirstResponder() }
        context.coordinator.highlight(tv)
        if let line = activeLine ?? errorLine, let range = CodeStyle.range(ofLine: line, in: tv.text) {
            tv.scrollRangeToVisible(range)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            if parent.text != tv.text { parent.text = tv.text }
            if tv.markedTextRange == nil { highlight(tv) }
            tv.setNeedsDisplay()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scrollView.setNeedsDisplay()
        }

        /// Auto-indent: keep the current indent on Enter, and add 4 spaces after a colon.
        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText s: String) -> Bool {
            if let ctv = tv as? CodeTextView, !ctv.allowsEdit(at: range) {
                ctv.flashLocked()
                return false
            }
            guard s == "\n" else { return true }
            let ns = tv.text as NSString
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let line = ns.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))
            var indent = String(line.prefix { $0 == " " })
            if line.trimmingCharacters(in: .whitespaces).hasSuffix(":") { indent += "    " }
            tv.insertText("\n" + indent)
            textViewDidChange(tv)
            return false
        }

        func highlight(_ tv: UITextView) {
            let sel = tv.selectedRange
            let offset = tv.contentOffset
            tv.attributedText = CodeStyle.attributed(tv.text, active: parent.activeLine, error: parent.errorLine, locked: parent.lockedLength)
            tv.typingAttributes = CodeStyle.baseAttributes
            tv.selectedRange = sel
            tv.setContentOffset(offset, animated: false)
            tv.setNeedsDisplay()
        }
    }
}

enum CodeStyle {
    static let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    static let plain = UIColor(white: 0.9, alpha: 1)
    static let baseAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: plain]

    private static let rules: [(NSRegularExpression, UIColor)] = {
        func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
        return [
            (rx("\\b(for|while|if|elif|else|def|return|in|range|and|or|not|break|continue|True|False|None)\\b"), UIColor(red: 0.85, green: 0.5, blue: 0.95, alpha: 1)),
            (rx("\\b(move|till|plant|water|harvest|wait)(?=\\s*\\()"), UIColor(red: 0.4, green: 0.75, blue: 1, alpha: 1)),
            (rx("\\b(North|East|South|West|Wheat)\\b"), UIColor(red: 0.98, green: 0.78, blue: 0.3, alpha: 1)),
            (rx("\\b\\d+(\\.\\d+)?\\b"), UIColor(red: 1, green: 0.6, blue: 0.4, alpha: 1)),
            (rx("(\"[^\"\\n]*\"|'[^'\\n]*')"), UIColor(red: 0.6, green: 0.9, blue: 0.5, alpha: 1)),
            (rx("#[^\\n]*"), UIColor(white: 0.45, alpha: 1)),
        ]
    }()

    static func attributed(_ text: String, active: Int?, error: Int?, locked: Int = 0) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: baseAttributes)
        let full = NSRange(location: 0, length: (text as NSString).length)
        if locked > 0 {
            out.addAttribute(.backgroundColor, value: UIColor(red: 0.3, green: 0.5, blue: 1, alpha: 0.08),
                             range: NSRange(location: 0, length: min(locked, full.length)))
        }
        for (rx, color) in rules {
            for m in rx.matches(in: text, range: full) {
                out.addAttribute(.foregroundColor, value: color, range: m.range)
            }
        }
        if let error, let r = range(ofLine: error, in: text) {
            out.addAttribute(.backgroundColor, value: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.28), range: r)
        }
        if let active, let r = range(ofLine: active, in: text) {
            out.addAttribute(.backgroundColor, value: UIColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 0.25), range: r)
        }
        return out
    }

    /// The character range of a 1-based line, without its newline.
    static func range(ofLine line: Int, in text: String) -> NSRange? {
        let ns = text as NSString
        var loc = 0
        var n = 1
        while loc <= ns.length {
            let r = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0))
            if n == line {
                var len = r.length
                if len > 0, NSMaxRange(r) <= ns.length, ns.character(at: NSMaxRange(r) - 1) == 10 { len -= 1 }
                return NSRange(location: r.location, length: len)
            }
            if NSMaxRange(r) >= ns.length { return nil }
            loc = NSMaxRange(r)
            n += 1
        }
        return nil
    }
}

/// UITextView that draws line numbers in a left gutter and keeps the caret above the keyboard.
final class CodeTextView: UITextView {
    static let gutter: CGFloat = 30
    var lockedLength = 0 { didSet { if oldValue != lockedLength { setNeedsDisplay() } } }

    func allowsEdit(at range: NSRange) -> Bool { range.location >= lockedLength }

    /// A quick red pulse on the locked lines when someone tries to type there.
    func flashLocked() {
        let flash = UIView(frame: CGRect(x: 0, y: textContainerInset.top, width: bounds.width, height: lockedHeight()))
        flash.backgroundColor = UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 0.25)
        flash.isUserInteractionEnabled = false
        addSubview(flash)
        UIView.animate(withDuration: 0.5, animations: { flash.alpha = 0 }, completion: { _ in flash.removeFromSuperview() })
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func lockedHeight() -> CGFloat {
        guard lockedLength > 0, lockedLength <= (text as NSString).length else { return 0 }
        let glyph = layoutManager.glyphIndexForCharacter(at: max(0, lockedLength - 1))
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).maxY
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        }
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let window, let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let mine = convert(bounds, to: window)
        let overlap = note.name == UIResponder.keyboardWillHideNotification ? 0 : max(0, mine.maxY - end.minY)
        contentInset.bottom = overlap
        verticalScrollIndicatorInsets.bottom = overlap
        if overlap > 0 { DispatchQueue.main.async { self.scrollRangeToVisible(self.selectedRange) } }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let gutterRect = CGRect(x: 0, y: rect.minY, width: CodeTextView.gutter, height: rect.height)
        ctx.setFillColor(UIColor(red: 0.055, green: 0.067, blue: 0.09, alpha: 1).cgColor)
        ctx.fill(gutterRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor(white: 0.4, alpha: 1),
        ]
        let lm = layoutManager
        lm.ensureLayout(for: textContainer)
        let ns = text as NSString
        var charIndex = 0
        var lineNo = 1
        let lockImage = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .bold))?
            .withTintColor(UIColor(red: 0.45, green: 0.6, blue: 1, alpha: 0.8), renderingMode: .alwaysOriginal)
        func drawNumber(_ y: CGFloat, _ h: CGFloat) {
            let s = "\(lineNo)" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: CodeTextView.gutter - size.width - 4, y: y + (h - size.height) / 2), withAttributes: attrs)
            if charIndex < lockedLength, let lockImage {
                lockImage.draw(at: CGPoint(x: 2, y: y + (h - lockImage.size.height) / 2))
            }
        }
        while charIndex < ns.length {
            let glyph = lm.glyphIndexForCharacter(at: charIndex)
            let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = frag.minY + textContainerInset.top
            if y > rect.maxY { return }
            if y + frag.height >= rect.minY { drawNumber(y, frag.height) }
            charIndex = NSMaxRange(ns.lineRange(for: NSRange(location: charIndex, length: 0)))
            lineNo += 1
        }
        // The empty last line after a final newline (or an empty file).
        if ns.length == 0 || ns.character(at: ns.length - 1) == 10 {
            let extra = lm.extraLineFragmentRect
            if extra.height > 0 { drawNumber(extra.minY + textContainerInset.top, extra.height) }
        }
    }
}

/// The row of coding keys that sits on top of the keyboard.
final class KeyRow: UIInputView {
    private weak var target: UITextView?
    private let onInsert: () -> Void

    private let keys: [(label: String, insert: String)]

    init(target: UITextView, commands: [String], onInsert: @escaping () -> Void) {
        self.target = target
        self.onInsert = onInsert
        var k: [(label: String, insert: String)] = [("⇥", "    "), ("( )", "()"), ("#", "# ")]
        for c in commands {
            if c == "move" {
                k.append(("move(", "move("))
                k += ["North", "East", "South", "West"].map { ($0, $0) }
            } else {
                k.append(("\(c)()", "\(c)()"))
            }
        }
        self.keys = k
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: 46), inputViewStyle: .keyboard)
        allowsSelfSizing = true

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        for (i, key) in keys.enumerated() {
            stack.addArrangedSubview(button(key.label, tag: i))
        }

        let done = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Done"
        cfg.baseBackgroundColor = UIColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1)
        cfg.baseForegroundColor = .black
        cfg.cornerStyle = .medium
        done.configuration = cfg
        done.translatesAutoresizingMaskIntoConstraints = false
        done.addAction(UIAction { [weak self] _ in self?.target?.resignFirstResponder() }, for: .touchUpInside)

        addSubview(scroll)
        addSubview(done)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            done.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            done.centerYAnchor.constraint(equalTo: centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func button(_ title: String, tag: Int) -> UIButton {
        var cfg = UIButton.Configuration.gray()
        cfg.title = title
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .medium
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a
            a.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
            return a
        }
        let b = UIButton(configuration: cfg)
        b.tag = tag
        b.addAction(UIAction { [weak self] _ in self?.tapped(tag) }, for: .touchUpInside)
        return b
    }

    private func tapped(_ i: Int) {
        guard let tv = target else { return }
        let key = keys[i]
        if let ctv = tv as? CodeTextView, !ctv.allowsEdit(at: tv.selectedRange) {
            ctv.flashLocked()
            return
        }
        if key.insert == "()" {
            tv.insertText("()")
            if let pos = tv.position(from: tv.selectedTextRange?.start ?? tv.endOfDocument, offset: -1) {
                tv.selectedTextRange = tv.textRange(from: pos, to: pos)
            }
        } else {
            tv.insertText(key.insert)
        }
        UIDevice.current.playInputClick()
        onInsert()
    }
}
