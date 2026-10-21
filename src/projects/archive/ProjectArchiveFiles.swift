import Cocoa

/// The capture queue owns the temporary snapshot; completed directories are published only after every write succeeds.
enum ProjectArchiveFiles {
    private static let updates = DispatchQueue(label: "com.alt-tab.archive-status", qos: .utility)
    struct Capture {
        var snapshot: ProjectArchiveSnapshot
        let projects: [ProjectEntry]
        let directories: [URL]
        let elements: [String: AXUIElement]
        var cancellation: ProjectArchiveCancellation? = nil
    }

    static func create(_ capture: Capture, completion: @escaping (Result<(ProjectArchiveSnapshot, [URL]), Error>) -> Void) {
        BackgroundWork.accessibilityCommandsQueue.addOperation {
            let ready: Capture
            do { ready = try readReferences(capture) }
            catch { DispatchQueue.main.async { completion(.failure(error)) }; return }
            BackgroundWork.screenshotsQueue.addOperation {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    let projects = try encoder.encode(ready.projects)
                    let result = try ProjectArchiveStore.write(ready.snapshot, projects: projects, directories: ready.directories,
                        cancellation: ready.cancellation, image: WindowCaptureScreenshotsPrivateApi.oneTimeCapture)
                    DispatchQueue.main.async { completion(.success(result)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    private static func readReferences(_ capture: Capture) throws -> Capture {
        var request = capture
        try request.cancellation?.check()
        for index in request.snapshot.windows.indices {
            try request.cancellation?.check()
            guard let element = request.elements[request.snapshot.windows[index].id] else { continue }
            if let reference = document(element) { request.snapshot.windows[index].reference = reference }
        }
        return request
    }

    private static func document(_ element: AXUIElement) -> String? {
        for key in [kAXDocumentAttribute, kAXURLAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { continue }
            if let url = value as? URL { return url.absoluteString }
            if let string = value as? String, !string.isEmpty { return string }
        }
        return nil
    }

    static func update(_ snapshot: ProjectArchiveSnapshot, in directories: [URL], completion: @escaping (Error?) -> Void) {
        // A spontaneous close can advance while the previous status write is in flight.
        updates.async {
            do {
                for directory in directories { try ProjectArchiveStore.save(snapshot, in: directory) }
                DispatchQueue.main.async { completion(nil) }
            } catch { DispatchQueue.main.async { completion(error) } }
        }
    }
}
