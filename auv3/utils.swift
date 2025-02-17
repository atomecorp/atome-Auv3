//
//  utils.swift
//  auv3
//
//  Created by jeezs on 26/04/2022.
//

import AVFoundation
import Foundation
import CoreAudio

// Protocol for real-time audio data delegation
protocol AudioDataDelegate: AnyObject {
    func didReceiveAudioData(_ data: [Float], timestamp: Double)
}

public class auv3Utils: AUAudioUnit {
    private var _outputBusArray: AUAudioUnitBusArray!
    private var _inputBusArray: AUAudioUnitBusArray!
    private var isMuted: Bool = false
    private var audioLogger: FileHandle?
    private var isLogging: Bool = false
    
    // Audio visualization properties
    weak var audioDataDelegate: AudioDataDelegate?
    private let audioBufferSize = 1024
    private var audioBuffer = [Float](repeating: 0, count: 1024)
    private var bufferIndex = 0
    private var lastVisualizationUpdate: TimeInterval = 0
    private let visualizationUpdateInterval: TimeInterval = 1.0 / 30.0 // 30 FPS update rate

    // Custom AudioBufferList wrapper
    private struct AudioBufferListWrapper {
        let ptr: UnsafeMutablePointer<AudioBufferList>
        
        var numberOfBuffers: Int {
            Int(ptr.pointee.mNumberBuffers)
        }
        
        func buffer(at index: Int) -> AudioBuffer {
            precondition(index < numberOfBuffers)
            return withUnsafePointer(to: &ptr.pointee.mBuffers) { buffers in
                buffers.withMemoryRebound(to: AudioBuffer.self, capacity: numberOfBuffers) { reboundBuffers in
                    reboundBuffers[index]
                }
            }
        }
        
        mutating func setBuffer(at index: Int, _ buffer: AudioBuffer) {
            precondition(index < numberOfBuffers)
            withUnsafeMutablePointer(to: &ptr.pointee.mBuffers) { buffers in
                buffers.withMemoryRebound(to: AudioBuffer.self, capacity: numberOfBuffers) { reboundBuffers in
                    reboundBuffers[index] = buffer
                }
            }
        }
    }
    
    // essential function for rendering
    public override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let strongSelf = self else { return kAudioUnitErr_NoConnection }
            guard let pullInputBlock = pullInputBlock else {
                return kAudioUnitErr_NoConnection
            }

            var inputTimestamp = AudioTimeStamp()
            let inputBusNumber: Int = 0

            let inputStatus = pullInputBlock(actionFlags, &inputTimestamp, frameCount, inputBusNumber, outputData)

            if inputStatus != noErr {
                return inputStatus
            }

            var bufferList = AudioBufferListWrapper(ptr: outputData)

            // Log audio data if logging is enabled
            if strongSelf.isLogging, let logger = strongSelf.audioLogger {
                for i in 0..<bufferList.numberOfBuffers {
                    let buffer = bufferList.buffer(at: i)
                    if let inData = buffer.mData {
                        let data = Data(bytes: inData, count: Int(buffer.mDataByteSize))
                        try? logger.write(contentsOf: data)
                    }
                }
            }

            // Process audio data for visualization with rate limiting
            let currentTime = CACurrentMediaTime()
            if currentTime - strongSelf.lastVisualizationUpdate >= strongSelf.visualizationUpdateInterval {
                for i in 0..<bufferList.numberOfBuffers {
                    let buffer = bufferList.buffer(at: i)
                    if let inData = buffer.mData {
                        let floatData = inData.assumingMemoryBound(to: Float.self)
                        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                        
                        var visualizationData = [Float]()
                        let downsampleFactor = max(1, count / strongSelf.audioBufferSize)
                        
                        for i in stride(from: 0, to: count, by: downsampleFactor) {
                            let sum = (0..<downsampleFactor)
                                .map { j in i + j < count ? abs(floatData[i + j]) : 0 }
                                .reduce(0, +)
                            visualizationData.append(sum / Float(downsampleFactor))
                        }
                        
                        DispatchQueue.main.async {
                            strongSelf.audioDataDelegate?.didReceiveAudioData(visualizationData, timestamp: inputTimestamp.mSampleTime)
                        }
                    }
                }
                strongSelf.lastVisualizationUpdate = currentTime
            }

