import SwiftUI
import UIKit

/// A request to scroll the editor so a line sits at the top. A new id triggers a new scroll.
struct EditorJump: Equatable {
    let id = UUID()
    let line: Int
}

/// A code editor made for a phone: line numbers, syntax colors, a row of coding keys
/// above the keyboard, and highlights for the running line and error line.
struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    var activeLine: Int?
    var errorLine: Int?
    var editable: Bool
    /// Characters at the start that can't be edited (the locked setup).
    var lockedLength: Int = 0
    /// Most lines the player's own code may have (below the locked part).
    var maxCodeLines: Int = 5000
    /// World commands to offer on the key row.
    var commands: [String] = []
    var jump: EditorJump? = nil
    var fontSize: CGFloat = 13

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CodeTextView {
        let tv = CodeTextView.make()
        tv.delegate = context.coordinator
        tv.backgroundColor = UIColor(red: 0.07, green: 0.085, blue: 0.11, alpha: 1)
        tv.font = CodeStyle.font(fontSize)
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
        tv.alwaysBounceHorizontal = false
        tv.showsHorizontalScrollIndicator = false
        tv.contentInsetAdjustmentBehavior = .never
        tv.layoutManager.allowsNonContiguousLayout = false
        tv.textContainer.widthTracksTextView = true
        tv.textContainer.lineBreakMode = .byWordWrapping
        // Generous bottom room so the last line can always be scrolled up into view.
        tv.textContainerInset = UIEdgeInsets(top: 10, left: CodeTextView.gutter + 6, bottom: 120, right: 8)
        tv.lockedLength = lockedLength
        tv.inputAccessoryView = KeyRow(target: tv, commands: commands, onInsert: { [weak tv, weak coordinator = context.coordinator] in
            guard let tv else { return }
            coordinator?.textViewDidChange(tv)
        })
        tv.text = text
        tv.textChanged()
        context.coordinator.styleAll(tv)
        return tv
    }

    func updateUIView(_ tv: CodeTextView, context: Context) {
        let c = context.coordinator
        let old = c.parent
        c.parent = self
        tv.lockedLength = lockedLength
        if tv.text != text {
            tv.text = text
            tv.textChanged()
            c.styleAll(tv)
        } else if old.fontSize != fontSize || old.lockedLength != lockedLength {
            c.styleAll(tv)
        } else if old.activeLine != activeLine || old.errorLine != errorLine {
            // Only the lines whose highlight changed need restyling.
            for line in Set([old.activeLine, activeLine, old.errorLine, errorLine].compactMap { $0 }) {
                if let r = tv.range(ofLine: line) { c.style(tv, range: r) }
            }
        }
        tv.isEditable = editable
        if !editable, tv.isFirstResponder { tv.resignFirstResponder() }

        if let line = activeLine, line != old.activeLine, let r = tv.range(ofLine: line) {
            tv.scrollRangeToVisible(r)
        } else if let line = errorLine, line != old.errorLine, let r = tv.range(ofLine: line) {
            tv.scrollRangeToVisible(r)
        } else if let jump, jump.id != c.lastJump {
            c.lastJump = jump.id
            // Wait a moment on first show so the text view has its real size.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak tv] in tv?.scroll(toLine: jump.line) }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        var lastJump: UUID?
        private var pendingEdit: NSRange?
        init(_ parent: CodeEditor) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            guard let ctv = tv as? CodeTextView else { return }
            ctv.textChanged()
            if parent.text != tv.text { parent.text = tv.text }
            if tv.markedTextRange == nil {
                let ns = tv.text as NSString
                if let edit = pendingEdit, NSMaxRange(edit) <= ns.length {
                    style(ctv, range: ns.paragraphRange(for: edit))
                } else {
                    styleAll(ctv)
                }
            }
            pendingEdit = nil
            ctv.setNeedsDisplay()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scrollView.setNeedsDisplay()
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText s: String) -> Bool {
            guard let ctv = tv as? CodeTextView else { return true }
            if !ctv.allowsEdit(at: range) {
                ctv.flashLocked()
                return false
            }
            // Line limit for the player's code.
            let added = s.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
            if added > 0 {
                let removed = (tv.text as NSString).substring(with: range).reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
                let codeLines = ctv.lineCount - ctv.lockedLines
                if codeLines + added - removed > parent.maxCodeLines {
                    ctv.flashLimit(parent.maxCodeLines)
                    return false
                }
            }
            // Auto-indent: keep the current indent on Enter, and add 4 spaces after a colon.
            if s == "\n" {
                let ns = tv.text as NSString
                let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let line = ns.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))
                var indent = String(line.prefix { $0 == " " })
                if line.trimmingCharacters(in: .whitespaces).hasSuffix(":") { indent += "    " }
                pendingEdit = NSRange(location: range.location, length: 1 + indent.count)
                tv.insertText("\n" + indent)
                textViewDidChange(tv)
                return false
            }
            pendingEdit = NSRange(location: range.location, length: (s as NSString).length)
            return true
        }

        func styleAll(_ tv: UITextView) {
            style(tv, range: NSRange(location: 0, length: (tv.text as NSString).length))
            tv.typingAttributes = CodeStyle.base(parent.fontSize)
        }

        /// Restyles a range in place (no layout reset, no scroll jump).
        func style(_ tv: UITextView, range: NSRange) {
            let storage = tv.textStorage
            let length = storage.length
            let r = NSIntersectionRange(range, NSRange(location: 0, length: length))
            guard r.length > 0 || length == 0 else { return }
            storage.beginEditing()
            storage.setAttributes(CodeStyle.base(parent.fontSize), range: r)
            let text = storage.string
            for (rx, color) in CodeStyle.rules {
                for m in rx.matches(in: text, range: r) {
                    storage.addAttribute(.foregroundColor, value: color, range: m.range)
                }
            }
            let locked = NSIntersectionRange(r, NSRange(location: 0, length: min(parent.lockedLength, length)))
            if locked.length > 0 {
                storage.addAttribute(.backgroundColor, value: UIColor(red: 0.3, green: 0.5, blue: 1, alpha: 0.08), range: locked)
            }
            if let ctv = tv as? CodeTextView {
                if let e = parent.errorLine, let lr = ctv.range(ofLine: e) {
                    let x = NSIntersectionRange(lr, r)
                    if x.length > 0 { storage.addAttribute(.backgroundColor, value: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.28), range: x) }
                }
                if let a = parent.activeLine, let lr = ctv.range(ofLine: a) {
                    let x = NSIntersectionRange(lr, r)
                    if x.length > 0 { storage.addAttribute(.backgroundColor, value: UIColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 0.25), range: x) }
                }
            }
            storage.endEditing()
            tv.setNeedsDisplay()
        }
    }
}

