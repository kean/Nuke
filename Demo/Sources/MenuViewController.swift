// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

private struct MenuItem {
    typealias Action = ((MenuItem) -> Void)

    var title: String?
    var subtitle: String?
    var action: Action?

    init(title: String?, subtitle: String? = nil, action: Action?) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }
}

private struct MenuSection {
    var title: String
    var items: [MenuItem]
    
    init(title: String, items: [MenuItem]) {
        self.title = title
        self.items = items
    }
}

final class MenuViewController: UITableViewController {
    fileprivate var sections = [MenuSection]()

    override func viewDidLoad() {
        super.viewDidLoad()

        UIApplication.shared.keyWindow?.tintColor = UIColor(red: 0.992, green: 0.243, blue: 0.416, alpha: 1.00)

        if #available(iOS 11.0, *) {
            navigationController?.navigationBar.prefersLargeTitles = true
            navigationItem.largeTitleDisplayMode = .automatic
        }

        sections.append(MenuSection(title: "General", items: {
            var items = [MenuItem]()

            items.append(MenuItem(
                title: "Image Pipeline",
                subtitle: "The default pipeline, configurable at runtime",
                action: { [weak self] _ in
                    let controller = BasicDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                    controller.title = "Image Pipeline"
                    self?.push(controller)
            }))

            items.append(MenuItem(
                title: "Image Processing",
                subtitle: "Showcases some of the built-in image processors",
                action: { [weak self] in
                    let controller = ImageProcessingDemoViewController()
                    controller.title = $0.title
                    self?.push(controller)
            }))

            items.append(MenuItem(
                title: "Disk Cache",
                subtitle: "Aggressive disk caching enabled",
                action: { [weak self] in
                    let controller = DataCachingDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                    controller.title = $0.title
                    self?.push(controller)
            }))

            items.append(MenuItem(
                title: "Prefetching",
                subtitle: "UICollectionView Prefetching",
                action: { [weak self] in
                    let controller = PrefetchingDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                    controller.title = $0.title
                    self?.push(controller)
            }))

            return items
        }()))

        sections.append(MenuSection(title: "Integrations", items: {
            var items = [MenuItem]()

            items.append(MenuItem(
                title: "Alamofire",
                subtitle: "Custom networking stack",
                action: { [weak self] in
                    let controller = AlamofireIntegrationDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                    controller.title = $0.title
                    self?.push(controller)
            }))

            items.append(MenuItem(
                title: "FLAnimatedImage",
                subtitle: "Display animated GIFs",
                action: { [weak self] in
                    let controller = AnimatedImageViewController(nibName: nil, bundle: nil)
                    controller.title = $0.title
                    self?.push(controller)
            }))

            items.append(MenuItem(
                title: "DFCache",
                subtitle: "Custom on-disk cache",
                action: { [weak self] in
                    let controller = CustomCacheDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                    controller.title = $0.title
                    self?.push(controller)
            }))

            return items
        }()))

        sections.append(MenuSection(title: "Advanced", items: {
            var items = [MenuItem]()

            items.append(MenuItem(
                title: "Progressive Decoding",
                subtitle: "Progressive vs baseline JPEG",
                action: { [weak self] _ in
                    let controller = ProgressiveDecodingDemoViewController()
                    controller.title = "Progressive JPEG"
                    self?.push(controller)
            }))

            items.append(MenuItem(
                title: "Rate Limiter",
                subtitle: "Infinite scroll, highlights rate limiter performance",
                action: { [weak self] in
                    let controller = RateLimiterDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                    controller.title = $0.title
                    self?.push(controller)
            }))

            items.append(MenuItem(
                title: "MP4 (Experimental)",
                subtitle: "Replaces GIFs with MP4",
                action: { [weak self] in
                    let controller = AnimatedImageUsingVideoViewController(nibName: nil, bundle: nil)
                    controller.title = $0.title
                    self?.push(controller)
            }))

            return items
        }()))
    }

    func push(_ controller: UIViewController) {
        self.navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MenuItemCell", for: indexPath)
        let item = sections[indexPath.section].items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.subtitle
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = sections[indexPath.section].items[indexPath.row]
        item.action?(item)
    }
}
