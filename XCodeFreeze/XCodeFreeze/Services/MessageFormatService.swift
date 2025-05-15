import Foundation

/// Service for formatting various message types used throughout the application
public final class MessageFormatService {
    /// Shared instance
    public static let shared = MessageFormatService()
    
    private let logger = LoggingService.shared
    private let dateFormatter = ISO8601DateFormatter()
    
    private init() {
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    
    // MARK: - Message Formatting
    
    /// Format a system message
    /// - Parameter message: The message content
    /// - Returns: Formatted message
    public func formatSystemMessage(_ message: String) -> String {
        return formatMessage(type: "SYSTEM", message: message)
    }
    
    /// Format an error message
    /// - Parameter message: The error message content
    /// - Returns: Formatted error message
    public func formatErrorMessage(_ message: String) -> String {
        logger.error(message)
        return formatMessage(type: "ERROR", message: message)
    }
    
    /// Format a diagnostic message
    /// - Parameter message: The diagnostic content
    /// - Returns: Formatted diagnostic message
    public func formatDiagnosticMessage(_ message: String) -> String {
        return formatMessage(type: "DIAGNOSTIC", message: message)
    }
    
    /// Format a debug message
    /// - Parameter message: The debug content
    /// - Returns: Formatted debug message
    public func formatDebugMessage(_ message: String) -> String {
        logger.debug(message)
        return formatMessage(type: "DEBUG", message: message)
    }
    
    /// Format a JSON-RPC request message
    /// - Parameters:
    ///   - method: The RPC method name
    ///   - params: The parameters object (optional)
    /// - Returns: Formatted RPC message
    public func formatJsonRpcRequest(method: String, params: Any? = nil) -> String {
        var paramsFormatted = ""
        
        if let params = params {
            if let paramsDict = params as? [String: Any] {
                paramsFormatted = JSONFormatter.buildObject(paramsDict)
            } else {
                paramsFormatted = "\(params)"
            }
            
            return "[→] JSON-RPC: \(method)(\(paramsFormatted))"
        }
        
        return "[→] JSON-RPC: \(method)()"
    }
    
    /// Format a JSON-RPC response message
    /// - Parameters:
    ///   - result: The response result object
    ///   - isError: Whether the response is an error
    /// - Returns: Formatted RPC response
    public func formatJsonRpcResponse(result: Any, isError: Bool = false) -> String {
        var resultFormatted = ""
        
        if let resultDict = result as? [String: Any] {
            resultFormatted = JSONFormatter.buildObject(resultDict)
        } else if let resultString = result as? String {
            resultFormatted = "\"\(resultString)\""
        } else {
            resultFormatted = "\(result)"
        }
        
        if isError {
            return "[←] JSON-RPC Error Response: \(resultFormatted)"
        } else {
            return "[←] JSON-RPC Response: \(resultFormatted)"
        }
    }
    
    // MARK: - Private Methods
    
    private func formatMessage(type: String, message: String) -> String {
        let timestamp = dateFormatter.string(from: Date())
        return "[\(timestamp)] [\(type)] \(message)"
    }
} 