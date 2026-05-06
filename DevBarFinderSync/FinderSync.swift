import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    private var refreshTimer: Timer?

    override init() {
        super.init()
        updateMonitoredDirectories()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(volumesChanged(_:)),
                       name: NSWorkspace.didMountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged(_:)),
                       name: NSWorkspace.didUnmountNotification, object: nil)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updateMonitoredDirectories()
        }
    }

    // MARK: - Volume Monitoring

    @objc private func volumesChanged(_ notification: Notification) {
        NSLog("DevBar: 检测到卷变化，更新监控目录")
        updateMonitoredDirectories()
    }

    private func updateMonitoredDirectories() {
        var urls: Set<URL> = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Volumes")
        ]

        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsLocalKey]
        if let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: []) {
            for volume in mountedVolumes {
                urls.insert(volume)
            }
        }

        NSLog("DevBar: 监控目录 = \(urls.map { $0.path })")
        FIFinderSyncController.default().directoryURLs = urls
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        let prefs = FinderSyncPreferences.shared

        // 新建文件子菜单
        let hasFileTypes = prefs.enableTxt || prefs.enableSh || prefs.enableMd || prefs.enableDocx || prefs.enableXlsx || prefs.enablePptx
        if hasFileTypes {
            let fileMenu = NSMenu(title: "New File")
            let fileItem = NSMenuItem(title: "New File", action: nil, keyEquivalent: "")
            fileItem.submenu = fileMenu

            if prefs.enableTxt {
                fileMenu.addItem(NSMenuItem(title: "Text File", action: #selector(createTxt(_:)), keyEquivalent: ""))
            }
            if prefs.enableSh {
                fileMenu.addItem(NSMenuItem(title: "Shell Script", action: #selector(createSh(_:)), keyEquivalent: ""))
            }
            if prefs.enableMd {
                fileMenu.addItem(NSMenuItem(title: "Markdown", action: #selector(createMd(_:)), keyEquivalent: ""))
            }
            if prefs.enableDocx {
                fileMenu.addItem(NSMenuItem(title: "Word 文档", action: #selector(createDocx(_:)), keyEquivalent: ""))
            }
            if prefs.enableXlsx {
                fileMenu.addItem(NSMenuItem(title: "Excel 表格", action: #selector(createXlsx(_:)), keyEquivalent: ""))
            }
            if prefs.enablePptx {
                fileMenu.addItem(NSMenuItem(title: "PowerPoint 文档", action: #selector(createPptx(_:)), keyEquivalent: ""))
            }

            menu.addItem(fileItem)
        }

        menu.addItem(NSMenuItem(title: "在此打开终端", action: #selector(openTerminal(_:)), keyEquivalent: ""))
        if CmuxLauncher.isInstalled {
            menu.addItem(NSMenuItem(title: "在此处打开 cmux", action: #selector(openCmux(_:)), keyEquivalent: ""))
        }

        // 拷贝文件路径（仅在有选中文件时显示）
        if prefs.enableCopyPath,
           let items = FIFinderSyncController.default().selectedItemURLs(),
           !items.isEmpty {
            let label = items.count == 1
                ? "拷贝路径"
                : "拷贝 \(items.count) 个路径"
            menu.addItem(NSMenuItem(title: label, action: #selector(copyFilePath(_:)), keyEquivalent: ""))
        }

        return menu
    }

    // MARK: - Target Directory

    private var targetDirectory: URL? {
        let targeted = FIFinderSyncController.default().targetedURL()
        NSLog("DevBar: targetedURL = \(targeted?.path ?? "nil")")

        if let items = FIFinderSyncController.default().selectedItemURLs() {
            NSLog("DevBar: selectedItems = \(items.map { $0.path })")
            for item in items {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    return item
                }
            }
        }
        return targeted
    }

    // MARK: - Actions

    @objc func createTxt(_ sender: AnyObject?) {
        NSLog("DevBar: createTxt called")
        guard let dir = targetDirectory else { NSLog("DevBar: no target dir"); return }
        FileCreator.createFile(type: .txt, in: dir)
    }

    @objc func createSh(_ sender: AnyObject?) {
        NSLog("DevBar: createSh called")
        guard let dir = targetDirectory else { NSLog("DevBar: no target dir"); return }
        FileCreator.createFile(type: .sh, in: dir)
    }

    @objc func createMd(_ sender: AnyObject?) {
        NSLog("DevBar: createMd called")
        guard let dir = targetDirectory else { NSLog("DevBar: no target dir"); return }
        FileCreator.createFile(type: .md, in: dir)
    }

    @objc func createDocx(_ sender: AnyObject?) {
        NSLog("DevBar: createDocx called")
        guard let dir = targetDirectory else { NSLog("DevBar: no target dir"); return }
        FileCreator.createFile(type: .docx, in: dir)
    }

    @objc func createXlsx(_ sender: AnyObject?) {
        NSLog("DevBar: createXlsx called")
        guard let dir = targetDirectory else { NSLog("DevBar: no target dir"); return }
        FileCreator.createFile(type: .xlsx, in: dir)
    }

    @objc func createPptx(_ sender: AnyObject?) {
        NSLog("DevBar: createPptx called")
        guard let dir = targetDirectory else { NSLog("DevBar: no target dir"); return }
        FileCreator.createFile(type: .pptx, in: dir)
    }

    @objc func openTerminal(_ sender: AnyObject?) {
        NSLog("DevBar: openTerminal called")
        guard let dir = targetDirectory else { NSLog("DevBar: no target dir"); return }
        TerminalLauncher.open(at: dir, using: FinderSyncPreferences.shared.preferredTerminal)
    }

    @objc func openCmux(_ sender: AnyObject?) {
        NSLog("DevBar: openCmux called")
        guard let dir = targetDirectory else { NSLog("DevBar: no target dir"); return }
        CmuxLauncher.open(at: dir)
    }

    @objc func copyFilePath(_ sender: AnyObject?) {
        PathCopier.copySelectedPaths()
    }
}
