// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke


fileprivate struct MenuItem {
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

fileprivate struct MenuSection {
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

        if #available(iOS 11.0, *) {
            navigationController?.navigationBar.prefersLargeTitles = true
            navigationItem.largeTitleDisplayMode = .automatic
        }

        sections.append(MenuSection(title: "Examples", items: {
            var items = [MenuItem]()
            
            items.append(MenuItem(title: "Basic", subtitle: "Zero config") { [weak self] in
                let controller = BasicDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                controller.title = $0.title
                self?.push(controller)
            })
            
            items.append(MenuItem(title: "Custom Cache", subtitle: "Uses DFCache for on-disk caching") { [weak self] in
                let controller = CustomCacheDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                controller.title = $0.title
                self?.push(controller)
            })
        
            items.append(MenuItem(title: "Preheating", subtitle: "Uses Preheat library") { [weak self] in
                let controller = PreheatingDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                controller.title = $0.title
                self?.push(controller)
            })
            
            items.append(MenuItem(title: "Rate Limiter", subtitle: "Infinite scroll, highlights rate limiter performance") { [weak self] in
                let controller = RateLimiterDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
                controller.title = $0.title
                self?.push(controller)
            })
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
