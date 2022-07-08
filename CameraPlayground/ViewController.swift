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
    
    @IBOutlet weak var previewView: UIView!
    
    // Helps to transfer data between one or more device inputs like camera or microphone
    let captureSession = AVCaptureSession()
    // Helps to render the camera view finder in the ViewController
    var previewLayer: AVCaptureVideoPreviewLayer! = nil
    
    let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)

    var rootView: UIView! = nil
    var detectionOverlay: CALayer! = nil
    var inputImageOrientation: CGImagePropertyOrientation! = .up
    var bufferSize: CGSize = .zero
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        captureSession.stopRunning()
        
        super.viewDidDisappear(animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        rootView = view
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
            videoDataOutput.connection(with: .video)?.isEnabled = true // always process the frames
            captureSession.addOutput(videoDataOutput)
        } else {
            print("Could not add video data output to the session")
            captureSession.commitConfiguration()
            return
        }
        
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
        previewLayer.name = "PreviewLayer"
        previewLayer.videoGravity = .resizeAspectFill
        previewView.layer.addSublayer(previewLayer)
        
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(origin: .zero, size: bufferSize)
        previewView.layer.addSublayer(detectionOverlay)
    }
    
    override func viewDidLayoutSubviews() {
        
        let interfaceOrientation = rootView.window?.windowScene?.interfaceOrientation
        
        previewLayer.frame = rootView.frame
        
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            
            switch interfaceOrientation {
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
                inputImageOrientation = .down
            case .landscapeRight:
                connection.videoOrientation = .landscapeRight
                inputImageOrientation = .left
            case .landscapeLeft:
                connection.videoOrientation = .landscapeLeft
                inputImageOrientation = .right
            case .portrait:
                connection.videoOrientation = .portrait
                inputImageOrientation = .up
            default:
                connection.videoOrientation = .portrait
                inputImageOrientation = .up
            }
        }
        
        updateLayerGeometry()
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let detectHumanBodyPoseRequest = VNDetectHumanBodyPoseRequest {
            (request, error) in
            
            guard let results = request.results as? [VNHumanBodyPoseObservation] else { return }
            
            DispatchQueue.main.async {
                
                CATransaction.begin()
                CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
                
                self.detectionOverlay?.sublayers = nil // remove all the old recognized objects
                
                for poseObservation in results {
                    guard let recognizedPoints = try? poseObservation.recognizedPoints(.all) else { return }
                    
                    // Retrieve the CGPoints containing the normalized X and Y coordinates.
                    let imagePoints: [CGPoint] = recognizedPoints.values.compactMap {
                        // Translate the point from normalized-coordinates to image coordinates.
                        $0.confidence > 0 ? VNImagePointForNormalizedPoint($0.location, Int(self.bufferSize.width), Int(self.bufferSize.height)) : nil
                    }
                    
                    // Draw the points onscreen.
                    for point in imagePoints {
                        let pointView = self.createPoint(point: point)
                        self.detectionOverlay?.addSublayer(pointView)
                    }
                    
                    // Draw a rectangle by points
                    let rectView = self.createRectangle(points: imagePoints)
                    self.detectionOverlay?.addSublayer(rectView)
                }
                
                self.updateLayerGeometry()
                                
                CATransaction.commit()
            }
        }
        
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: inputImageOrientation, options: [:]).perform([detectHumanBodyPoseRequest])
    }
    
    func createPoint(point: CGPoint) -> CALayer {
        let dimention = 4.0
        let bounds = CGRect(x: point.x, y: point.y, width: dimention, height: dimention)
        let pointLayer = CALayer()
        pointLayer.name = "Point"
        pointLayer.bounds = bounds
        pointLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        pointLayer.backgroundColor = CGColor(red: 1, green: 0, blue: 0, alpha: 0.75)
        pointLayer.cornerRadius = dimention / 2
        return pointLayer
    }
    
    func createRectangle(points: [CGPoint]) -> CALayer {
        let coordX = points.map{$0.x}
        let coordY = points.map{$0.y}
        let begin = CGPoint(x: coordX.min()!, y: coordY.min()!)
        let end = CGPoint(x: coordX.max()!, y: coordY.max()!)
        let bounds = CGRect(origin: begin, size: CGSize(width: end.x - begin.x, height: end.y - begin.y))
        let pointLayer = CALayer()
        pointLayer.name = "Shape"
        pointLayer.bounds = bounds
        pointLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        pointLayer.backgroundColor = CGColor(red: 0, green: 1, blue: 0, alpha: 0.25)
        return pointLayer
    }
    
    func updateLayerGeometry() {
        let bounds = rootView.layer.bounds
        let xScale: CGFloat = bounds.width / bufferSize.height
        let yScale: CGFloat = bounds.height / bufferSize.width
        
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