enum CodeStyle {
    static let plain = UIColor(white: 0.9, alpha: 1)

    static func font(_ size: CGFloat) -> UIFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
    static func base(_ size: CGFloat) -> [NSAttributedString.Key: Any] { [.font: font(size), .foregroundColor: plain] }

    static let rules: [(NSRegularExpression, UIColor)] = {
        func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
        return [
            (rx("\\b(for|while|if|elif|else|def|return|in|and|or|not|is|break|continue|pass|global|True|False|None)\\b"), UIColor(red: 0.85, green: 0.5, blue: 0.95, alpha: 1)),
            (rx("\\b(print|range|len|abs|min|max|int|str|float|list|bool|round)(?=\\s*\\()"), UIColor(red: 0.5, green: 0.85, blue: 0.95, alpha: 1)),
            (rx("\\b(move|till|plant|water|harvest|wait|tick|pick|drop|scan)(?=\\s*\\()"), UIColor(red: 0.4, green: 0.75, blue: 1, alpha: 1)),
            (rx("(?<=\\.)[a-z_]+"), UIColor(red: 0.55, green: 0.85, blue: 0.8, alpha: 1)),
            (rx("\\b(field|drone|stock|tile|GOAL|GROW_TIME|Field|Crop|floor|loader|crate|BAYS|Bay|shipped|Floor)\\b"), UIColor(red: 1, green: 0.55, blue: 0.7, alpha: 1)),
            (rx("\\b(North|East|South|West|Wheat)\\b"), UIColor(red: 0.98, green: 0.78, blue: 0.3, alpha: 1)),
            (rx("\\b\\d+(\\.\\d+)?\\b"), UIColor(red: 1, green: 0.6, blue: 0.4, alpha: 1)),
            (rx("(\"[^\"\\n]*\"|'[^'\\n]*')"), UIColor(red: 0.6, green: 0.9, blue: 0.5, alpha: 1)),
            (rx("#[^\\n]*"), UIColor(white: 0.45, alpha: 1)),
        ]
    }()
}

