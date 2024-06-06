//
//  ContentView.swift
//  Image Guard
//
//  Created by Tomasz Baranowicz on 06/06/2024.
//

import SwiftUI
import Vision

enum DataType {
    case email
    case phone
    case url
}

struct SensitiveData: Hashable, Identifiable {
    let id = UUID()
    let type: DataType
    var selected: Bool
    let boundingBox: CGRect
    let text: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

struct ContentView: View {
    @State private var droppedImage: NSImage?
    @State private var blurredImage: NSImage?
    @State private var emailRects: [CGRect] = []
    
    @State private var detectEmails = true
    @State private var detectPhoneNumbers = true
    @State private var detectURLs = true
    
    @State private var detectedData: [SensitiveData] = []
    
    var body: some View {
        HStack {
            VStack {
                if let image = blurredImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .shadow(color: .black.opacity(0.75), radius: 15)
                } else {
                    Text("Drop an image here")
                        .frame(width: 300, height: 200)
                        .border(Color.gray, width: 2)
                }
            }
            .onDrop(of: [.image], isTargeted: nil) { providers in
                loadImage(from: providers)
                return true
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            VStack {
                
                Form {
                    Section(header:Text("Hide Sensitive Data:").font(.title3)) {
                        
                        Toggle("Emails", isOn: $detectEmails).onChange(of: detectEmails) {
                            self.updateImage()
                        }
                        Toggle("Phone Numbers", isOn: $detectPhoneNumbers).onChange(of: detectPhoneNumbers) {
                            self.updateImage()
                        }
                        Toggle("URLs", isOn: $detectURLs).onChange(of: detectURLs) {
                            self.updateImage()
                        }
                    }
                    Divider()
                    
                    Section(header:Text("Detected Sensitive Data:").font(.title3)){
                        if detectEmails {
                            Text("Emails:")
                            self.listForType(type: .email)
                        }
                        if detectPhoneNumbers {
                            Text("Phone numbers:")
                            self.listForType(type: .phone)
                        }
                        
                        if detectURLs {
                            Text("Urls:")
                            self.listForType(type: .url)
                        }
                    }.padding(.top, 10)
                }
                .padding()
                
                Spacer()
                
            }
            .frame(maxWidth: 250, maxHeight: .infinity)
        }.toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Load New Image") {
                    self.loadImage()
                }
                Button("Save Censored Image") {
                    self.saveImage()
                }
            }
        }.navigationTitle("Image Guard")
    }
    
    private func listForType(type: DataType) -> some View {
        ForEach($detectedData) { $item in
            if item.type == type {
                HStack {
                    Text(item.text)
                    Spacer()
                    Toggle("", isOn: $item.selected)
                        .labelsHidden().onChange(of: item.selected) {
                            self.updateImage()
                        }
                }
                .padding()
            }
        }
    }
    
    private func saveImage() {
        guard let image = self.blurredImage else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = ["png", "jpg", "jpeg"]
        savePanel.nameFieldStringValue = "blurred.png"  // Set the default name
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmapImageRep = NSBitmapImageRep(data: tiffData),
                   let data = bitmapImageRep.representation(using: .png, properties: [:]) {
                    do {
                        try data.write(to: url)
                        print("Image saved to \(url)")
                    } catch {
                        print("Failed to save image: \(error)")
                    }
                }
            }
        }
    }
    
    private func loadImage(from providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { (image, error) in
                    DispatchQueue.main.async {
                        self.droppedImage = image as? NSImage
                        self.detectSensitiveData()
                    }
                }
            }
        }
    }
    
    private func detectSensitiveData() {
        
        guard let image = self.droppedImage else { return }
        
        self.detectedData = []
        
        //        Data detector
        var types: NSTextCheckingResult.CheckingType = []
        if detectEmails {
            types.insert(.link)
        }
        if detectPhoneNumbers {
            types.insert(.phoneNumber)
        }
        if detectURLs {
            types.insert(.link)
        }
        if types.isEmpty {
            return
        }
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return
        }
        
        print("TRY TO DETECT \(image.size)")
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        let request = VNRecognizeTextRequest { request, error in
            if let results = request.results as? [VNRecognizedTextObservation] {
                
                detectedData = results.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string
                    
                    let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                    
                    for match in matches {
                        switch match.resultType {
                        case .link:
                            return SensitiveData(type: match.url!.absoluteString.contains("mailto:") ? .email : .url, selected: true, boundingBox: observation.boundingBox, text: match.url!.absoluteString)
                        case .phoneNumber:
                            return SensitiveData(type: .phone, selected: true, boundingBox: observation.boundingBox, text: match.phoneNumber!)
                        default:
                            return nil
                        }
                    }
                    
                    
                    return nil
                }
                
                self.updateImage()
            }
        }
        
        request.usesLanguageCorrection = false
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? requestHandler.perform([request])
    }
    
    private func loadImage() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["png", "jpg", "jpeg"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                if let nsImage = NSImage(contentsOf: url) {
                    self.droppedImage = nsImage
                    self.detectSensitiveData()
                }
            }
        }
    }
    
    private func updateImage() {
        DispatchQueue.main.async {
            self.blurredImage = self.coverImageRegions()
        }
    }
    
    func coverImageRegions() -> NSImage? {
        
        guard let image = self.droppedImage else {return nil}
        // Create a new NSImage instance based on the original image
        let newImage = NSImage(size: image.size)
        
        // Set up drawing context
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        
        // Draw original image
        image.draw(at: NSPoint.zero, from: NSRect.zero, operation: .copy, fraction: 1.0)
        
        // Set fill color to black
        NSColor.black.set()
        
        let boundingBoxes = self.detectedData.filter{ data in
            if (data.selected && (data.type == .email && detectEmails || data.type == .phone && detectPhoneNumbers || data.type == .url && detectURLs)) {
                return true
            }
            return false
        }.map { $0.boundingBox }
        
        
        // Draw black rectangles for each bounding box
        for boundingBox in boundingBoxes {
            // Convert bounding box from normalized coordinates to image coordinates
            let imageBoundingBox = VNImageRectForNormalizedRect(boundingBox, Int(image.size.width), Int(image.size.height))
            
            // Draw black rectangle
            NSBezierPath(rect: imageBoundingBox).fill()
        }
        
        // Return the modified image
        return newImage
    }
}
