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
        
        let request = VNDetectHumanBodyPoseRequest {
            (request, error) in
            
            guard let results = request.results as? [VNHumanBodyPoseObservation] else { return }
            
            DispatchQueue.main.async {
                
                self.detectionOverlay?.sublayers = nil // remove all the old recognized objects
                                
                CATransaction.begin()
                CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
                
                for poseObservation in results {
                    guard let recognizedPoints = try? poseObservation.recognizedPoints(.all) else { return }
                        
                    let jointNames: [VNHumanBodyPoseObservation.JointName] = [
                        .root,
                        .neck,
                        .leftShoulder,
                        .rightShoulder,
                        .leftHip,
                        .rightHip,
                        .leftAnkle,
                        .rightAnkle,
                        .leftHip,
                        .rightHip,
                        .leftKnee,
                        .rightKnee,
                        .leftElbow,
                        .rightElbow,
                        .leftWrist,
                        .rightWrist,
                    ]
                    
                    // Retrieve the CGPoints containing the normalized X and Y coordinates.
                    let imagePoints: [CGPoint] = jointNames.compactMap {
                        guard let point = recognizedPoints[$0], point.confidence > 0 else { return nil }
                            
                        // Translate the point from normalized-coordinates to image coordinates.
                        return VNImagePointForNormalizedPoint(point.location, Int(self.bufferSize.width), Int(self.bufferSize.height))
                    }
                    
                    // Draw the points onscreen.
                    for point in imagePoints {
                        let pointView = self.createPoint(point: point)
                        self.detectionOverlay?.addSublayer(pointView)
                    }
                }
                
                self.updateLayerGeometry()
                                
                CATransaction.commit()
            }
        }
        
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }
    
    func createPoint(point: CGPoint) -> CALayer {
        let dimention = 8.0
        let bounds = CGRect(x: point.x, y: point.y, width: dimention, height: dimention)
        let pointLayer = CALayer()
        pointLayer.name = "Point"
        pointLayer.bounds = bounds
        pointLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        pointLayer.backgroundColor = CGColor(red: 1, green: 0, blue: 0, alpha: 0.75)
        pointLayer.cornerRadius = dimention / 2
        return pointLayer
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
