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

struct UserPhoto {
    var image: UIImage
    var descriprions: Set<String>
    var isDuplicated: Bool
}


class MyViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, OpalImagePickerControllerDelegate {
    
    let model = MobileNet()
    typealias Prediction = (String, Double)

    var userPhotos = [UserPhoto]()
    var images = [CIImage]()
    var totalCells = 0
    var consumedTimes = [Double]()

    @IBOutlet var tableView: UITableView!
    @IBOutlet weak var totalObjects: UILabel!
    @IBOutlet weak var timeDifference: UILabel!
    @IBOutlet weak var currentStatusLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        currentStatusLabel.text = "Loading photos..."
        activityIndicator.startAnimating()
        
        
        // Populate TableView with data
        for image in images {
            let exactDate = Date()
            currentStatusLabel.text = "Loading photos..."
            let predictions = predictUsingCoreML(image: UIImage(ciImage: image), predictionsCount: 2)
            
            userPhotos.append(
                UserPhoto(
                    image: UIImage(ciImage: image),
                    descriprions: convertPredictionsToSet(predictions: predictions),
                    isDuplicated: false))
            let endDate = Date().timeIntervalSince(exactDate)
            consumedTimes.append(endDate)
            timeDifference.text = String(calculateAverageTime(arr: consumedTimes))
        }
        // Deciding duplicates
        userPhotos.sort{ $0.descriprions.intersection($1.descriprions).count > 2 }
        
        currentStatusLabel.text = "Rendering"
        tableView.reloadData()
        currentStatusLabel.text = ((images.count > 0) ? "Done" : "Waiting for photos")
        activityIndicator.stopAnimating()
    }
    
    //MARK: ML
    
    /*
     This uses the Core ML-generated MobileNet class directly.
     Downside of this method is that we need to convert the UIImage to a
     CVPixelBuffer object ourselves. Core ML does not resize the image for
     you, so it needs to be 224x224 because that's what the model expects.
     */
    func predictUsingCoreML(image: UIImage, predictionsCount: Int) -> [Prediction] {
        if let pixelBuffer = image.pixelBuffer(width: 224, height: 224),
            let prediction = try? model.prediction(image: pixelBuffer) {
            return top(predictionsCount, prediction.classLabelProbs)
        }
        return [Prediction]()
    }
    
    
    //MARK: TableViewDelegate
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return totalCells
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell:MyCustomCell = self.tableView.dequeueReusableCell(withIdentifier: "myCell") as! MyCustomCell
        if self.userPhotos.count > indexPath.row {
            let currentItem = self.userPhotos[indexPath.row]
            cell.myImageView.image = currentItem.image
            cell.isDuplicatedLabel.text = currentItem.isDuplicated ? "🎏" : ""
            cell.myCellLabel?.text = currentItem.descriprions.count == 0 ?
                "Loading..." :
                currentItem.descriprions.joined(separator: ", ")
        } else {
            cell.myImageView.image = UIImage(named: "loading-bar")
            cell.isDuplicatedLabel.text = ""
            cell.myCellLabel?.text = "Loading..."
        }
        
        return cell
    }
    
    //MARK: Image Picker
    
    @IBAction func pickImagesPressed(_ sender: Any) {
        let imagePicker = OpalImagePickerController()
        imagePicker.allowedMediaTypes = Set([PHAssetMediaType.image])
        imagePicker.maximumSelectionsAllowed = 100
        imagePicker.imagePickerDelegate = self
        present(imagePicker, animated: true, completion: nil)
    }
    
    func imagePicker(_ picker: OpalImagePickerController, didFinishPickingAssets assets: [PHAsset]) {
        var index = 0
        print("Found \(assets.count) assets")
        self.totalCells = assets.count
        
        //Refresh data
        userPhotos = [UserPhoto]()
        images = [CIImage]()
        
        for asset in assets {
            images.append(getAssetThumbnail(asset: asset).0)
            self.totalObjects.text = "Object \(index+1) / \(assets.count)"
            index += 1
        }
        tableView.reloadData()
        presentedViewController?.dismiss(animated: true, completion: nil)
    }
    
    
    //MARK: Supp funcs
    
    func calculateAverageTime(arr: [Double]) -> Double {
        var total = 0.0
        for value in arr {
            total += value
        }
        if arr.count != 0 {
            return total/Double(arr.count)
        } else {
            return 0;
        }
        
    }
    
    func convertPredictionsToSet(predictions: [Prediction]) -> Set<String> {
        var someSet = Set<String>()
        for predict in predictions {
            someSet.insert(predict.0)
        }
        return someSet
    }
    
    func show(results: [Prediction]) -> String {
        var s: [String] = []
        for (i, pred) in results.enumerated() {
            s.append(String(format: "%d: %@ (%3.2f%%)", i + 1, pred.0, pred.1 * 100))
        }
        return s.joined(separator: ", "/*"\n\n"*/)
    }
    
    func top(_ k: Int, _ prob: [String: Double]) -> [Prediction] {
        precondition(k <= prob.count)
        
        return Array(prob.map { x in (x.key, x.value) }
            .sorted(by: { a, b -> Bool in a.1 > b.1 })
            .prefix(through: k - 1))
    }
    
    func getAssetThumbnail(asset: PHAsset) -> (CIImage, Int) {
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        var resultImage = CIImage()
        var orientationRaw = 0
        option.isSynchronous = true
        manager.requestImageData(for: asset, options: option) { (data, str, orient, someUselessVariable) in
            resultImage = CIImage(data: data ?? Data()) ?? CIImage()
            orientationRaw = orient.rawValue
        }
        return (resultImage, orientationRaw)
    }
    
}


class MyCustomCell: UITableViewCell {
    @IBOutlet weak var myImageView: UIImageView!
    @IBOutlet weak var myCellLabel: UILabel!
    @IBOutlet weak var isDuplicatedLabel: UILabel!
}
