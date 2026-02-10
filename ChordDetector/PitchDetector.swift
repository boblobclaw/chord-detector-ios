//
//  PitchDetector.swift
//  ChordDetector
//
//  Pitch detection using FFT-based spectral analysis
//

import Foundation
import Accelerate

struct Pitch: Equatable {
    let frequency: Double
    let amplitude: Double
    let noteName: String
    let midiNote: Int
}

class PitchDetector {
    private var minFrequency: Double = 50   // ~E2 (low E string)
    private var maxFrequency: Double = 500  // ~B4 (high B on fret 19)
    private let threshold: Double = 0.1     // Detection threshold
    
    // MARK: - Cached FFT Resources (High Priority Fix #2)
    private let fftSize: Int = 4096
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let halfCount: Int
    
    // Pre-allocated buffers to avoid heap allocations in hot path
    private var windowBuffer: [Float]
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudeBuffer: [Float]
    private var dbMagnitudeBuffer: [Float]
    
    init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        halfCount = fftSize / 2
        
        // Create FFT setup once - this is expensive
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Failed to create FFT setup")
        }
        fftSetup = setup
        
        // Pre-allocate all buffers
        windowBuffer = [Float](repeating: 0, count: fftSize)
        realBuffer = [Float](repeating: 0, count: fftSize)
        imagBuffer = [Float](repeating: 0, count: fftSize)
        magnitudeBuffer = [Float](repeating: 0, count: halfCount)
        dbMagnitudeBuffer = [Float](repeating: 0, count: halfCount)
        
        // Pre-compute Hann window (never changes)
        vDSP_hann_window(&windowBuffer, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    func setFrequencyRange(min: Double, max: Double) {
        minFrequency = min
        maxFrequency = max
    }
    
    func detectPitches(in samples: [Float], sampleRate: Double) -> [Pitch] {
        guard samples.count >= fftSize else { return [] }
        
        var pitches: [Pitch] = []
        
        // Apply window and perform FFT using pre-allocated buffers
        guard let fftResult = performFFT(on: samples, sampleRate: sampleRate) else {
            return []
        }
        
        // Find peaks in spectrum
        let peaks = findSpectralPeaks(magnitudes: fftResult.magnitudes, 
                                       frequencies: fftResult.frequencies,
                                       sampleRate: sampleRate)
        
        // Convert peaks to pitches
        for peak in peaks {
            if let pitch = frequencyToPitch(peak.frequency, amplitude: peak.magnitude) {
                // Avoid duplicates (within ~15 cents for better harmonic handling)
                if !pitches.contains(where: { abs($0.frequency - pitch.frequency) < pitch.frequency * 0.009 }) {
                    pitches.append(pitch)
                }
            }
        }
        
        // Sort by amplitude (loudest first)
        return pitches.sorted { $0.amplitude > $1.amplitude }
    }
    
    // MARK: - FFT Processing (High Priority Fix #1 - Memory Management)
    
    private func performFFT(on samples: [Float], sampleRate: Double) -> (magnitudes: [Float], frequencies: [Double])? {
        // Copy samples into real buffer and apply window in one pass
        // This avoids the unsafe pointer casting issue
        for i in 0..<min(samples.count, fftSize) {
            realBuffer[i] = samples[i] * windowBuffer[i]
        }
        
        // Zero-pad if needed
        if samples.count < fftSize {
            for i in samples.count..<fftSize {
                realBuffer[i] = 0
            }
        }
        
        // Reset imaginary buffer
        for i in 0..<fftSize {
            imagBuffer[i] = 0
        }
        
        // Perform FFT using properly mutable buffers
        realBuffer.withUnsafeMutableBufferPointer { realPtr in
            imagBuffer.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        
        // Calculate magnitudes from the FFT output
        realBuffer.withUnsafeBufferPointer { realPtr in
            imagBuffer.withUnsafeBufferPointer { imagPtr in
                magnitudeBuffer.withUnsafeMutableBufferPointer { magPtr in
                    // Manual magnitude calculation: sqrt(real^2 + imag^2)
                    // But we use squared magnitude for efficiency (relative comparison still valid)
                    for i in 0..<halfCount {
                        let real = realPtr[i]
                        let imag = imagPtr[i]
                        magPtr[i] = real * real + imag * imag
                    }
                }
            }
        }
        
        // Convert to decibel scale
        var zero: Float = 0.0001
        vDSP_vdbcon(magnitudeBuffer, 1, &zero, &dbMagnitudeBuffer, 1, vDSP_Length(halfCount), 0)
        
        // Generate frequency array
        let frequencies = (0..<halfCount).map { Double($0) * sampleRate / Double(fftSize) }
        
        return (dbMagnitudeBuffer, frequencies)
    }
    
    private func findSpectralPeaks(magnitudes: [Float], frequencies: [Double], sampleRate: Double) -> [(frequency: Double, magnitude: Double)] {
        var peaks: [(frequency: Double, magnitude: Double)] = []
        
        let binWidth = sampleRate / Double(fftSize)
        let minBin = max(1, Int(minFrequency / binWidth))
        let maxBin = min(halfCount - 2, Int(maxFrequency / binWidth))
        
        for i in (minBin + 1)..<maxBin {
            let mag = magnitudes[i]
            let prevMag = magnitudes[i - 1]
            let nextMag = magnitudes[i + 1]
            
            // Check if it's a peak and above threshold
            if mag > threshold && mag > prevMag && mag > nextMag {
                // Quadratic interpolation for better frequency estimation
                let alpha = Double(prevMag)
                let beta = Double(mag)
                let gamma = Double(nextMag)
                
                // Avoid division by zero
                let denominator = alpha - 2 * beta + gamma
                guard abs(denominator) > 0.0001 else {
                    peaks.append((frequencies[i], Double(mag)))
                    continue
                }
                
                let p = 0.5 * (alpha - gamma) / denominator
                let interpolatedFreq = frequencies[i] + p * binWidth
                
                // Validate interpolated frequency is reasonable
                if interpolatedFreq >= minFrequency && interpolatedFreq <= maxFrequency {
                    peaks.append((interpolatedFreq, Double(mag)))
                }
            }
        }
        
        return peaks
    }
    
    private func frequencyToPitch(_ frequency: Double, amplitude: Double) -> Pitch? {
        guard frequency >= minFrequency && frequency <= maxFrequency else { return nil }
        
        // Convert frequency to MIDI note number
        let midiNote = 69.0 + 12.0 * log2(frequency / 440.0)
        let roundedMidi = Int(round(midiNote))
        
        // Validate MIDI note is in reasonable range (A0 = 21, C8 = 108)
        guard roundedMidi >= 21 && roundedMidi <= 108 else { return nil }
        
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let noteIndex = ((roundedMidi % 12) + 12) % 12  // Handle negative modulo
        let octave = (roundedMidi / 12) - 1
        let noteName = "\(noteNames[noteIndex])\(octave)"
        
        return Pitch(frequency: frequency, amplitude: amplitude, noteName: noteName, midiNote: roundedMidi)
    }
}
