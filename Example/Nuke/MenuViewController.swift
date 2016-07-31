// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

struct MenuItem {
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

struct MenuSection {
    var title: String
    var items: [MenuItem]
    
    init(title: String, items: [MenuItem]) {
        self.title = title
        self.items = items
    }
}

class MenuViewController: UITableViewController {
    var sections = [MenuSection]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        var items = [MenuItem]()

        items.append(MenuItem(title: "Basic Demo") { [weak self] in
            let controller = BasicDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = $0.title
            self?.push(controller)
        })

        items.append(MenuItem(title: "Alamofire Demo", subtitle: "'Nuke/Alamofire' subspec") { [weak self] in
            let controller = AlamofireDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = $0.title
            self?.push(controller)
        })

        items.append(MenuItem(title: "Custom Cache Demo", subtitle: "Uses DFCache for on-disk caching") { [weak self] in
            let controller = CustomCacheDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = $0.title
            self?.push(controller)
        })

        items.append(MenuItem(title: "Animated GIF Demo", subtitle: "'Nuke/GIF' subspec") { [weak self] in
            let controller = AnimatedImageDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = $0.title
            self?.push(controller)
        })

        items.append(MenuItem(title: "Preheat Demo", subtitle: "Uses Preheat library") { [weak self] in
            let controller = PreheatingDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = $0.title
            self?.push(controller)
        })
        
        sections.append(MenuSection(title: "Nuke", items: items))
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