            // Handle muting
            if strongSelf.isMuted {
                for i in 0..<bufferList.numberOfBuffers {
                    let buffer = bufferList.buffer(at: i)
                    if let mData = buffer.mData {
                        memset(mData, 0, Int(buffer.mDataByteSize))
                    }
                }
            }
            
            strongSelf.checkHostTransport()
            strongSelf.checkHostTempo()

            return noErr
        }
    }

    public override var musicalContextBlock: AUHostMusicalContextBlock? {
        get {
            return super.musicalContextBlock
        }
        set {
            super.musicalContextBlock = newValue
        }
    }
    
    // Add mute utilities
    public var mute: Bool {
        get { return isMuted }
        set { isMuted = newValue }
    }
    
    // Add logging control
    public var logging: Bool {
        get { return isLogging }
        set {
            if newValue != isLogging {
                if newValue {
                    startLogging()
                } else {
                    stopLogging()
                }
                isLogging = newValue
            }
        }
    }
    
    private func startLogging() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let logPath = documentsPath.appendingPathComponent("audio_log_\(timestamp).raw")
        
        FileManager.default.createFile(atPath: logPath.path, contents: nil)
        audioLogger = try? FileHandle(forWritingTo: logPath)
        
        print("Started audio logging to: \(logPath.path)")
    }
    
    private func stopLogging() {
        audioLogger?.closeFile()
        audioLogger = nil
        print("Stopped audio logging")
    }
    
    // busses handling
    override public var inputBusses: AUAudioUnitBusArray {
        return _inputBusArray
    }

    override public var outputBusses: AUAudioUnitBusArray {
        return _outputBusArray
    }

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

        _inputBusArray = AUAudioUnitBusArray(audioUnit: self,
                                             busType: .input,
                                             busses: [try AUAudioUnitBus(format: format)])

        _outputBusArray = AUAudioUnitBusArray(audioUnit: self,
                                              busType: .output,
                                              busses: [try AUAudioUnitBus(format: format)])
    }

    private func checkHostTransport() {
        if let transportStateBlock = self.transportStateBlock {
            var transportStateChanged = AUHostTransportStateFlags(rawValue: 0)
            var currentSampleTime: Double = 0

            let success = transportStateBlock(&transportStateChanged,
                                          &currentSampleTime,
                                          nil,
                                          nil)
            if success {
                DispatchQueue.main.async {
                    if transportStateChanged.rawValue != 0 {
                        if transportStateChanged.rawValue & 2 != 0 {
                            print("Transport is playing")
                        }
                        print("Playhead position: \(currentSampleTime)")
                        
                        if let sampleRate = self.getSampleRate() {
                            print("Sample Rate: \(sampleRate)")
                        }
                    }
                }
            } else {
                print("Failed to retrieve transport state")
            }
        }
    }
  
    private func checkHostTempo() {
        guard let contextBlock = self.musicalContextBlock else {
            print("No musical context block available")
            return
        }

        var tempo: Double = 0
        var timeSignatureNumerator: Double = 0
        var timeSignatureDenominator: Int = 0
        var currentBeatPosition: Double = 0
        var timeSignatureValid: Int = 0
        var tempoValid: Double = 0

        let success = contextBlock(
            &tempo,
            &timeSignatureNumerator,
            &timeSignatureDenominator,
            &currentBeatPosition,
            &timeSignatureValid,
            &tempoValid
        )

        if success {
            if timeSignatureValid != 0 {
                print("Tempo: \(tempo) BPM")
                print("Time Signature: \(Int(timeSignatureNumerator))/\(Int(timeSignatureDenominator))")
                print("Beat Position: \(currentBeatPosition)")
            }
        }
    }
    
    func getSampleRate() -> Double? {
        guard outputBusses.count > 0 else {
            print("No output busses available")
            return nil
        }
        return outputBusses[0].format.sampleRate
    }
}
