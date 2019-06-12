// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke
import DFCache

protocol ImagePipelineSettingsViewControllerDelegate: class {
    func imagePipelineSettingsViewController(_ vc: ImagePipelineSettingsViewController, didFinishWithConfiguration configuration: ImagePipeline.Configuration)
}

final class ImagePipelineSettingsViewController: UITableViewController {
    var configuration: ImagePipeline.Configuration! {
        didSet {
            guard isViewLoaded else { return }
            reload()
        }
    }

    weak var delegate: ImagePipelineSettingsViewControllerDelegate?

    @IBOutlet weak var optionDecompressionEnabledSwitch: UISwitch!
    @IBOutlet weak var optionDeduplicationEnabledSwitch: UISwitch!
    @IBOutlet weak var optionResumableDataEnabledSwitch: UISwitch!
    @IBOutlet weak var optionRateLimiterEnabledSwitch: UISwitch!
    @IBOutlet weak var optionProgressiveDecodingEnabledSwitch: UISwitch!

    @IBOutlet weak var memoryCacheEnabledSwitch: UISwitch!
    @IBOutlet weak var memoryCacheButtonClear: UIButton!
    @IBOutlet weak var memoryCacheTotalCost: UILabel!
    @IBOutlet weak var memoryCacheTotalCount: UILabel!

    @IBOutlet weak var urlCacheEnabledSwitch: UISwitch!
    @IBOutlet weak var urlCacheDetailsLabel: UILabel!
    @IBOutlet weak var urlCacheDataUsageLabel: UILabel!
    @IBOutlet weak var urlCacheMemoryUsageLabel: UILabel!
    @IBOutlet weak var urlCacheButtonClear: UIButton!

    @IBOutlet weak var dataCacheTitle: UILabel!
    @IBOutlet weak var dataCacheEnabledSwitch: UISwitch!
    @IBOutlet weak var dataCacheDataUsageCell: UITableViewCell!
    @IBOutlet weak var dataCacheTotalCountCell: UITableViewCell!
    @IBOutlet weak var dataCacheForOriginalImagesEnabledSwitch: UISwitch!
    @IBOutlet weak var dataCacheForProcessedImagesEnabledSwitch: UISwitch!
    @IBOutlet weak var dataCacheButtonClear: UIButton!

    @IBOutlet weak var queueDataLoadingValueLabel: UILabel!
    @IBOutlet weak var queueDataLoadingStepper: UIStepper!
    @IBOutlet weak var queueDataCachingValueLabel: UILabel!
    @IBOutlet weak var queueDataCachingStepper: UIStepper!
    @IBOutlet weak var queueDecodingValueLabel: UILabel!
    @IBOutlet weak var queueDecodingStepper: UIStepper!
    @IBOutlet weak var queueEncodingValueLabel: UILabel!
    @IBOutlet weak var queueEncodingStepper: UIStepper!
    @IBOutlet weak var queueProcessingValueLabel: UILabel!
    @IBOutlet weak var queueProcessingStepper: UIStepper!
    @IBOutlet weak var queueDecompressionValueLabel: UILabel!
    @IBOutlet weak var queueDecompressionStepper: UIStepper!

