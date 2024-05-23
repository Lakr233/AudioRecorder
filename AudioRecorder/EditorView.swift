//
//  EditorView.swift
//  AudioRecorder
//
//  Created by Harshad Dange on 19/07/2014.
//  Copyright (c) 2014 Laughing Buddha Software. All rights reserved.
//

import Cocoa
import QuartzCore

// MARK: EditorViewDelegate

protocol EditorViewDelegate {
    func timeRangeChanged(editor: EditorView, timeRange: (start: TimeInterval, end: TimeInterval))
}

class EditorView: NSView {
    // MARK: Defined types

    enum DragState: Int {
        case Started
        case DraggingFromLeft, DraggingFromRight
        case Ended
    }

    struct LevelGroup {
        let levels: [Float]
        var average: Float {
            var total: Float = 0.0
            for level in levels {
                total += level
            }
            return total / Float(levels.count)
        }

        init(levels withLevels: [Float]) {
            levels = withLevels
        }
    }

    // MARK: Properties

    var minimumPower: Float = 0
    var maximumPower: Float = 160.0
    var canvasWidth: CGFloat = 1.0
    var levelGroups: [LevelGroup] = []
    var levelOffset: Float = 0
    var trimView: NSView?
    var dragState = DragState.Ended
    var previousPoint = NSZeroPoint
    var duration: TimeInterval = 0.0
    var delegate: EditorViewDelegate?

    var firstBandX: CGFloat {
        CGRectGetMidX(bounds) - CGFloat(canvasWidth / 2)
    }

    var canvasRect: CGRect {
        CGRectMake(firstBandX, 0.0, canvasWidth, bounds.size.height)
    }

    var timeScale: Float {
        Float(CGFloat(duration) / canvasWidth)
    }

    // MARK: properties

    var audioLevels: [Float] = [] {
        didSet {
            let totalLevels = audioLevels.count
            let sortedLevels = audioLevels.sorted { $0 < $1 }

            if let min = sortedLevels.firstObject() {
                if min < 0 {
                    levelOffset = 0 - min
                    minimumPower = 0
                } else {
                    minimumPower = min
                }
            }
            if let max = sortedLevels.lastObject() {
                maximumPower = max + levelOffset
            }
            var groups: [LevelGroup] = []
            if totalLevels < Int(bounds.size.width) {
                for audioLevel in audioLevels {
                    let group = LevelGroup(levels: [audioLevel])
                    groups.append(group)
                }
                canvasWidth = CGFloat(totalLevels)
            } else {
                canvasWidth = bounds.size.width
                while totalLevels % Int(canvasWidth) == 0 {
                    canvasWidth -= 1
                }

                let levelsInAGroup = totalLevels / Int(canvasWidth)
                var currentGroup: LevelGroup
                var levelsForCurrentGroup: [Float] = []

                for level in audioLevels {
                    levelsForCurrentGroup.append(level)

                    if levelsForCurrentGroup.count == levelsInAGroup {
                        currentGroup = LevelGroup(levels: levelsForCurrentGroup)
                        groups.append(currentGroup)
                        levelsForCurrentGroup = []
                    }
                }
            }

            if let theView = trimView {
                theView.frame = canvasRect
            }

            levelGroups = groups

            setNeedsDisplay(frame)
        }
    }

    // MARK: Overrides

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        trimView = NSView(frame: bounds)
        trimView!.layerContentsRedrawPolicy = .onSetNeedsDisplay
        trimView!.wantsLayer = true
        trimView!.layer = CALayer()
        trimView!.layer!.needsDisplayOnBoundsChange = true
        trimView!.layer!.autoresizingMask = [CAAutoresizingMask.layerWidthSizable, CAAutoresizingMask.layerHeightSizable]

        let trimLayer = CALayer()
        trimLayer.needsDisplayOnBoundsChange = true
        trimLayer.autoresizingMask = CAAutoresizingMask(rawValue: CAAutoresizingMask.layerWidthSizable.rawValue | CAAutoresizingMask.layerHeightSizable.rawValue)
        let trimColor = NSColor(calibratedRed: 0.0, green: 0.59, blue: 1.0, alpha: 1.0)
        trimLayer.backgroundColor = trimColor.withAlphaComponent(0.3).cgColor
        trimLayer.borderWidth = 2.0
        trimLayer.cornerRadius = 10.0
        trimLayer.borderColor = trimColor.withAlphaComponent(0.8).cgColor
        trimLayer.frame = trimView!.layer!.bounds

