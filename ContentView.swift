import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedFiles: [URL] = []
    @State private var outputDirectory: URL? = nil
    @State private var bitrate = "128 kbps"
    @State private var isCompressing = false
    @State private var progress: Double = 0.0
    @State private var statusMessage = "No file selected"
    
    let bitrates = ["64 kbps", "80 kbps", "96 kbps", "112 kbps", "128 kbps", "144 kbps", "160 kbps", "192 kbps", "224 kbps", "256 kbps", "288 kbps", "320 kbps"]
    
    var body: some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .padding(.top)
            Text("Compressr - Compress Audio and Video")
                .font(.largeTitle)
                .fontWeight(.bold)
                .lineLimit(1)
            
            Button(action: selectFiles) {
                Label("Select Media Files", systemImage: "folder.fill")
            }
            .buttonStyle(.borderedProminent)
            
            if !selectedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Selected \(selectedFiles.count) file(s):")
                        .foregroundColor(.gray)
                        .fontWeight(.semibold)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(selectedFiles, id: \.self) { file in
                                Text(file.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            VStack(alignment: .leading) {
                Text("Select Bitrate:")
                    .font(.headline)
                Picker("Bitrate", selection: $bitrate) {
                    ForEach(bitrates, id: \.self) { rate in
                        Text(rate)
                    }
                }
                .pickerStyle(.menu)
            }
            
            Menu {
                Button("Downloads") { selectPredefinedFolder("Downloads") }
                Button("Documents") { selectPredefinedFolder("Documents") }
                Button("Desktop") { selectPredefinedFolder("Desktop") }
                Divider()
                Button("Browse…") { selectOutputDirectory() }
            } label: {
                Label("Choose Output Folder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            
            if let outputDirectory = outputDirectory {
                Text("Output: \(outputDirectory.path)")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            
            Button(action: compressFiles) {
                Label("Compress", systemImage: "arrow.down.circle")
            }
            .disabled(selectedFiles.isEmpty || isCompressing || outputDirectory == nil)
            .buttonStyle(.borderedProminent)
            
            ProgressView(value: progress)
                .padding()
                .frame(height: 20)
            
            Text(statusMessage)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
        .padding()
        .frame(width: 520)
    }
    
    // MARK: - Functions
    
    func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.mp3,
            UTType.mpeg4Movie,   // .mp4 and .mov
            UTType.mpeg4Audio,
            UTType.wav,
            UTType.quickTimeMovie
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            selectedFiles = panel.urls
        }
    }

    
    func selectPredefinedFolder(_ folderName: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folderURL = home.appendingPathComponent(folderName)
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                setOutputDirectory(url)
            }
        }
    }
    
    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                setOutputDirectory(url)
            }
        }
    }
    
    func setOutputDirectory(_ url: URL) {
        do {
            let testFile = url.appendingPathComponent("test.tmp")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
            outputDirectory = url
            statusMessage = "Selected output: \(url.lastPathComponent)"
        } catch {
            statusMessage = "Can't write to output directory: \(error.localizedDescription)"
        }
    }
    
    func compressFiles() {
        isCompressing = true
        progress = 0
        statusMessage = "Starting compression..."
        
        guard let ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: "") else {
            statusMessage = "ffmpeg not found in resources."
            isCompressing = false
            return
        }
        
        guard let outputDir = outputDirectory else {
            statusMessage = "No output directory selected."
            isCompressing = false
            return
        }
        
        let bitrateValue = bitrate.replacingOccurrences(of: " kbps", with: "k")
        
        DispatchQueue.global(qos: .userInitiated).async {
            if outputDir.startAccessingSecurityScopedResource() {
                defer { outputDir.stopAccessingSecurityScopedResource() }
                
                for (index, file) in selectedFiles.enumerated() {
                    let outputURL = outputDir.appendingPathComponent("Compressed-\(file.lastPathComponent)")
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: ffmpegPath)
                    
                    var arguments = ["-y", "-i", file.path]
                    if ["mp3", "m4a"].contains(file.pathExtension.lowercased()) {
                        arguments += ["-b:a", bitrateValue]
                    } else {
                        arguments += ["-b:v", bitrateValue]
                    }
                    arguments.append(outputURL.path)
                    
                    process.arguments = arguments
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    let outputHandle = pipe.fileHandleForReading
                    
                    outputHandle.readabilityHandler = { handle in
                        if let line = String(data: handle.availableData, encoding: .utf8) {
                            // Parse progress line, e.g. extract "time=00:00:10.05" from ffmpeg stderr
                            if let timeString = parseTime(from: line),
                               let duration = getDuration(of: file),
                               let progressForFile = calculateProgress(currentTime: timeString, duration: duration) {
                                
                                DispatchQueue.main.async {
                                    // Calculate overall progress across all files
                                    let fileProgress = Double(index) / Double(self.selectedFiles.count)
                                    let progressInFile = progressForFile / Double(self.selectedFiles.count)
                                    self.progress = fileProgress + progressInFile
                                    self.statusMessage = "Compressing \(file.lastPathComponent): \(Int(self.progress * 100))%"
                                }
                            }
                        }
                    }
                    
                    do {
                        try process.run()
                        process.waitUntilExit()
                        outputHandle.readabilityHandler = nil
                    } catch {
                        DispatchQueue.main.async {
                            self.statusMessage = "Failed to run ffmpeg on \(file.lastPathComponent)"
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.statusMessage = "Compression complete"
                    self.isCompressing = false
                    self.progress = 1.0
                }
            } else {
                DispatchQueue.main.async {
                    self.statusMessage = "Permission denied for output folder."
                    self.isCompressing = false
                }
            }
        }
    }
}
func getDuration(of file: URL) -> Double? {
    // Run `ffprobe` or parse media info to get duration in seconds
    // For simplicity, assume a fixed duration or implement a method to get duration with ffprobe.
    // You can also hardcode or skip this for a rough progress bar.
    return 60.0 // Example: 60 seconds duration
}

func parseTime(from line: String) -> Double? {
    // Parse ffmpeg output line to find time=HH:MM:SS.xxx and return seconds as Double
    // Example line: "frame=  240 fps=0.0 q=28.0 size=     512kB time=00:00:10.05 bitrate= 418.2kbits/s speed=  20x"
    if let range = line.range(of: "time=") {
        let timeStringStart = line[range.upperBound...]
        let timeString = timeStringStart.split(separator: " ").first ?? ""
        return parseTimeString(String(timeString))
    }
    return nil
}

func parseTimeString(_ time: String) -> Double? {
    let parts = time.split(separator: ":").map { Double($0) ?? 0 }
    guard parts.count == 3 else { return nil }
    return parts[0] * 3600 + parts[1] * 60 + parts[2]
}

func calculateProgress(currentTime: Double, duration: Double) -> Double? {
    guard duration > 0 else { return nil }
    return min(max(currentTime / duration, 0), 1)
}
