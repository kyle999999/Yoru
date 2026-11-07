// SPDX-License-Identifier: GPL-3.0-only
#if targetEnvironment(macCatalyst)
import UIKit
// UIStepper raises an exception in the Mac idiom. Keep the existing settings
// binding using ordinary native Mac buttons instead.
final class MacSettingsStepper: UIControl {
    var minimumValue: Double = 0 { didSet { updateButtons() } }
    var maximumValue: Double = 100 { didSet { updateButtons() } }
    var stepValue: Double = 1
    private var storedValue: Double = 0
    var value: Double {
        get { storedValue }
        set { storedValue = min(max(newValue, minimumValue), maximumValue); updateButtons() }
    }
    var defaultsKey: String? { didSet { value = defaultsKey.map { AidokuStorage.defaults.double(forKey: $0) } ?? 0 } }
    private var handler: ((Double) -> Void)?
    private let minus = UIButton(type: .system)
    private let plus = UIButton(type: .system)
    override var isEnabled: Bool { didSet { updateButtons() } }
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 88, height: 30))
        minus.setImage(UIImage(systemName: "minus"), for: .normal)
        plus.setImage(UIImage(systemName: "plus"), for: .normal)
        minus.accessibilityLabel = "Decrease value"; plus.accessibilityLabel = "Increase value"
        minus.addTarget(self, action: #selector(decrease), for: .touchUpInside)
        plus.addTarget(self, action: #selector(increase), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [minus, plus])
        stack.axis = .horizontal; stack.distribution = .fillEqually; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
        updateButtons()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func handleChange(_ handler: @escaping (Double) -> Void) { self.handler = handler }
    @objc private func decrease() { change(-stepValue) }
    @objc private func increase() { change(stepValue) }
    private func change(_ delta: Double) {
        value += delta
        if let defaultsKey { AidokuStorage.defaults.set(value, forKey: defaultsKey); NotificationCenter.default.post(name: NSNotification.Name(defaultsKey), object: value) }
        handler?(value); sendActions(for: .valueChanged)
    }
    private func updateButtons() { minus.isEnabled = isEnabled && value > minimumValue; plus.isEnabled = isEnabled && value < maximumValue }
}
#endif
