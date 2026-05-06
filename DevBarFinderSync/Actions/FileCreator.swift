import Foundation

enum FileType: String, CaseIterable {
    case txt
    case sh
    case md
    case docx
    case xlsx
    case pptx

    var templateName: String { "blank" }
    var fileExtension: String {
        switch self {
        case .sh: return "sh"
        case .md: return "md"
        default:  return rawValue
        }
    }
    var needsTemplate: Bool { ![.txt, .sh, .md].contains(self) }

    var defaultFileName: String {
        switch self {
        case .txt:  return "未命名文本.txt"
        case .sh:   return "untitled.sh"
        case .md:   return "untitled.md"
        case .docx: return "未命名文档.docx"
        case .xlsx: return "未命名表格.xlsx"
        case .pptx: return "未命名演示.pptx"
        }
    }
}

final class FileCreator {

    @discardableResult
    static func createFile(type: FileType, in directory: URL) -> URL? {
        let accessing = directory.startAccessingSecurityScopedResource()
        defer {
            if accessing { directory.stopAccessingSecurityScopedResource() }
        }

        let destination = uniqueURL(for: type.defaultFileName, in: directory)

        if !type.needsTemplate {
            do {
                try Data().write(to: destination, options: .atomic)
                NSLog("DevBar: Created empty file at \(destination.path)")
                return destination
            } catch {
                NSLog("DevBar: Failed to create empty file: \(error.localizedDescription)")
                return nil
            }
        }

        guard let templateURL = Bundle.main.url(
            forResource: type.templateName,
            withExtension: type.fileExtension,
            subdirectory: "Templates"
        ) else {
            NSLog("DevBar: Template not found for \(type.rawValue)")
            return nil
        }

        do {
            let data = try Data(contentsOf: templateURL)
            try data.write(to: destination, options: .atomic)
            NSLog("DevBar: Created file at \(destination.path)")
            return destination
        } catch {
            NSLog("DevBar: Data.write failed: \(error.localizedDescription)")
        }

        // Fallback: FileManager.createFile
        if let data = try? Data(contentsOf: templateURL) {
            if FileManager.default.createFile(atPath: destination.path, contents: data, attributes: nil) {
                NSLog("DevBar: Created file (createFile) at \(destination.path)")
                return destination
            }
        }

        // Last resort: /bin/cp
        NSLog("DevBar: Trying cp fallback...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = [templateURL.path, destination.path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                NSLog("DevBar: Created file (cp) at \(destination.path)")
                return destination
            }
        } catch {
            NSLog("DevBar: cp fallback failed: \(error.localizedDescription)")
        }

        NSLog("DevBar: All methods failed for \(destination.path)")
        return nil
    }

    private static func uniqueURL(for name: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let nameWithoutExt = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        var candidate = directory.appendingPathComponent(name)
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let newName = "\(nameWithoutExt) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }

        return candidate
    }
}
