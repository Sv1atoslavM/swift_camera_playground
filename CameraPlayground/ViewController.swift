//
//  ViewController.swift
//  CameraPlayground
//
//  Created by Sviatoslav Moskva on 09.06.2022.
//

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate {
    
    @IBOutlet var previewView: UIView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var messageLabel: UILabel!
    
    // Helps us to transfer data between one or more device inputs like camera or microphone
    var captureSession: AVCaptureSession?
    // Helps to render the camera view finder in our ViewController
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    // Helps us to snap a photo from our capture session
    var capturePhotoOutput: AVCapturePhotoOutput?
    
    var frameView: UIView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let device = AVCaptureDevice.default(for: .video)
        
        do {
            let input = try AVCaptureDeviceInput(device: device!)
            
            captureSession = AVCaptureSession()
            captureSession?.addInput(input)
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            videoPreviewLayer?.videoGravity = .resizeAspectFill
            videoPreviewLayer?.frame = view.bounds
            previewView.layer.addSublayer(videoPreviewLayer!)
            capturePhotoOutput = AVCapturePhotoOutput()
            capturePhotoOutput?.isHighResolutionCaptureEnabled = true
            captureSession?.addOutput(capturePhotoOutput!)
            
            let captureMetadataOutput = AVCaptureMetadataOutput()
            
            captureSession?.addOutput(captureMetadataOutput)
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            captureMetadataOutput.metadataObjectTypes = [.qr, .face]
            
            // Start video capture
            captureSession?.startRunning()
            
            messageLabel.isHidden = true
            frameView = UIView()
                        
            if let frameView = frameView {
                frameView.layer.borderColor = UIColor.green.cgColor
                frameView.layer.borderWidth = 2
                view.addSubview(frameView)
                view.bringSubviewToFront(frameView)
            }
        } catch {
            print(error)
        }
    }
    
    override func viewDidLayoutSubviews() {
            videoPreviewLayer?.frame = view.bounds
        
            if let previewLayer = videoPreviewLayer, (previewLayer.connection?.isVideoOrientationSupported)! {
                previewLayer.connection?.videoOrientation = self.view.window?.windowScene?.interfaceOrientation.videoOrientation ?? .portrait
            }
        }
    
    @IBAction func onPhotoPressed(_ sender: Any) {
        if let capturePhotoOutput = capturePhotoOutput {
            let photoSettings = AVCapturePhotoSettings()
            
            photoSettings.isHighResolutionPhotoEnabled = true
            photoSettings.photoQualityPrioritization = .balanced
            photoSettings.flashMode = .auto
            capturePhotoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else {
            print("Fail to capture photo: \(String(describing: error))")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            print("Fail to convert pixel buffer")
            return
        }
        
        guard let capturedImage = UIImage.init(data: imageData, scale: 1.0) else {
            print("Fail to convert image data to UIImage")
            return
        }
        
        let width = capturedImage.size.width
        let height = capturedImage.size.height
        let origin = CGPoint(x: (width - height) / 2, y: (height - height) / 2)
        let size = CGSize(width: height, height: height)
        
        guard let imageRef = capturedImage.cgImage?.cropping(to: CGRect(origin: origin, size: size)) else {
            print("Fail to crop image")
            return
        }
        
        let imageToSave = UIImage(cgImage: imageRef, scale: 1.0, orientation: .down)
        
        UIImageWriteToSavedPhotosAlbum(imageToSave, nil, nil, nil)
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        if metadataObjects.count == 0 {
            frameView?.frame = CGRect.zero
            messageLabel.isHidden = true
            return
        }
        
        let metadataObj = metadataObjects[0]
        
        switch metadataObj.type {
        case .qr:
            let metadataObj = metadataObj as! AVMetadataMachineReadableCodeObject
            
            if let qr = videoPreviewLayer?.transformedMetadataObject(for: metadataObj) {
                frameView?.frame = qr.bounds
                
                if metadataObj.stringValue != nil {
                    messageLabel.isHidden = false
                    messageLabel.text = metadataObj.stringValue
                }
            }
            
        case .face:
            let metadataObj = metadataObj as! AVMetadataFaceObject
            
            if let face = videoPreviewLayer?.transformedMetadataObject(for: metadataObj) {
                frameView?.frame = face.bounds
            }
            
        default:
            
            return
        }
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
