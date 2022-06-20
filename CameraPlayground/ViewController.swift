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
    lazy var previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)

    
    override func viewDidAppear(_ animated: Bool) {
        captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        captureSession.stopRunning()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        
        captureSession.sessionPreset = .photo
        captureSession.addInput(input)
        
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.frame
        view.layer.addSublayer(previewLayer)
        view.addSubview(messageLabel)
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(videoDataOutput)
    }
    
    override func viewDidLayoutSubviews() {
        previewLayer.frame = view.frame
        
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
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
