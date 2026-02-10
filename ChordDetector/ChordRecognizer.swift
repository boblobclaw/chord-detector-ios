//
//  ChordRecognizer.swift
//  ChordDetector
//
//  Recognizes chords from detected pitches
//

import Foundation

struct Chord {
    let root: String
    let quality: ChordQuality
    let bass: String?  // For slash chords
    
    var displayName: String {
        if let bass = bass, bass != root {
            return "\(root)\(quality.symbol)/\(bass)"
        }
        return "\(root)\(quality.symbol)"
    }
}

enum ChordQuality: String, CaseIterable {
    case major = "Major"
    case minor = "Minor"
    case diminished = "Diminished"
    case augmented = "Augmented"
    case dominant7 = "7"
    case major7 = "maj7"
    case minor7 = "m7"
    case suspended2 = "sus2"
    case suspended4 = "sus4"
    case power = "5"
    
    var symbol: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        case .diminished: return "dim"
        case .augmented: return "aug"
        case .dominant7: return "7"
        case .major7: return "maj7"
        case .minor7: return "m7"
        case .suspended2: return "sus2"
        case .suspended4: return "sus4"
        case .power: return "5"
        }
    }
}

struct ChordRecognitionResult {
    let chord: Chord?
    let confidence: Double
}

class ChordRecognizer {
    private var tuning: Tuning = .guitar(.standard)
    private var instrument: Instrument = .guitar
    
    // Semitone intervals for each chord quality (relative to root)
    private let chordIntervals: [ChordQuality: [Int]] = [
        .major: [0, 4, 7],
        .minor: [0, 3, 7],
        .diminished: [0, 3, 6],
        .augmented: [0, 4, 8],
        .dominant7: [0, 4, 7, 10],
        .major7: [0, 4, 7, 11],
        .minor7: [0, 3, 7, 10],
        .suspended2: [0, 2, 7],
        .suspended4: [0, 5, 7],
        .power: [0, 7]
    ]
    
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    func setTuning(_ tuning: Tuning) {
        self.tuning = tuning
    }
    
    func setInstrument(_ instrument: Instrument) {
        self.instrument = instrument
    }
    
    func getFrequencyRange() -> (min: Double, max: Double) {
        switch instrument {
        case .guitar:
            return (50, 500)  // E2 to B4
        case .piano:
            switch tuning {
            case .piano(let range):
                let minFreq = midiToFrequency(range.range.min)
                let maxFreq = midiToFrequency(range.range.max)
                return (minFreq, maxFreq)
            default:
                return (27.5, 4186)  // Full piano range A0 to C8
            }
        }
    }
    
    private func midiToFrequency(_ midiNote: Int) -> Double {
        return 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }
    
    func recognizeChord(from pitches: [Pitch]) -> ChordRecognitionResult {
        guard pitches.count >= 2 else {
            return ChordRecognitionResult(chord: nil, confidence: 0)
        }
        
        // Get unique note classes (ignoring octaves)
        let noteClasses = Set(pitches.map { $0.midiNote % 12 })
        let detectedCount = noteClasses.count
        
        // Try to match against known chords
        var bestMatch: Chord?
        var bestConfidence = 0.0
        var bestChordSize = Int.max
        
        for rootIndex in 0..<12 {
            for quality in ChordQuality.allCases {
                guard let intervals = chordIntervals[quality] else { continue }
                
                let requiredNotes = Set(intervals.map { (rootIndex + $0) % 12 })
                let chordSize = requiredNotes.count
                
                // Calculate match metrics
                let matchedNotes = noteClasses.intersection(requiredNotes).count
                
                // Skip if we don't have at least 2 matching notes
                guard matchedNotes >= 2 else { continue }
                
                // Completeness: what fraction of the chord's notes did we detect?
                // e.g., detecting C,E,G for C major = 3/3 = 1.0
                let completeness = Double(matchedNotes) / Double(chordSize)
                
                // Purity: what fraction of detected notes belong to this chord?
                // e.g., detecting C,E,G,A and matching C major = 3/4 = 0.75
                let purity = Double(matchedNotes) / Double(detectedCount)
                
                // Confidence = geometric mean of completeness and purity
                // This naturally stays in 0-1 range and rewards both factors equally
                let confidence = sqrt(completeness * purity)
                
                // Prefer simpler chords when confidence is similar (within 5%)
                // e.g., prefer C major over Cmaj7 if both match well
                let dominated = confidence < bestConfidence - 0.05
                let dominated2 = confidence < bestConfidence && chordSize >= bestChordSize
                
                if !dominated && !dominated2 {
                    if confidence > bestConfidence || (confidence == bestConfidence && chordSize < bestChordSize) {
                        bestConfidence = confidence
                        bestChordSize = chordSize
                        let root = noteNames[rootIndex]
                        
                        // Determine bass note (lowest pitch)
                        let bassNote = pitches.min { $0.midiNote < $1.midiNote }.map { noteNames[$0.midiNote % 12] }
                        
                        bestMatch = Chord(root: root, quality: quality, bass: bassNote)
                    }
                }
            }
        }
        
        // Confidence is already 0-1 (geometric mean of two 0-1 values)
        // Threshold of 0.5 means we need decent completeness AND purity
        if bestConfidence >= 0.5 {
            return ChordRecognitionResult(chord: bestMatch, confidence: bestConfidence)
        }
        
        return ChordRecognitionResult(chord: nil, confidence: 0)
    }
    
}

