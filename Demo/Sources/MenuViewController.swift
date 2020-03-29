// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

final class MenuViewController: UITableViewController {
    private var sections = [MenuSection]()

    override func viewDidLoad() {
        super.viewDidLoad()

        UIApplication.shared.keyWindow?.tintColor = UIColor(red: 0.992, green: 0.243, blue: 0.416, alpha: 1.00)

        if #available(iOS 11.0, *) {
            navigationController?.navigationBar.prefersLargeTitles = true
            navigationItem.largeTitleDisplayMode = .automatic
        }

        sections = [generalSection, integrationSection, advancedSection]
    }

    private var generalSection: MenuSection {
        MenuSection(title: "General", items: [
            MenuItem(
                title: "Image Pipeline",
                subtitle: "The default pipeline, configurable at runtime",
                action: { [weak self] in self?.push(BasicDemoViewController(), $0) }
            ),
            MenuItem(
                title: "Image Processing",
                subtitle: "Showcases some of the built-in image processors",
                action: { [weak self] in self?.push(ImageProcessingDemoViewController(), $0) }
            ),
            MenuItem(
                title: "Disk Cache",
                subtitle: "Aggressive disk caching enabled",
                action: { [weak self] in self?.push(DataCachingDemoViewController(), $0) }
            ),
            MenuItem(
                title: "Prefetching",
                subtitle: "UICollectionView Prefetching",
                action: { [weak self] in self?.push(PrefetchingDemoViewController(), $0) }
            )
        ])
    }

    private var integrationSection:  MenuSection {
        MenuSection(title: "Integrations", items: [
            MenuItem(
                title: "Alamofire",
                subtitle: "Custom networking stack",
                action: { [weak self] in self?.push(AlamofireIntegrationDemoViewController(), $0) }
            ),
            MenuItem(
                title: "Gifu",
                subtitle: "Display animated GIFs",
                action: { [weak self] in self?.push(AnimatedImageViewController(), $0) }
            ),
            MenuItem(
                title: "SwiftSVG",
                subtitle: "Render vector images",
                action: { [weak self] in self?.push(SwiftSVGDemoViewController(), $0) }
            )
        ])
    }

    private var advancedSection: MenuSection {
        MenuSection(title: "Advanced", items: [
            MenuItem(
                title: "Progressive JPEG",
                subtitle: "Progressive vs baseline JPEG",
                action: { [weak self] in self?.push(ProgressiveDecodingDemoViewController(), $0) }
            ),
            MenuItem(
                title: "Rate Limiter",
                subtitle: "Infinite scroll, highlights rate limiter performance",
                action: { [weak self] in self?.push(RateLimiterDemoViewController(), $0) }
            ),
            MenuItem(
                title: "MP4 (Experimental)",
                subtitle: "Replaces GIFs with MP4",
                action: { [weak self] in self?.push(AnimatedImageUsingVideoViewController(), $0)
            })
        ])
    }

    private func push(_ controller: UIViewController, _ item: MenuItem) {
        controller.title = item.title
        navigationController?.pushViewController(controller, animated: true)
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

// MARK - MenuItem

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
