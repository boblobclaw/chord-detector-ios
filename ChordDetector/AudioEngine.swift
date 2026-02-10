//
//  AudioEngine.swift
//  ChordDetector
//
//  Manages audio input and processing
//

import AVFoundation
import Combine

class AudioEngine: ObservableObject {
    @Published var isRunning = false
    @Published var detectedChord: Chord?
    @Published var detectedNotes: [String] = []
    @Published var confidence: Double?
    @Published var showPermissionAlert = false
    
    private var audioEngine: AVAudioEngine?
    private var pitchDetector = PitchDetector()
    private var chordRecognizer = ChordRecognizer()
    private var currentInstrument: Instrument = .guitar
    private var currentTuning: Tuning = .guitar(.standard)
    private var sampleRate: Double = 44100  // Will be updated from audio format
    
    private let processingQueue = DispatchQueue(label: "com.chorddetector.audio", qos: .userInitiated)
    
    func start() {
        checkMicrophonePermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.setupAudioSession()
                    self?.startAudioEngine()
                } else {
                    self?.showPermissionAlert = true
                }
            }
        }
    }
    
    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRunning = false
        detectedChord = nil
        detectedNotes = []
        confidence = nil
    }
    
    func setInstrument(_ instrument: Instrument) {
        currentInstrument = instrument
        chordRecognizer.setInstrument(instrument)
        updateFrequencyRange()
    }
    
    func setTuning(_ tuning: Tuning) {
        currentTuning = tuning
        chordRecognizer.setTuning(tuning)
        updateFrequencyRange()
    }
    
    private func updateFrequencyRange() {
        let range = chordRecognizer.getFrequencyRange()
        pitchDetector.setFrequencyRange(min: range.min, max: range.max)
    }
    
    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                completion(granted)
            }
        @unknown default:
            completion(false)
        }
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    private func startAudioEngine() {
        audioEngine = AVAudioEngine()
        
        let inputNode = audioEngine!.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate audio format
        guard inputFormat.channelCount > 0 else {
            print("Invalid audio format: no channels")
            return
        }
        
        // Store sample rate from actual hardware
        sampleRate = inputFormat.sampleRate
        
        // Configure buffer size for real-time processing
        let bufferSize = AVAudioFrameCount(4096)
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine!.start()
            isRunning = true
        } catch {
            print("Failed to start audio engine: \(error)")
            // Clean up tap on failure
            inputNode.removeTap(onBus: 0)
            audioEngine = nil
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let currentSampleRate = self.sampleRate  // Capture for async block
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Convert to array for processing
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            
            // Detect pitches using actual sample rate
            let pitches = self.pitchDetector.detectPitches(in: samples, sampleRate: currentSampleRate)
            
            // Recognize chord
            let result = self.chordRecognizer.recognizeChord(from: pitches)
            
            DispatchQueue.main.async {
                self.updateUI(with: result, pitches: pitches)
            }
        }
    }
    
    private func updateUI(with result: ChordRecognitionResult, pitches: [Pitch]) {
        self.detectedChord = result.chord
        self.confidence = result.confidence
        self.detectedNotes = pitches.map { $0.noteName }.sorted()
    }
}
