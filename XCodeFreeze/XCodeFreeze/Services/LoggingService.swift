import Foundation
import os.log

/// Log levels for the application
public enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

/// A centralized logging service
public final class LoggingService {
    /// Shared instance of the logging service
    public static let shared = LoggingService()
    
    // Private OSLog for system logging
    private let osLog: OSLog
    
    // File handle for log file
    private var fileHandle: FileHandle?
    private let logQueue = DispatchQueue(label: "com.xcodefreeeze.logging", qos: .utility)
    
    // Current minimum log level to display
    public var minimumLogLevel: LogLevel = .info
    
    // Enable/disable file logging
    public var enableFileLogging = false {
        didSet {
            if enableFileLogging {
                setupFileLogging()
            } else {
                closeFileLogging()
            }
        }
    }
    
    private init() {
        self.osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.toddbruss.XCodeFreeze", category: "default")
        setupFileLogging()
    }
    
    // MARK: - Public Logging Methods
    
    /// Log a message with a specific level
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: The severity level of the log
    ///   - file: The file where the log was called (automatic)
    ///   - function: The function where the log was called (automatic)
    ///   - line: The line where the log was called (automatic)
    public func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Skip logging if below minimum level
        guard shouldLog(level) else { return }
        
        // Format the log message
        let fileName = (file as NSString).lastPathComponent
        let formattedMessage = formatLogMessage(
            message: message,
            level: level,
            fileName: fileName,
            function: function,
            line: line
        )
        
        // Log to system
        os_log("%{public}@", log: osLog, type: level.osLogType, formattedMessage)
        
        // Log to console
        print(formattedMessage)
        
        // Log to file if enabled
        if enableFileLogging {
            logToFile(formattedMessage)
        }
    }
    
    /// Log a debug message
    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    /// Log an info message
    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    /// Log a warning message
    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    /// Log an error message
    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    /// Log a critical error message
    public func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, file: file, function: function, line: line)
    }
    
    // MARK: - Private Methods
    
    private func shouldLog(_ level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.debug, .info, .warning, .error, .critical]
        guard let minIndex = levels.firstIndex(of: minimumLogLevel),
              let currentIndex = levels.firstIndex(of: level) else {
            return true
        }
        return currentIndex >= minIndex
    }
    
    private func formatLogMessage(
        message: String,
        level: LogLevel,
        fileName: String,
        function: String,
        line: Int
    ) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line) \(function)] \(message)"
    }
    
    private func logToFile(_ message: String) {
        logQueue.async { [weak self] in
            guard let self = self, let fileHandle = self.fileHandle else { return }
            
            if let data = (message + "\n").data(using: .utf8) {
                do {
                    try fileHandle.write(contentsOf: data)
                } catch {
                    print("Failed to write to log file: \(error)")
                }
            }
        }
    }
    
    private func setupFileLogging() {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            let logDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Logs", isDirectory: true)
            
            // Create logs directory if it doesn't exist
            if !fileManager.fileExists(atPath: logDirectory.path) {
                do {
                    try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
                } catch {
                    print("Failed to create log directory: \(error)")
                    return
                }
            }
            
            // Create log file name with date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            let logFileName = "xcodefreeze-\(dateString).log"
            let logFilePath = logDirectory.appendingPathComponent(logFileName)
            
            // Create or open log file
            if !fileManager.fileExists(atPath: logFilePath.path) {
                fileManager.createFile(atPath: logFilePath.path, contents: nil)
            }
            
            do {
                let fileHandle = try FileHandle(forWritingTo: logFilePath)
                fileHandle.seekToEndOfFile()
                self.fileHandle = fileHandle
            } catch {
                print("Failed to open log file: \(error)")
            }
        }
    }
    
    private func closeFileLogging() {
        logQueue.async { [weak self] in
            do {
                try self?.fileHandle?.close()
                self?.fileHandle = nil
            } catch {
                print("Failed to close log file: \(error)")
            }
        }
    }
    
    deinit {
        closeFileLogging()
    }
} 