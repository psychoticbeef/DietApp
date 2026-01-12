//
//  NutritionScannerView.swift
//  Haesslon
//
//  Created by Daniel Arndt on 12.01.26.
//

import SwiftUI
import Vision
import VisionKit

struct NutritionScannerView: UIViewControllerRepresentable {
    var onCompletion: (String) -> Void
    var onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: NutritionScannerView
        
        init(_ parent: NutritionScannerView) {
            self.parent = parent
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Process the first page found
            if scan.pageCount > 0 {
                let image = scan.imageOfPage(at: 0)
                processImage(image)
            } else {
                parent.onCancel()
            }
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("Scanner error: \(error)")
            parent.onCancel()
        }
        
        private func processImage(_ image: UIImage) {
            guard let cgImage = image.cgImage else {
                parent.onCancel()
                return
            }
            
            let request = VNRecognizeTextRequest { [weak self] request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    self?.parent.onCancel()
                    return
                }
                
                // Combine all text into one block, preserving newlines
                let fullText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                
                DispatchQueue.main.async {
                    // --- DEBUG: Copy to Clipboard ---
                    UIPasteboard.general.string = fullText
                    print("--- DEBUG OCR OUTPUT ---\n\(fullText)\n------------------------")
                    // --------------------------------
                    
                    self?.parent.onCompletion(fullText)
                }
            }
            
            // "Accurate" is slower but necessary for dense tables and curved surfaces
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Added German priority for accurate umlaut/comma handling
            request.recognitionLanguages = ["de-DE", "en-US"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    print("Failed to perform OCR: \(error)")
                    DispatchQueue.main.async {
                        self.parent.onCancel()
                    }
                }
            }
        }
    }
}

// Wrapper to match previous usage
struct ScannerSheet: View {
    @Environment(\.dismiss) var dismiss
    var onResult: (String) -> Void
    
    var body: some View {
        NutritionScannerView(
            onCompletion: { text in
                onResult(text)
                dismiss()
            },
            onCancel: { dismiss() }
        )
        .ignoresSafeArea()
    }
}
