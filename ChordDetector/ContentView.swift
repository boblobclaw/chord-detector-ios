//
//  ContentView.swift
//  ChordDetector
//
//  Main UI for chord detection
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @State private var selectedInstrument: Instrument = .guitar
    @State private var selectedTuning: Tuning = .guitar(.standard)
    
    var body: some View {
        VStack(spacing: 25) {
            // Title
            Text("Chord Detector")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 20)
            
            // Current Chord Display
            VStack(spacing: 10) {
                Text("Detected Chord")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(audioEngine.detectedChord?.displayName ?? "—")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundColor(audioEngine.detectedChord != nil ? .blue : .gray)
                    .frame(height: 100)
                    .animation(.easeInOut(duration: 0.2), value: audioEngine.detectedChord?.displayName)
            }
            
            // Confidence Meter
            if let confidence = audioEngine.confidence {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Confidence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(confidence * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: confidence)
                        .progressViewStyle(LinearProgressViewStyle(tint: confidenceColor(confidence)))
                }
                .padding(.horizontal)
            }
            
            // Detected Notes
            if !audioEngine.detectedNotes.isEmpty {
                VStack(spacing: 10) {
                    Text("Detected Notes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 15) {
                        ForEach(audioEngine.detectedNotes, id: \.self) { note in
                            NoteBadge(note: note)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Instrument Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Instrument")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Picker("Instrument", selection: $selectedInstrument) {
                    ForEach(Instrument.allCases) { instrument in
                        Text(instrument.name).tag(instrument)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .onChange(of: selectedInstrument) { newInstrument in
                    selectedTuning = newInstrument.tunings[0]
                    audioEngine.setInstrument(newInstrument)
                    audioEngine.setTuning(selectedTuning)
                }
            }
            
            // Tuning/Range Selector
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedInstrument == .guitar ? "Tuning" : "Range")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Picker("Tuning", selection: $selectedTuning) {
                    ForEach(selectedInstrument.tunings, id: \.self) { tuning in
                        Text(tuning.name).tag(tuning)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal)
                .onChange(of: selectedTuning) { newTuning in
                    audioEngine.setTuning(newTuning)
                }
            }
            
            // Start/Stop Button
            Button(action: {
                if audioEngine.isRunning {
                    audioEngine.stop()
                } else {
                    audioEngine.start()
                }
            }) {
                HStack {
                    Image(systemName: audioEngine.isRunning ? "stop.fill" : "mic.fill")
                    Text(audioEngine.isRunning ? "Stop Listening" : "Start Listening")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(audioEngine.isRunning ? Color.red : Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .alert("Microphone Access Required", isPresented: $audioEngine.showPermissionAlert) {
            Button("OK") { }
        } message: {
            Text("Please enable microphone access in Settings to use chord detection.")
        }
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...1.0: return .green
        case 0.5..<0.8: return .yellow
        default: return .red
        }
    }
}

struct NoteBadge: View {
    let note: String
    
    var body: some View {
        Text(note)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .background(Color.orange)
            .cornerRadius(10)
    }
}

#Preview {
    ContentView()
}
