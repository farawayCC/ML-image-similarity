//
//  ViewController.swift
//  TestingMLAllImages
//
//  Created by Alexey Klygin on 14/01/2019.
//  Copyright © 2019 Alexey Klygin. All rights reserved.
//

import UIKit
import CoreML
import Vision
import ImageIO
import Photos
import OpalImagePicker

//По идее мы только идентификаторы распознанные можем запоминать и по их номерам потом говорить, что является дубликатом а что нет
class MyViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, OpalImagePickerControllerDelegate {
    
    var photos = [CIImage]()
    var classificationsConfidence = [Float]()
    var classificationsIdentifier = [String]()
    var isDuplicatedArr = [Bool]()
    
    let cellReuseIdentifier = "myCell"
    
    @IBOutlet var tableView: UITableView!
    @IBOutlet weak var totalObjects: UILabel!
    @IBOutlet weak var timeDifference: UILabel!
    
    var startDate = Date()
    var endDate = Date()
    var totalCells = 0
    var loadedCells = 0
    
    var classifiedAssets = [ClassifiedAsset]()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self
        tableView.dataSource = self
        
//        PHPhotoLibrary.requestAuthorization { status in
//            switch status {
//
//            case .authorized:
//                let fetchOptions = PHFetchOptions()
//                let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
//                print("Found \(allPhotos.count) assets")
//                self.totalCells = allPhotos.count
//                allPhotos.enumerateObjects({ (asset, index, stop) in
//                    let myCiImage = self.getAssetThumbnail(asset: asset).0
//                    self.photos.append(myCiImage)
//
//                    self.updateClassifications(
//                        for: myCiImage,
//                        orientation: self.getAssetThumbnail(asset: asset).1)
//                    self.totalObjects.text = "Object \(index+1) / \(allPhotos.count)"
//                })
//                print("Fetch images from library completed")
//
//            case .denied, .restricted:
//                print("Not allowed")
//            case .notDetermined:
//                print("Not determined yet")
//            }
//        }
    }
    
    //MARK: OpalImagePickerDelegate
    
    func imagePicker(_ picker: OpalImagePickerController, didFinishPickingAssets assets: [PHAsset]) {
        var index = 0
        print("Found \(assets.count) assets")
        self.totalCells = assets.count
        
        photos = [CIImage]()
        classificationsConfidence = [Float]()
        classificationsIdentifier = [String]()
        isDuplicatedArr = [Bool]()
        
        for asset in assets {
            let myCiImage = self.getAssetThumbnail(asset: asset).0
            self.photos.append(myCiImage)
            
            startDate = Date()
            self.updateClassifications(
                for: myCiImage,
                orientation: self.getAssetThumbnail(asset: asset).1)
            self.totalObjects.text = "Object \(index+1) / \(assets.count)"
            print("Fetch images from library completed")
            index += 1
        }
        startDate = Date()
        presentedViewController?.dismiss(animated: true, completion: nil)

    }
    
    @IBAction func pickImagesPressed(_ sender: Any) {
        let imagePicker = OpalImagePickerController()
        imagePicker.allowedMediaTypes = Set([PHAssetMediaType.image])
        imagePicker.maximumSelectionsAllowed = 5
        imagePicker.imagePickerDelegate = self
        present(imagePicker, animated: true, completion: nil)
    }
    
    //MARK: TableViewDelegate
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return totalCells
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell:MyCustomCell = self.tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier) as! MyCustomCell
        
        cell.myImageView.image = UIImage(ciImage: self.photos[indexPath.row])
        cell.isDuplicatedLabel.text = self.isDuplicatedArr[indexPath.row] ? "🎏" : ""
        cell.myCellLabel?.text =
            String(format: "  (%.2f) %@", classificationsConfidence[indexPath.row], classificationsIdentifier[indexPath.row])
        
        return cell
    }
    
    
    //MARK: ML
    lazy var classificationRequest: VNCoreMLRequest = {
        do {
            print("Start get model: \(Date())")
            let model = try VNCoreMLModel(for: MobileNet().model)
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                self?.processClassifications(for: request, error: error)
            })
            request.imageCropAndScaleOption = .centerCrop
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    func updateClassifications(for ciImage: CIImage, orientation: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(
                ciImage: ciImage,
                orientation: CGImagePropertyOrientation(rawValue: UInt32(orientation)) ?? CGImagePropertyOrientation.up)
            do {
                try handler.perform([self.classificationRequest])
            } catch {
                /*
                 This handler catches general image processing errors. The `classificationRequest`'s
                 completion handler `processClassifications(_:error:)` catches errors specific
                 to processing that request.
                 */
                print("Failed to perform classification.\n\(error.localizedDescription)")
            }
        }
    }
    
    
    /// Updates the UI with the results of the classification.
    /// - Tag: ProcessClassifications
    func processClassifications(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let results = request.results else {
                print("Unable to classify image.\n\(error!.localizedDescription)  \(Date())")
                return
            }
            // The `results` will always be `VNClassificationObservation`s, as specified by the Core ML model in this project.
            let classifications = results as! [VNClassificationObservation]
            
            if classifications.isEmpty {
                print("Nothing recognized. \(Date())")
            } else {
                // Display top classifications ranked by confidence in the UI.
                let topClassifications = classifications.prefix(2)
                topClassifications.map { classification in
                    self.classificationsConfidence.append(classification.confidence)
                    self.classificationsIdentifier.append(classification.identifier)
                }
                
                self.endDate = Date()
                let diffTime = Float(self.endDate.timeIntervalSince(self.startDate))
                
                self.timeDifference.text = "Time taken: \((diffTime*10).rounded()/10)"
            }
        }
        
        //When all classification ended
        decideDuplicatePhotos()
        tableView.reloadData()
    }
    
    //MARK: Supp funcs
    
    func getAssetThumbnail(asset: PHAsset) -> (CIImage, Int) {
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        var resultImage = CIImage()
        var orientationRaw = 0
        option.isSynchronous = true
        manager.requestImageData(for: asset, options: option) { (data, str, orient, someuseless) in
            resultImage = CIImage(data: data ?? Data()) ?? CIImage()
            orientationRaw = orient.rawValue
            self.loadedCells += 1
        }
//        manager.requestImage(for: asset, targetSize: CGSize(width: 100, height: 100), contentMode: .aspectFit, options: option, resultHandler: {(result, info)->Void in
//            resultImage = CIImage(image: result ?? UIImage()) ?? CIImage()
//            orientationRaw = 0 //default
//            self.loadedCells += 1
//        })
        return (resultImage, orientationRaw)
    }

    func populateClassifiedAssets(from assets: [PHAsset]) -> [CIImage] {
        var ciImages = [CIImage]()
        for asset in assets {
            ciImages.append(getAssetThumbnail(asset: asset).0)
        }
        return ciImages
    }
    
    func decideDuplicatePhotos() {
        //TODO
        for _ in photos {
            isDuplicatedArr.append(true)
        }
        
    }

}


class MyCustomCell: UITableViewCell {
    @IBOutlet weak var myImageView: UIImageView!
    @IBOutlet weak var myCellLabel: UILabel!
    @IBOutlet weak var isDuplicatedLabel: UILabel!
}


struct ClassifiedAsset {
    var identifier = Int()
    var confidence = Float()
    var image = UIImage()
    var isDuplicated = false
}
