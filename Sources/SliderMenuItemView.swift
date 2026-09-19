//
//  SliderMenuItemView.swift
//  Labelled slider embedded in a menu item.
//

import AppKit

final class SliderMenuItemView: NSView {
    private let preferredWidth: CGFloat
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private let titleField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 0.0, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let stackView = NSStackView()
    private let headerRow = NSStackView()

    var formatter: (Double) -> String = { String(format: "%.2f", $0) }
    var onChange: ((Double) -> Void)?
    var horizontalOffset: CGFloat = 12.0 {
        didSet {
            leadingConstraint?.constant = horizontalOffset
            trailingConstraint?.constant = -(16.0 - horizontalOffset)
            needsLayout = true
        }
    }

    init(title: String, minValue: Double, maxValue: Double, initialValue: Double, width: CGFloat = 220.0) {
        self.preferredWidth = width
        super.init(frame: NSRect(x: 0.0, y: 0.0, width: width, height: 44.0))
        titleField.stringValue = title
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = initialValue
        setupView(width: width)
        updateValueLabel()
    }

    required init?(coder: NSCoder) {
        self.preferredWidth = 220.0
        super.init(coder: coder)
        setupView(width: 220.0)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 44.0)
    }

    override var fittingSize: NSSize {
        intrinsicContentSize
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: preferredWidth, height: 44.0))
    }

    var doubleValue: Double {
        get { slider.doubleValue }
        set {
            slider.doubleValue = newValue
            updateValueLabel()
        }
    }

    private func setupView(width: CGFloat) {
        frame.size.width = width

        titleField.font = .systemFont(ofSize: 11.0, weight: .medium)
        titleField.textColor = NSColor.labelColor

        valueField.font = .monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
        valueField.textColor = NSColor.secondaryLabelColor
        valueField.alignment = .right
        valueField.setContentHuggingPriority(.required, for: .horizontal)

        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.distribution = .fill
        headerRow.spacing = 10.0
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(titleField)
        headerRow.addArrangedSubview(valueField)

        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 4.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(headerRow)
        stackView.addArrangedSubview(slider)

        addSubview(stackView)

        leadingConstraint = stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalOffset)
        trailingConstraint = stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(16.0 - horizontalOffset))

        NSLayoutConstraint.activate([
            leadingConstraint!,
            trailingConstraint!,
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 2.0),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2.0),
            headerRow.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            slider.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    private func updateValueLabel() {
        valueField.stringValue = formatter(slider.doubleValue)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        updateValueLabel()
        onChange?(sender.doubleValue)
    }
}
