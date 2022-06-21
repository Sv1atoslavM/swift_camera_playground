//
//  ViewController.swift
//  CameraPlayground
//
//  Created by Sviatoslav Moskva on 09.06.2022.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet var previewView: UIView!
    
    // Helps to transfer data between one or more device inputs like camera or microphone
    let captureSession = AVCaptureSession()
    // Helps to render the camera view finder in the ViewController
    var previewLayer: AVCaptureVideoPreviewLayer! = nil
    
    let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)

    var bufferSize: CGSize = .zero
    var detectionOverlay: CALayer! = nil
    
    
    override func viewDidAppear(_ animated: Bool) {
        captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        captureSession.stopRunning()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480
        
        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        } else {
            print("Could not add video device input to the session")
            captureSession.commitConfiguration()
            return
        }
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        
        if captureSession.canAddOutput(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            captureSession.addOutput(videoDataOutput)
        } else {
            print("Could not add video data output to the session")
            captureSession.commitConfiguration()
            return
        }
        
        let captureConnection = videoDataOutput.connection(with: .video)
        
        // Always process the frames
        captureConnection?.isEnabled = true
        do {
            try captureDevice.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions(captureDevice.activeFormat.formatDescription)
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            captureDevice.unlockForConfiguration()
        } catch {
            print(error)
        }
        
        captureSession.commitConfiguration()
        
        let bounds = previewView.layer.bounds
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
        view.layer.addSublayer(previewLayer)
        
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0, y: 0.0, width: bufferSize.width, height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        view.layer.addSublayer(detectionOverlay)
        
        updateLayerGeometry()
    }
    
    override func viewDidLayoutSubviews() {
        previewLayer?.frame = view.frame
        
        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = self.view.window?.windowScene?.interfaceOrientation.videoOrientation ?? .portrait
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3Tiny", withExtension: "mlmodelc") else {
            print("Incorrect model url")
            return
        }
        
        guard let visionModel = try? VNCoreMLModel(for: MLModel(contentsOf: modelURL)) else { return }
        
        let request = VNCoreMLRequest(model: visionModel) {
            (request, error) in
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
            
            DispatchQueue.main.async {
                
                self.detectionOverlay?.sublayers = nil // remove all the old recognized objects
                
                CATransaction.begin()
                CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
                
                for objectObservation in results {
                    // Select only the label with the highest confidence.
                    let topLabelObservation = objectObservation.labels[0]
                    let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(self.bufferSize.width), Int(self.bufferSize.height))
                    let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)
                    let textLayer = self.createTextSubLayerInBounds(objectBounds, identifier: topLabelObservation.identifier, confidence: topLabelObservation.confidence)
                    shapeLayer.addSublayer(textLayer)
                    self.detectionOverlay?.addSublayer(shapeLayer)
                }
                
                self.updateLayerGeometry()
                
                CATransaction.commit()
            }
        }
        
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }
    
    func updateLayerGeometry() {
        let bounds = previewView.layer.bounds
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
        var scale = fmax(xScale, yScale)
        
        if scale.isInfinite { scale = 1.0 }
        
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.name = "Found Object"
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.backgroundColor = UIColor.green.withAlphaComponent(0.2).cgColor
        shapeLayer.cornerRadius = 7
        return shapeLayer
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.foregroundColor = UIColor.black.cgColor
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
}

extension UIInterfaceOrientation {
    var videoOrientation: AVCaptureVideoOrientation? {
        switch self {
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeRight:
            return .landscapeRight
        case .landscapeLeft:
            return .landscapeLeft
        case .portrait:
            return .portrait
        default:
            return nil
        }
    }
}
