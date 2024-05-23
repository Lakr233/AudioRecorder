//
//  RootController.swift
//  AudioRecorder
//
//  Created by Harshad Dange on 19/07/2014.
//  Copyright (c) 2014 Laughing Buddha Software. All rights reserved.
//

import AVFoundation
import Cocoa

// MARK: Extensions

extension Array {
    func firstObject() -> Element? {
        var firstObject: Element?
        if count > 0 {
            firstObject = self[0]
        }
        return firstObject
    }

    func lastObject() -> Element? {
        var lastObject: Element?
        if count > 0 {
            lastObject = self[endIndex - 1]
        }
        return lastObject
    }
}

extension TimeInterval {
    func hourComponent() -> Int {
        Int(self / 3600)
    }

    func minuteComponent() -> Int {
        let remainderByRemovingHours = truncatingRemainder(dividingBy: TimeInterval(3600))
        return Int(remainderByRemovingHours / 60)
    }

    func secondComponent() -> Int {
        let remainderByRemovingHours = truncatingRemainder(dividingBy: TimeInterval(3600))
        return Int(remainderByRemovingHours.truncatingRemainder(dividingBy: TimeInterval(60)))
    }

    func hhmmss() -> String {
        String(format: "%02d : %02d : %02d", hourComponent(), minuteComponent(), secondComponent())
    }
}

// MARK: RootController

class RootController: NSObject, EditorControllerDelegate {
    // MARK: Defined types

    enum ButtonState: Int {
        case NotYetStarted = 0
        case Recording

        func buttonTitle() -> String {
            switch self {
            case .NotYetStarted: "Record"
            case .Recording: "Stop"
            }
        }
    }

    // MARK: Outlets

    @IBOutlet var recordButton: NSButton!
    @IBOutlet var timeField: NSTextField!
    @IBOutlet var qualityPresetMatrix: NSMatrix!
    @IBOutlet var window: NSWindow!

    // MARK: Actions

    @IBAction
    @objc
    func clickRecord(_ sender: NSButton) {
        var nextState = ButtonState.NotYetStarted
        switch recorderState {
        case .NotYetStarted:
            nextState = .Recording

            // Create and start recording
            createRecorder()
            let ans = recorder?.record()
            print("[*] starting record returns \(ans ?? false ? "success" : "failure")")

            // Create a timer
            timer = Timer.scheduledTimer(
                timeInterval: 0.25,
                target: self,
                selector: #selector(timerChanged),
                userInfo: nil,
                repeats: true
            )
            timer!.fire()

        case .Recording:
            nextState = .NotYetStarted

            editor = EditorController(windowNibName: "EditorController")
            editor!.powerTrace = powerTrace
            editor!.recordingURL = recorder?.url as NSURL?
            editor!.delegate = self
            if let theDuration = recorder?.currentTime {
                editor!.duration = theDuration
            }

            // Stop recording
            recorder?.stop()
            recorder = nil

            // Invalidate the timer
            timer?.invalidate()
            timer = nil

            // Clear the power trace
            powerTrace.removeAll(keepingCapacity: false)

            guard let window = NSApp.keyWindow, let sheetWindow = editor?.window else {
                return
            }
            window.beginSheet(sheetWindow, completionHandler: nil)
        }

        recorderState = nextState
        recordButton.title = recorderState.buttonTitle()
    }

    // MARK: Instance variables

    var recorder: AVAudioRecorder?
    var recorderState = ButtonState.NotYetStarted
    var timer: Timer?
    var powerTrace: [Float] = []
    var editor: EditorController?

    // MARK: Overrides

    override func awakeFromNib() {
        super.awakeFromNib()

        updateTimeLabel(currentTime: 0)
    }

    // MARK: Instance methods

    func createRecorder() {
        var initialisedRecorder: AVAudioRecorder?
        let currentDate = NSDate()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM-yy HHmmss"
        let fileName = "Recording on " + dateFormatter.string(from: currentDate as Date) + ".caf"
        let filePaths = NSSearchPathForDirectoriesInDomains(.musicDirectory, .userDomainMask, true)
        if let firstPath = filePaths.firstObject() {
            let recordingPath = firstPath + fileName
            let url = NSURL(fileURLWithPath: recordingPath)
            let selectedPreset = RecordingPreset.High
            do {
                initialisedRecorder = try AVAudioRecorder(url: url as URL, settings: selectedPreset.settings())
            } catch {
                print("nope")
            }
            initialisedRecorder!.isMeteringEnabled = true
            initialisedRecorder!.prepareToRecord()
        }
        recorder = initialisedRecorder
    }

    func updateTimeLabel(currentTime: TimeInterval?) {
        timeField.stringValue = (currentTime?.hhmmss())!
    }

    @objc func timerChanged(aTimer: Timer) {
        if let theRecorder = recorder {
            theRecorder.updateMeters()
            powerTrace.append(theRecorder.peakPower(forChannel: 0))
            updateTimeLabel(currentTime: theRecorder.currentTime)
        } else {
            aTimer.invalidate()
            timer = nil
        }
    }

    // MARK: EditorControllerDelegate methods

    func editorControllerDidFinishExporting(editor: EditorController) {
        guard let window = NSApp.keyWindow, let sheetWindow = editor.window else {
            return
        }
        window.endSheet(sheetWindow)
        sheetWindow.close()
        self.editor = nil
        timeField.stringValue = TimeInterval(0).hhmmss()
    }
}
