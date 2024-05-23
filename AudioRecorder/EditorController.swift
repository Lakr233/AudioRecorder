//
//  EditorController.swift
//  AudioRecorder
//
//  Created by Harshad Dange on 20/07/2014.
//  Copyright (c) 2014 Laughing Buddha Software. All rights reserved.
//

import AVFoundation
import Cocoa
import CoreMedia

protocol EditorControllerDelegate {
    func editorControllerDidFinishExporting(editor: EditorController)
}

enum RecordingPreset: Int {
    case Low = 0
    case Medium
    case High

    func settings() -> [String: Int] {
        switch self {
        case .Low:
            [AVLinearPCMBitDepthKey: 16, AVNumberOfChannelsKey: 1, AVSampleRateKey: 12000, AVLinearPCMIsBigEndianKey: 0, AVLinearPCMIsFloatKey: 0]

        case .Medium:
            [AVLinearPCMBitDepthKey: 16, AVNumberOfChannelsKey: 1, AVSampleRateKey: 24000, AVLinearPCMIsBigEndianKey: 0, AVLinearPCMIsFloatKey: 0]

        case .High:
            [AVLinearPCMBitDepthKey: 16, AVNumberOfChannelsKey: 1, AVSampleRateKey: 48000, AVLinearPCMIsBigEndianKey: 0, AVLinearPCMIsFloatKey: 0]
        }
    }

    func exportSettings() -> [String: Int] {
        var recordingSetting = settings()
        recordingSetting[AVFormatIDKey] = Int(kAudioFormatLinearPCM)
        recordingSetting[AVLinearPCMIsNonInterleaved] = 0

        return recordingSetting
    }
}

class EditorController: NSWindowController, EditorViewDelegate {
    override func windowDidLoad() {
        super.windowDidLoad()

        refreshView()
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        editorView.delegate = self
        startField.stringValue = TimeInterval(0).hhmmss()
        endField.stringValue = duration.hhmmss()
    }

    @IBOutlet var editorView: EditorView!
    @IBOutlet var startField: NSTextField!
    @IBOutlet var endField: NSTextField!
    @IBOutlet var qualitySelector: NSSegmentedControl!

    var recordingURL: NSURL?
    var exportSession: AVAssetExportSession?
    var delegate: EditorControllerDelegate?
    var assetReadingQueue: dispatch_queue_t?
    var assetReader: AVAssetReader?
    var assetWriter: AVAssetWriter?

    var powerTrace: [Float]? {
        didSet {
            refreshView()
        }
    }

    var duration: TimeInterval = 0.0 {
        didSet {
            refreshView()
        }
    }

    @IBAction
    @objc
    func clickSave(_ sender: NSButton) {
        if let assetURL = recordingURL {
            window!.ignoresMouseEvents = true
            let selectedRange = editorView.selectedRange()
            let asset = AVAsset(url: assetURL as URL)
            let startTime = CMTimeMakeWithSeconds(selectedRange.start, preferredTimescale: 600)
            let duration = CMTimeMakeWithSeconds(selectedRange.end - selectedRange.start, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: duration)
            let exportPath = NSString(string: assetURL.path!).deletingPathExtension + "-edited.wav"

            do {
                assetReader = try AVAssetReader(asset: asset)
            } catch {
                print("Couldn't startup the AVAssetReader")
            }

            let assetTrack = asset.tracks(withMediaType: AVMediaType.audio).firstObject()!
            let readerOutput = AVAssetReaderTrackOutput(track: assetTrack, outputSettings: nil)
            assetReader!.add(readerOutput)
            assetReader!.timeRange = timeRange

            do {
                print(exportPath)
                assetWriter = try AVAssetWriter(outputURL: NSURL(fileURLWithPath: exportPath) as URL, fileType: AVFileType.wav)
            } catch {
                print("Couldn't startup the AVAssetWriter")
            }

            let selectedQuality = RecordingPreset(rawValue: qualitySelector.selectedSegment)
            let writerInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: selectedQuality?.exportSettings())
            writerInput.expectsMediaDataInRealTime = false
            assetWriter!.add(writerInput)

            assetWriter!.startWriting()
            assetWriter!.startSession(atSourceTime: CMTime.zero)

            assetReader!.startReading()

            assetReadingQueue = DispatchQueue(label: "com.lbs.audiorecorder.assetreadingqueue")
            writerInput.requestMediaDataWhenReady(on: assetReadingQueue!) {
                while writerInput.isReadyForMoreMediaData {
                    let nextBuffer: CMSampleBuffer? = readerOutput.copyNextSampleBuffer()
                    if self.assetReader!.status == AVAssetReader.Status.reading, nextBuffer != nil {
                        writerInput.append(nextBuffer!)
                    } else {
                        writerInput.markAsFinished()

                        switch self.assetReader!.status {
                        case .failed:
                            self.assetWriter!.cancelWriting()
                            print("Failed :(")

                        case .completed:
                            print("Done!")
                            self.assetWriter!.endSession(atSourceTime: duration)

                            self.assetWriter!.finishWriting(completionHandler: {
                                DispatchQueue.main.async {
                                    if let theDelegate = self.delegate {
                                        theDelegate.editorControllerDidFinishExporting(editor: self)
                                    }
                                }
                            }
                            )

                        default:
                            print("This should not happen :/")
                        }

                        break
                    }
                }
            }
        }
    }

    @IBAction
    @objc
    func cliickReset(_ sender: NSButton) {
        editorView.reset()
    }

    func refreshView() {
        if editorView != nil {
            editorView.duration = duration
            if let trace = powerTrace {
                editorView.audioLevels = trace
            }
        }
    }

    // MARK: EditorViewDelegate methods

    func timeRangeChanged(editor _: EditorView, timeRange: (start: TimeInterval, end: TimeInterval)) {
        startField.stringValue = timeRange.start.hhmmss()
        endField.stringValue = timeRange.end.hhmmss()
    }
}
