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


/// Общий сценарий: Выбираем фото с помощью OpalImagePickerController, хранящиеся в images фото во viewDidAppear() превращаем в объекты структуры UserPhoto, тут же предсказывая для каждого элемента что на картинке (можно попробовать запустить предсказания параллельно). Запускаем перерисовку таблицы

///TODO: Помимо распараллеливания предсказаний, можно не хранить фото после выбора, а только ссылки на них в память

struct UserPhoto {
    var image: UIImage
    var descriprions: Set<String>
    var groupNumber: Int
    var isLastInGroup: Bool
}

class MyViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, OpalImagePickerControllerDelegate {
    
    //MARK: Outlets

    let model = MobileNet()
    typealias Prediction = (String, Double)

    var userPhotos = [UserPhoto]()
    var images = [CIImage]()
    var consumedTimes = [Double]()
    var groupNumber = 0
    var needToUpdate = false

    @IBOutlet var tableView: UITableView!
    @IBOutlet weak var totalObjects: UILabel!
    @IBOutlet weak var timeDifference: UILabel!
    @IBOutlet weak var currentStatusLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    //MARK: Main
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        currentStatusLabel.text = "Loading photos..."
        activityIndicator.startAnimating()
        
        if needToUpdate {
            // Populate TableView with data
            for image in images {
                let exactDate = Date()
                currentStatusLabel.text = "Loading photos..."
                let predictions = predictUsingCoreML(image: UIImage(ciImage: image), predictionsCount: 2)
                
                userPhotos.append(
                    UserPhoto(
                        image: UIImage(ciImage: image),
                        descriprions: convertPredictionsToSet(predictions: predictions),
                        groupNumber: 0,
                        isLastInGroup: false))
                let endDate = Date().timeIntervalSince(exactDate)
                consumedTimes.append(endDate)
                let avgTime = Double(round(1000*calculateAverageTime(arr: consumedTimes))/1000)
                timeDifference.text = String(avgTime) + " sec per image"
            }
            
            // Deciding duplicates
            let groupsOfSimilarPhotos = getGroupsOfSimilarPhotos(userPhotos)
            userPhotos = [UserPhoto]()
            // Каждому элементу присваиваем групповой индекс
            for group in groupsOfSimilarPhotos {
                for i in 0..<group.count {
                    var copyOfPhoto = group[i]
                    copyOfPhoto.groupNumber = groupNumber
                    if i == group.count-1 {
                        copyOfPhoto.isLastInGroup = true
                    }
                    userPhotos.append(copyOfPhoto)
                }
                groupNumber += 1
            }
            
            tableView.reloadData()
            needToUpdate = false
        }
        
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
        return userPhotos.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell:MyCustomCell = tableView.dequeueReusableCell(withIdentifier: "myCell") as! MyCustomCell
        let currentItem = userPhotos[indexPath.row]
        cell.myImageView.image = currentItem.image
        if currentItem.groupNumber % 2 == 0 {
            cell.backgroundColor = UIColor.white
        } else {
            cell.backgroundColor = UIColor.init(displayP3Red: 205/255, green: 205/255, blue: 205/255, alpha: 1)
        }
        cell.myCellLabel?.text = currentItem.descriprions.count == 0 ? "Loading..." : currentItem.descriprions.joined(separator: ", ")
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
        needToUpdate = true
        var index = 0

        //Refresh data
        userPhotos = [UserPhoto]()
        images = [CIImage]()
        
        for asset in assets {
            images.append(getAssetThumbnail(asset: asset).0)
            totalObjects.text = "Object \(index+1) / \(assets.count)"
            index += 1
        }
        tableView.reloadData()
        presentedViewController?.dismiss(animated: true, completion: nil)
    }
    
    
    //MARK: Supp funcs
    
    private func getGroupsOfSimilarPhotos(_ userPhotos: [UserPhoto]) -> [[UserPhoto]] {
        var photosToCheck = userPhotos
        var similars = [[UserPhoto]]()
        while let leftHandPhoto = photosToCheck.first {
            var photosToIterate = photosToCheck
            photosToIterate.removeFirst()
            var hasIntersections = [UserPhoto]()
            while let rightHandPhoto = photosToIterate.first {
                if leftHandPhoto.descriprions.intersection(rightHandPhoto.descriprions).count > 0 {
                    if hasIntersections.isEmpty {
                        hasIntersections.append(leftHandPhoto)
                    }
                    hasIntersections.append(rightHandPhoto)
                }
                photosToIterate.removeFirst()
            }
            similars = hasIntersections.isEmpty ? similars: similars + [hasIntersections]
            photosToCheck.removeFirst()
        }
        print(similars)
        return similars
    }
    
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
