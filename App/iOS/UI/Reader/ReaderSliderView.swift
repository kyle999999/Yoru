// Modernized iOS 26 reader progress control for the GPL Aidoku integration.
// SPDX-License-Identifier: GPL-3.0-only
import UIKit

/// Preserve the reader's original control API while using the current native slider
/// for reliable touch targets, RTL layout, and VoiceOver adjustment.
class ReaderSliderView: UISlider {
    enum SliderDirection { case forward, backward }
    var direction: SliderDirection = .forward {
        didSet { transform = direction == .backward ? CGAffineTransform(scaleX: -1, y: 1) : .identity }
    }
    var currentValue: CGFloat {
        get { CGFloat(value) }
        set { setValue(Float(newValue.isFinite ? min(1, max(0, newValue)) : 0), animated: false) }
    }
    var pageStep: Float = 1
    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumValue = 0; maximumValue = 1
        accessibilityLabel = "Reading progress"
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    func move(toValue value: CGFloat) { currentValue = value }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        sendActions(for: .editingDidEnd)
    }
    override func accessibilityIncrement() {
        value = min(maximumValue, value + pageStep)
        sendActions(for: [.valueChanged, .editingDidEnd])
    }
    override func accessibilityDecrement() {
        value = max(minimumValue, value - pageStep)
        sendActions(for: [.valueChanged, .editingDidEnd])
    }
}