// MARK: - Instrument Selection

enum Instrument: String, CaseIterable, Identifiable {
    case guitar = "Guitar"
    case piano = "Piano"
    
    var id: String { rawValue }
    var name: String { rawValue }
    
    var tunings: [Tuning] {
        switch self {
        case .guitar:
            return GuitarTuning.allCases.map { Tuning.guitar($0) }
        case .piano:
            return PianoRange.allCases.map { Tuning.piano($0) }
        }
    }
}

enum Tuning: Hashable {
    case guitar(GuitarTuning)
    case piano(PianoRange)
    
    var name: String {
        switch self {
        case .guitar(let tuning): return tuning.name
        case .piano(let range): return range.name
        }
    }
}

enum PianoRange: String, CaseIterable, Identifiable {
    case full = "Full Range (A0-C8)"
    case bass = "Bass (A0-E3)"
    case mid = "Middle (F3-B5)"
    case treble = "Treble (C6-C8)"
    
    var id: String { rawValue }
    var name: String { rawValue }
    
    // MIDI note numbers for range bounds
    var range: (min: Int, max: Int) {
        switch self {
        case .full:
            return (21, 108)  // A0 to C8
        case .bass:
            return (21, 52)   // A0 to E3
        case .mid:
            return (53, 83)   // F3 to B5
        case .treble:
            return (84, 108)  // C6 to C8
        }
    }
}

// MARK: - Guitar Tuning

enum GuitarTuning: String, CaseIterable, Identifiable {
    case standard = "Standard (EADGBE)"
    case dropD = "Drop D (DADGBE)"
    case halfStepDown = "Half Step Down (D#G#C#F#A#D#)"
    case openG = "Open G (DGDGBD)"
    case openD = "Open D (DADF#AD)"
    case dadgad = "DADGAD"
    
    var id: String { rawValue }
    var name: String { rawValue }
    
    // MIDI note numbers for open strings (low to high)
    var openStrings: [Int] {
        switch self {
        case .standard:
            return [40, 45, 50, 55, 59, 64]  // E2, A2, D3, G3, B3, E4
        case .dropD:
            return [38, 45, 50, 55, 59, 64]  // D2, A2, D3, G3, B3, E4
        case .halfStepDown:
            return [39, 44, 49, 54, 58, 63]  // D#2, G#2, C#3, F#3, A#3, D#4
        case .openG:
            return [38, 43, 47, 50, 55, 62]  // D2, G2, B2, D3, G3, D4
        case .openD:
            return [38, 45, 50, 54, 57, 62]  // D2, A2, D3, F#3, A3, D4
        case .dadgad:
            return [38, 45, 50, 55, 57, 62]  // D2, A2, D3, G3, A3, D4
        }
    }
}