    static func show(from presentingViewController: UIViewController & ImagePipelineSettingsViewControllerDelegate, pipeline: ImagePipeline) {
        let navigationVC = UIStoryboard(name: "ImagePipelineSettingsViewController", bundle: nil).instantiateInitialViewController() as! UINavigationController
        let settingsVC = navigationVC.viewControllers[0] as! ImagePipelineSettingsViewController
        settingsVC.configuration = pipeline.configuration
        settingsVC.delegate = presentingViewController
        presentingViewController.present(navigationVC, animated: true, completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        reload()
        reloadDataCache()
        reloadURLCache()
    }

    private func reload() {
        optionDecompressionEnabledSwitch.isOn = configuration.isDecompressionEnabled
        optionDeduplicationEnabledSwitch.isOn = configuration.isDeduplicationEnabled
        optionResumableDataEnabledSwitch.isOn = configuration.isResumableDataEnabled
        optionRateLimiterEnabledSwitch.isOn = configuration.isRateLimiterEnabled
        optionProgressiveDecodingEnabledSwitch.isOn = configuration.isProgressiveDecodingEnabled

        memoryCacheEnabledSwitch.isOn = configuration.imageCache != nil
        memoryCacheButtonClear.isEnabled = configuration.imageCache != nil
        if let imageCache = configuration.imageCache as? ImageCache {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            memoryCacheTotalCost.text = "\(formatter.string(fromByteCount: Int64(imageCache.totalCost))) / \(formatter.string(fromByteCount: Int64(imageCache.costLimit)))"
            memoryCacheTotalCount.text = "\(imageCache.totalCount) / \(imageCache.countLimit == Int.max ? "Unlimited" : "\(imageCache.countLimit)")"
        } else {
            memoryCacheTotalCost.text = "Disabled"
            memoryCacheTotalCount.text = "Disabled"
        }

        urlCacheDetailsLabel.text = "Native URL HTTP cache used by URLSession"
        if let dataLoader = configuration.dataLoader as? DataLoader {
            let urlCache = dataLoader.session.configuration.urlCache
            urlCacheEnabledSwitch.isOn = urlCache != nil
            urlCacheButtonClear.isEnabled = urlCache != nil
        } else if let dataLoader = configuration.dataLoader as? AlamofireDataLoader {
            let urlCache = dataLoader.manager.session.configuration.urlCache
            urlCacheEnabledSwitch.isOn = urlCache != nil
            urlCacheEnabledSwitch.isEnabled = false // Not supported
            urlCacheButtonClear.isEnabled = urlCache != nil
            urlCacheDetailsLabel.text = "Alamofire is used, some settings are disabled"
        } else {
            urlCacheEnabledSwitch.isEnabled = false
            urlCacheButtonClear.isEnabled = false
            urlCacheDataUsageLabel.text = "Unknown"
            urlCacheMemoryUsageLabel.text = "Unknown"
            urlCacheDetailsLabel.text = "Settings disabled – unknown data loader is used"
        }

        dataCacheTitle.text = "Data Cache"
        dataCacheEnabledSwitch.isOn = configuration.dataCache != nil
        dataCacheButtonClear.isEnabled = configuration.dataCache != nil
        dataCacheForOriginalImagesEnabledSwitch.isEnabled = configuration.dataCache != nil
        dataCacheForOriginalImagesEnabledSwitch.isOn = configuration.isDataCachingForOriginalImageDataEnabled
        dataCacheForProcessedImagesEnabledSwitch.isEnabled = configuration.dataCache != nil
        dataCacheForProcessedImagesEnabledSwitch.isOn = configuration.isDataCachingForProcessedImagesEnabled

        if let _ = configuration.dataCache as? DataCache {
            // Do nothing
        } else if let _ = configuration.dataCache as? DFCache {
            dataCacheTitle.text = "Data Cache (DFCache)"
            dataCacheEnabledSwitch.isEnabled = false
        } else if configuration.dataCache != nil {
            dataCacheTitle.text = "Data Cache (Custom)"
            dataCacheEnabledSwitch.isEnabled = false
        } else {
            // Do nothing
        }

        queueDataLoadingValueLabel.text = "\(configuration.dataLoadingQueue.maxConcurrentOperationCount)"
        queueDataLoadingStepper.value = Double(configuration.dataLoadingQueue.maxConcurrentOperationCount)
        queueDataCachingValueLabel.text = "\(configuration.dataCachingQueue.maxConcurrentOperationCount)"
        queueDataCachingStepper.value = Double(configuration.dataCachingQueue.maxConcurrentOperationCount)
        queueDecodingValueLabel.text = "\(configuration.imageDecodingQueue.maxConcurrentOperationCount)"
        queueDecodingStepper.value = Double(configuration.imageDecodingQueue.maxConcurrentOperationCount)
        queueEncodingValueLabel.text = "\(configuration.imageEncodingQueue.maxConcurrentOperationCount)"
        queueEncodingStepper.value = Double(configuration.imageEncodingQueue.maxConcurrentOperationCount)
        queueProcessingValueLabel.text = "\(configuration.imageProcessingQueue.maxConcurrentOperationCount)"
        queueProcessingStepper.value = Double(configuration.imageProcessingQueue.maxConcurrentOperationCount)
        queueDecompressionValueLabel.text = "\(configuration.imageDecompressingQueue.maxConcurrentOperationCount)"
        queueDecompressionStepper.value = Double(configuration.imageDecompressingQueue.maxConcurrentOperationCount)
    }

    func reloadURLCache() {
        func display(urlCache: URLCache?) {
            if let urlCache = urlCache {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .binary
                urlCacheDataUsageLabel.text = "\(formatter.string(fromByteCount: Int64(urlCache.currentDiskUsage))) / \(formatter.string(fromByteCount: Int64(urlCache.diskCapacity)))"
                urlCacheMemoryUsageLabel.text = "\(formatter.string(fromByteCount: Int64(urlCache.currentMemoryUsage))) / \(formatter.string(fromByteCount: Int64(urlCache.memoryCapacity)))"
            } else {
                urlCacheDataUsageLabel.text = "Disabled"
                urlCacheMemoryUsageLabel.text = "Disabled"
            }
        }

        if let dataLoader = configuration.dataLoader as? DataLoader {
            display(urlCache: dataLoader.session.configuration.urlCache)
        } else if let dataLoader = configuration.dataLoader as? AlamofireDataLoader {
            display(urlCache: dataLoader.manager.session.configuration.urlCache)
        } else {
            urlCacheDataUsageLabel.text = "Unknown"
            urlCacheMemoryUsageLabel.text = "Unknown"
        }
    }

    func reloadDataCache() {
        if let dataCache = configuration.dataCache as? DataCache {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            dataCacheDataUsageCell.detailTextLabel?.text = "\(formatter.string(fromByteCount: Int64(dataCache.totalSize))) / \(formatter.string(fromByteCount: Int64(dataCache.sizeLimit)))"
            dataCacheTotalCountCell.detailTextLabel?.text = "\(dataCache.totalCount) / \(dataCache.countLimit == Int.max ? "Unlimited" : "\(dataCache.countLimit)")"
        } else if let dataCache = configuration.dataCache as? DFCache {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary

            if let diskCache = dataCache.diskCache {
                dataCacheDataUsageCell.detailTextLabel?.text = "\(formatter.string(fromByteCount: Int64(diskCache.contentsSize()))) / \(formatter.string(fromByteCount: Int64(diskCache.capacity)))"
                dataCacheTotalCountCell.detailTextLabel?.text = "Unlimited"
            } else {
                dataCacheDataUsageCell.detailTextLabel?.text = "Disabled"
                dataCacheTotalCountCell.detailTextLabel?.text = "Disabled"
            }
        } else if configuration.dataCache != nil {
            dataCacheDataUsageCell.detailTextLabel?.text = "Unknown"
            dataCacheTotalCountCell.detailTextLabel?.text = "Unknown"
        } else {
            dataCacheDataUsageCell.detailTextLabel?.text = "Disabled"
            dataCacheTotalCountCell.detailTextLabel?.text = "Disabled"
        }
    }

    // MARK: - Navigation

    @IBAction func buttonCancelTapped(_ sender: Any) {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    @IBAction func buttonSaveTapped(_ sender: Any) {
        delegate?.imagePipelineSettingsViewController(self, didFinishWithConfiguration: configuration)
    }

    // MARK: - Actions

    @IBAction func switchDecompressionEnabledValueChanged(_ sender: UISwitch) {
        configuration.isDecompressionEnabled = sender.isOn
    }

    @IBAction func switchDeduplicationEnabledValueChanged(_ sender: UISwitch) {
        configuration.isDeduplicationEnabled = sender.isOn
    }

    @IBAction func switchResumableDataEnabledTapped(_ sender: UISwitch) {
        configuration.isResumableDataEnabled = sender.isOn
    }

    @IBAction func switchRateLimiterValueChanged(_ sender: UISwitch) {
        configuration.isRateLimiterEnabled = sender.isOn
    }

    @IBAction func switchProgressiveDecodingValueChanged(_ sender: UISwitch) {
        configuration.isProgressiveDecodingEnabled = sender.isOn
    }

    @IBAction func switchMemoryCachedEnabledValueChanged(_ sender: UISwitch) {
        configuration.imageCache = sender.isOn ? ImageCache.shared : nil
    }

    @IBAction func buttonClearMemoryCacheTapped(_ sender: Any) {
        ImageCache.shared.removeAll()
        reload()
    }

    // MARK: - Actions (URLCache)

    @IBAction func urlCacheSwitchEnabledValueChanged(_ sender: UISwitch) {
        let configuration = DataLoader.defaultConfiguration
        configuration.urlCache = sender.isOn ? DataLoader.sharedUrlCache : nil

        self.configuration.dataLoader = DataLoader(configuration: configuration)
        reloadURLCache()
    }

    @IBAction func buttonClearURLCacheTapped(_ sender: Any) {
        if let dataLoader = configuration.dataLoader as? DataLoader {
            dataLoader.session.configuration.urlCache?.removeAllCachedResponses()
        } else if let dataLoader = configuration.dataLoader as? AlamofireDataLoader {
            dataLoader.manager.session.configuration.urlCache?.removeAllCachedResponses()
        } else {
            assertionFailure("Unsupported cache type")
        }

        reloadURLCache()
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.reload()
            self.reloadURLCache()
        }
    }

    // MARK: - Actions (Data Cache)

    @IBAction func dataCacheSwitchValueChanged(_ sender: UISwitch) {
        configuration.dataCache = sender.isOn ? try? DataCache(name: "com.github.kean.Nuke.DataCache") : nil
        reloadDataCache()
    }

    @IBAction func optionDataCacheForOriginalImageDataEnabledValueChanged(_ sender: UISwitch) {
        configuration.isDataCachingForOriginalImageDataEnabled = sender.isOn
    }

    @IBAction func optionDataCacheForProcessedImageDataEnabledValueChanged(_ sender: UISwitch) {
        configuration.isDataCachingForProcessedImagesEnabled = sender.isOn
    }

    @IBAction func dataCacheButtonClearTapped(_ sender: Any) {
        if let dataCache = configuration.dataCache as? DataCache {
            dataCache.removeAll()
            dataCache.flush()
        } else if let dataCache = configuration.dataCache as? DFCache {
            dataCache.removeAllObjects()
        }
        reloadDataCache()
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.reloadDataCache()
        }
    }

    // MARK: - Actions (Queues)

    @IBAction func stepperDataLoadingQueueValueChanged(_ sender: UIStepper) {
        configuration.dataLoadingQueue.maxConcurrentOperationCount = Int(sender.value)
        reload()
    }

    @IBAction func stepperDataCachingQueueValueChanged(_ sender: UIStepper) {
        configuration.dataCachingQueue.maxConcurrentOperationCount = Int(sender.value)
        reload()
    }

    @IBAction func stepperDecodingQueueValueChanged(_ sender: UIStepper) {
        configuration.imageDecodingQueue.maxConcurrentOperationCount = Int(sender.value)
        reload()
    }

    @IBAction func stepperEncodingQueueValueChanged(_ sender: UIStepper) {
        configuration.imageEncodingQueue.maxConcurrentOperationCount = Int(sender.value)
        reload()
    }

    @IBAction func stepperProcessingQueueValueChanged(_ sender: UIStepper) {
        configuration.imageProcessingQueue.maxConcurrentOperationCount = Int(sender.value)
        reload()
    }

    @IBAction func stepperDecompressionQueueValueChanged(_ sender: UIStepper) {
        configuration.imageDecompressingQueue.maxConcurrentOperationCount = Int(sender.value)
        reload()
    }
}