/// UITextView that draws line numbers in a left gutter, measures its full content height
/// itself (so it can always scroll to the last line), and keeps the caret above the keyboard.
final class CodeTextView: UITextView {
    static let gutter: CGFloat = 36

    /// Builds the text view with a classic TextKit 1 stack through a designated initializer.
    /// (UITextView(usingTextLayoutManager:) skips Swift's property setup in subclasses, which
    /// left lineStarts uninitialized and crashed every level in 0.1.10.)
    static func make() -> CodeTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let tv = CodeTextView(frame: .zero, textContainer: container)
        tv.storageRef = storage
        return tv
    }

    /// The text container only weakly references its layout chain, so keep the storage alive.
    private var storageRef: NSTextStorage?
    var lockedLength = 0 {
        didSet { if oldValue != lockedLength { lockedLines = line(containing: max(0, lockedLength - 1)); setNeedsDisplay() } }
    }
    private(set) var lockedLines = 0
    /// UTF-16 offset where each line starts. Rebuilt on every text change.
    private var lineStarts: [Int] = [0]
    var lineCount: Int { lineStarts.count }

    func allowsEdit(at range: NSRange) -> Bool { range.location >= lockedLength }

    func textChanged() {
        let ns = text as NSString
        var starts = [0]
        starts.reserveCapacity(ns.length / 20 + 1)
        let len = ns.length
        var i = 0
        while i < len {
            if ns.character(at: i) == 10 { starts.append(i + 1) }
            i += 1
        }
        lineStarts = starts
        lockedLines = lockedLength > 0 ? line(containing: lockedLength - 1) : 0
        setNeedsLayout()
    }

    /// 1-based line number of a character offset.
    func line(containing offset: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    /// The character range of a 1-based line, without its newline.
    func range(ofLine line: Int) -> NSRange? {
        guard line >= 1, line <= lineStarts.count else { return nil }
        let start = lineStarts[line - 1]
        let total = (text as NSString).length
        let end = line < lineStarts.count ? lineStarts[line] - 1 : total
        return NSRange(location: start, length: max(0, end - start))
    }

    // MARK: Content size

    override func layoutSubviews() {
        super.layoutSubviews()
        fitContentSize()
    }

    /// Space the keyboard covers at the bottom.
    private var keyboardOverlap: CGFloat = 0

    /// UITextView sometimes under-measures long text and stops scrolling early. Instead of fighting
    /// its content size, measure the text ourselves and add any shortfall as extra bottom inset.
    private func fitContentSize() {
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let extra = layoutManager.extraLineFragmentRect
        let needed = ceil(max(used.maxY, extra.maxY) + textContainerInset.top + textContainerInset.bottom)
        let shortfall = max(0, needed - contentSize.height)
        let bottom = keyboardOverlap + shortfall
        if abs(contentInset.bottom - bottom) > 0.5 {
            contentInset.bottom = bottom
            verticalScrollIndicatorInsets.bottom = keyboardOverlap
        }
    }

    /// Scrolls so that a 1-based line sits at the top of the editor.
    func scroll(toLine line: Int) {
        fitContentSize()
        let minY = -contentInset.top
        guard line > 1, let r = range(ofLine: line) else {
            setContentOffset(CGPoint(x: 0, y: minY), animated: false)
            return
        }
        let y: CGFloat
        if r.location >= (text as NSString).length {
            y = layoutManager.extraLineFragmentRect.minY
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: r.location)
            y = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        }
        let maxY = max(minY, contentSize.height - bounds.height + contentInset.bottom)
        setContentOffset(CGPoint(x: 0, y: min(maxY, max(minY, y + textContainerInset.top - 6))), animated: false)
    }

    // MARK: Feedback

    /// A quick red pulse on the locked lines when someone tries to type there.
    func flashLocked() {
        let flash = UIView(frame: CGRect(x: 0, y: textContainerInset.top, width: bounds.width, height: lockedHeight()))
        flash.backgroundColor = UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 0.25)
        flash.isUserInteractionEnabled = false
        addSubview(flash)
        UIView.animate(withDuration: 0.5, animations: { flash.alpha = 0 }, completion: { _ in flash.removeFromSuperview() })
        if AppSettings.shared.haptics { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }

    func flashLimit(_ limit: Int) {
        let label = UILabel()
        label.text = "  \(limit)-line limit reached  "
        label.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.backgroundColor = UIColor(red: 0.85, green: 0.3, blue: 0.25, alpha: 0.95)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.sizeToFit()
        label.center = CGPoint(x: bounds.midX, y: contentOffset.y + bounds.height / 2)
        addSubview(label)
        UIView.animate(withDuration: 0.4, delay: 1.2, animations: { label.alpha = 0 }, completion: { _ in label.removeFromSuperview() })
        if AppSettings.shared.haptics { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    private func lockedHeight() -> CGFloat {
        guard lockedLength > 0, lockedLength <= (text as NSString).length else { return 0 }
        let glyph = layoutManager.glyphIndexForCharacter(at: max(0, lockedLength - 1))
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).maxY
    }

    // MARK: Keyboard

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
        let hiding = note.name == UIResponder.keyboardWillHideNotification || end.minY >= window.bounds.maxY
        let overlap = hiding ? 0 : max(0, mine.maxY - end.minY)
        keyboardOverlap = overlap
        fitContentSize()
        contentInset.bottom = max(contentInset.bottom, overlap)
        verticalScrollIndicatorInsets.bottom = overlap
        if overlap > 0 { DispatchQueue.main.async { self.scrollRangeToVisible(self.selectedRange) } }
    }

    // MARK: Line numbers

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor(red: 0.055, green: 0.067, blue: 0.09, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: rect.minY, width: CodeTextView.gutter, height: rect.height))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor(white: 0.4, alpha: 1),
        ]
        let lockImage = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 6, weight: .bold))?
            .withTintColor(UIColor(red: 0.45, green: 0.6, blue: 1, alpha: 0.8), renderingMode: .alwaysOriginal)

        let lm = layoutManager
        let ns = text as NSString
        func drawNumber(_ n: Int, _ y: CGFloat, _ h: CGFloat) {
            let s = "\(n)" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: CodeTextView.gutter - size.width - 4, y: y + (h - size.height) / 2), withAttributes: attrs)
            if n <= lockedLines, let lockImage {
                lockImage.draw(at: CGPoint(x: 2, y: y + (h - lockImage.size.height) / 2))
            }
        }

        // Only walk the lines that are on screen.
        if ns.length > 0 {
            let visible = CGRect(x: 0, y: rect.minY - textContainerInset.top, width: bounds.width, height: rect.height)
            let glyphs = lm.glyphRange(forBoundingRect: visible, in: textContainer)
            let firstChar = lm.characterIndexForGlyph(at: min(glyphs.location, max(0, lm.numberOfGlyphs - 1)))
            var n = line(containing: firstChar)
            while n <= lineStarts.count {
                let start = lineStarts[n - 1]
                if start >= ns.length { break }
                let frag = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: start), effectiveRange: nil)
                let y = frag.minY + textContainerInset.top
                if y > rect.maxY { return }
                drawNumber(n, y, frag.height)
                n += 1
            }
        }
        // The empty last line after a final newline (or an empty file).
        if ns.length == 0 || ns.character(at: ns.length - 1) == 10 {
            let extra = lm.extraLineFragmentRect
            if extra.height > 0 { drawNumber(lineStarts.count, extra.minY + textContainerInset.top, extra.height) }
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
        var k: [(label: String, insert: String)] = [("⇥", "    "), ("( )", "()"), (":", ":"), ("=", " = "), ("==", " == "), ("\" \"", "\"\"")]
        for c in commands {
            if c == "move" {
                k.append(("move(", "move("))
                k += ["North", "East", "South", "West"].map { ($0, $0) }
            } else {
                k.append(("\(c)()", "\(c)()"))
            }
        }
        k += [("if", "if "), ("else:", "else:"), ("for", "for i in range("), ("while", "while "), ("def", "def "), ("print(", "print("), ("#", "# ")]
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
        if key.insert == "()" || key.insert == "\"\"" {
            tv.insertText(key.insert)
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
