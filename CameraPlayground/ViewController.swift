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
    @IBOutlet weak var messageLabel: UILabel!
    
    // Helps to transfer data between one or more device inputs like camera or microphone
    let captureSession = AVCaptureSession()
    // Helps to render the camera view finder in the ViewController
    var previewLayer: AVCaptureVideoPreviewLayer!

    var bufferSize: CGSize = .zero
    var rootLayer: CALayer! = nil
    
    
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
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
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
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        rootLayer = previewView.layer
        previewLayer.frame = rootLayer.bounds
        view.layer.addSublayer(previewLayer)
        view.addSubview(messageLabel)
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
        guard let cvPixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let model = try? VNCoreMLModel(for: Resnet50(configuration: .init()).model) else { return }
        
        let request = VNCoreMLRequest(model: model) {
            (request, error) in
            guard let results = request.results as? [VNClassificationObservation] else { return }
            guard let firstObservation = results.first else { return }
            
            let identifier = firstObservation.identifier
            let confidence = (firstObservation.confidence * 100).rounded()
            
            DispatchQueue.main.async {
                self.messageLabel.text = "\(identifier) - \(confidence)%"
            }
        }
        
        try? VNImageRequestHandler(cvPixelBuffer: cvPixelBuffer, options: [:]).perform([request])
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
