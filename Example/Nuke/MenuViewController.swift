//
//  ViewController.swift
//  Nuke
//
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import UIKit
import Nuke

struct MenuItem {
    var title: String?
    var subtitle: String?
    var action: (() -> Void)?
    
    init(title: String?, subtitle: String? = nil, action: (() -> Void)?) {
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

        items.append(MenuItem(title: "Basic Demo") {
            [weak self] in
            let controller = BasicDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = "Basic Demo"
            self?.navigationController?.pushViewController(controller, animated: true)
        })

        items.append(MenuItem(title: "Alamofire Demo", subtitle: "'Nuke/Alamofire' subspec") {
            [weak self] in
            let controller = AlamofireDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = "Alamofire Demo"
            self?.navigationController?.pushViewController(controller, animated: true)
        })

        items.append(MenuItem(title: "Custom Cache Demo", subtitle: "Uses DFCache for on-disk caching") {
            [weak self] in
            let controller = CustomCacheDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = "Custom Cache Demo"
            self?.navigationController?.pushViewController(controller, animated: true)
        })

        items.append(MenuItem(title: "Animated GIF Demo", subtitle: "'Nuke/GIF' subspec") {
            [weak self] in
            let controller = AnimatedImageDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = "Animated GIF Demo"
            self?.navigationController?.pushViewController(controller, animated: true)
        })

        items.append(MenuItem(title: "Preheat Demo", subtitle: "Uses Preheat package") {
            [weak self] in
            let controller = PreheatingDemoViewController(collectionViewLayout: UICollectionViewFlowLayout())
            controller.title = "Preheat Demo"
            self?.navigationController?.pushViewController(controller, animated: true)
        })
        
        sections.append(MenuSection(title: "Nuke", items: items))
    }
    
    // MARK: Table View
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return self.sections.count
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sections[section].items.count
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.sections[section].title
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("MenuItemCell", forIndexPath: indexPath)
        let item = self.sections[indexPath.section].items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.subtitle
        return cell
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let item = self.sections[indexPath.section].items[indexPath.row]
        item.action?()
    }
}
