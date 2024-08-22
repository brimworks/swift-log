import Foundation

// Install this log handler if you want the ability to dynamically change the
// log handler implementation. Generally, this should only be done for testing:
public final class DelegatedLogHandler: LogHandler, @unchecked Sendable {
    private static let queue = DispatchQueue(label: "DelegatedLogHandler")
    // Guarded by queue:
    private static var isInitialized = false
    private static var factory: @Sendable(String, Logger.MetadataProvider?) -> any LogHandler = {
        label, _ in
        // Default to stderr logger:
        StreamLogHandler.standardError(label: label)
    }
    // Guarded by queue:
    private static var metadataProvider: Logger.MetadataProvider? = nil
    // Guarded by queue:
    private static var handlers: NSMapTable<NSString, DelegatedLogHandler> = .strongToWeakObjects()

    private let label: String
    private var delegate: any LogHandler
    public var metadata: Logger.Metadata {
        get {
            delegate.metadata
        }
        set {
            delegate.metadata = newValue
        }
    }
    public var logLevel: Logger.Level {
        get {
            delegate.logLevel
        }
        set {
            delegate.logLevel = newValue
        }
    }

    internal init(label: String, delegate: any LogHandler) {
        self.label = label
        self.delegate = delegate
    }

    internal func overtake() {
        self.delegate = Self.factory(label, Self.metadataProvider)
    }
    public static func bootstrap(_ factory: @escaping @Sendable(String) -> any LogHandler) {
        queue.sync {
            Self.factory = { label, _ in factory(label) }
            Self.metadataProvider = nil
            Self.unsafeInitialize()
        }
    }

    public static func bootstrap(_ factory: @escaping @Sendable(String, Logger.MetadataProvider?) -> any LogHandler,
                                 metadataProvider: Logger.MetadataProvider? = nil)
    {
        queue.sync {
            Self.factory = factory
            Self.metadataProvider = metadataProvider
            Self.unsafeInitialize()
        }
    }
    // MUST be called in a queue.sync call:
    internal static func unsafeInitialize() {
        if !isInitialized {
            isInitialized = true
            LoggingSystem.bootstrap({ label in
                queue.sync { () -> DelegatedLogHandler in
                    let found = Self.handlers.object(forKey: label as NSString)
                    if let found {
                        return found
                    }
                    let handler = DelegatedLogHandler(
                        label: label,
                        delegate: Self.factory(label, Self.metadataProvider))
                    Self.handlers.setObject(handler, forKey: label as NSString)
                    return handler
                }
            })
        } else {
            // Update all existing handlers:
            guard let enumerator = handlers.objectEnumerator() else {
                return
            }
            while true {
                guard let handler = enumerator.nextObject() else {
                    break
                }
                if let handler = handler as? DelegatedLogHandler {
                    handler.overtake()
                }
            }
        }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        delegate.log(level: level, message: message, metadata: metadata, source: source, file: file, function: function, line: line)
    }

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            delegate[metadataKey: metadataKey]
        }
        set {
            delegate[metadataKey: metadataKey] = newValue
        }
    }
}
