import Foundation
import ObjectiveC

/// SkyLight's bridge moves foreign windows without changing the active Desktop. All IPC stays off-main.
enum WindowDesktopMoveBridge {
    private typealias Allocate = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
    private typealias Initialize = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> Unmanaged<AnyObject>?
    private typealias Perform = @convention(c) (AnyObject, Selector) -> Void

    private struct Methods {
        let cls: AnyClass
        let allocate: Allocate
        let initialize: Initialize
        let perform: Perform
    }

    private static let allocSelector = NSSelectorFromString("alloc")
    private static let initSelector = NSSelectorFromString("initWithWindows:spaceID:")
    private static let performSelector = NSSelectorFromString("performWithWMBridgeDelegate")
    private static let methods: Methods? = {
        guard let cls = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
              let allocate = class_getClassMethod(cls, allocSelector),
              let initialize = class_getInstanceMethod(cls, initSelector),
              let perform = class_getInstanceMethod(cls, performSelector),
              signature(allocate, returns: "@", arguments: ["@", ":"]),
              signature(initialize, returns: "@", arguments: ["@", ":", "@", "Q"]),
              signature(perform, returns: "v", arguments: ["@", ":"]) else { return nil }
        return Methods(cls: cls, allocate: unsafeBitCast(method_getImplementation(allocate), to: Allocate.self),
            initialize: unsafeBitCast(method_getImplementation(initialize), to: Initialize.self),
            perform: unsafeBitCast(method_getImplementation(perform), to: Perform.self))
    }()

    static var isAvailable: Bool { methods != nil }

    /// Submission has no success reply. Only subsequent WindowServer membership confirms the move.
    static func submit(windowId: UInt32, spaceId: UInt64) -> Bool {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let methods else { return false }
        let allocated = methods.allocate(methods.cls, allocSelector)
        guard let initialized = methods.initialize(allocated.takeUnretainedValue(), initSelector,
            [NSNumber(value: windowId)], spaceId) else { return false }
        let operation = initialized.takeRetainedValue()
        methods.perform(operation, performSelector)
        return true
    }

    private static func signature(_ method: Method, returns result: String, arguments: [String]) -> Bool {
        guard method_getNumberOfArguments(method) == arguments.count else { return false }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType) == result else { return false }
        for (index, expected) in arguments.enumerated() {
            guard let type = method_copyArgumentType(method, UInt32(index)) else { return false }
            defer { free(type) }
            guard String(cString: type) == expected else { return false }
        }
        return true
    }
}