        trimView!.layer!.addSublayer(trimLayer)

        addSubview(trimView!)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        func heightForCurrentBand(level: Float) -> Float {
            let powerFSD = Float(maximumPower - minimumPower)
            let heightFSD = Float(CGRectGetHeight(bounds))
            let height: Float = (level + levelOffset) * (heightFSD / powerFSD)
            return height
        }

        var startPointX = firstBandX
        // let currentContext: CGContextRef = Unmanaged<CGContext>.fromOpaque(NSGraphicsContext.currentContext().graphicsPort()).takeUnretainedValue()
        guard let currentContext = NSGraphicsContext.current?.cgContext else { return }

        let backgroundColor = NSColor(calibratedRed: 0.82, green: 0.86, blue: 0.87, alpha: 1.0)
        let foregroundColor = NSColor(calibratedRed: 0.30, green: 0.44, blue: 0.58, alpha: 1.0)
        currentContext.setFillColor(backgroundColor.cgColor)
        currentContext.fill(bounds)

        currentContext.setLineWidth(1.0)
        currentContext.setStrokeColor(foregroundColor.cgColor)

        for levelGroup in levelGroups {
            let startPoint = CGPointMake(CGFloat(startPointX), 0.0)
            let endPoint = CGPointMake(startPoint.x, CGFloat(heightForCurrentBand(level: levelGroup.average)))
            let points = [startPoint, endPoint]
            currentContext.addLines(between: points)
            currentContext.strokePath()
            startPointX += 1
        }
    }

    // MARK: Instance methods

    func selectedRange() -> (start: TimeInterval, end: TimeInterval) {
        var returnValue = (0.0, duration)

        if trimView != nil {
            var start = Float(trimView!.frame.origin.x - firstBandX) * timeScale
            var end = Float(trimView!.frame.origin.x + trimView!.frame.size.width - firstBandX) * timeScale
            if start < 0 {
                start = 0
            }
            if end > Float(duration) {
                end = Float(duration)
            }

            returnValue = (TimeInterval(floorf(start)), TimeInterval(floorf(end)))
        }

        return returnValue
    }

    func reset() {
        if let theTrimView = trimView {
            theTrimView.frame = canvasRect
            delegate?.timeRangeChanged(editor: self, timeRange: selectedRange())
        }
    }

    // MARK: Mouse events

    override func mouseDown(with theEvent: NSEvent) {
        if trimView != nil {
            let point = theEvent.locationInWindow
            let convertedPoint = convert(point, to: self)
            if NSPointInRect(convertedPoint, frame) {
                let midX = trimView!.frame.origin.x + trimView!.frame.size.width / 2
                if convertedPoint.x > midX {
                    dragState = .DraggingFromRight
                } else {
                    dragState = .DraggingFromLeft
                }
                previousPoint = convertedPoint
            }
        }
    }

    override func mouseDragged(with theEvent: NSEvent) {
        if dragState == .DraggingFromRight || dragState == .DraggingFromLeft, trimView != nil {
            let point = convert(theEvent.locationInWindow, to: self)
            var targetFrame = trimView!.frame
            let deltaX = point.x - previousPoint.x
            if dragState == .DraggingFromLeft {
                targetFrame.origin.x += deltaX
                targetFrame.size.width -= deltaX
            } else {
                targetFrame.size.width += deltaX
            }

            targetFrame = NSIntegralRect(targetFrame)

            if targetFrame.size.width > 10.0 {
                if !NSContainsRect(canvasRect, targetFrame) {
                    targetFrame = NSIntersectionRect(canvasRect, targetFrame)
                }

                trimView!.frame = targetFrame
                delegate?.timeRangeChanged(editor: self, timeRange: selectedRange())
                previousPoint = point
            }
        }
    }

    override func mouseUp(with _: NSEvent) {
        dragState = .Ended
    }
}
