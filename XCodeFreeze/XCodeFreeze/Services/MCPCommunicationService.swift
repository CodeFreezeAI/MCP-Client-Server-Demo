import Foundation
import MCP
import Combine

/// NOTICE: This service is currently not integrated into the main app.
/// The app uses ClientServerService with the MCP Swift library instead.
/// This implementation provides manual JSON-RPC handling but needs integration work.
/// 
/// Handles robust JSON-RPC communication over stdio pipes with message buffering
/// This service ensures smooth bidirectional communication like Cursor AI and Claude Code
@MainActor
public class MCPCommunicationService: ObservableObject {
    
    // MARK: - Message Types
    
    public struct JSONRPCMessage: Codable {
        let jsonrpc: String = "2.0"
        let id: JSONRPCId?
        let method: String?
        let params: AnyCodable?
        let result: AnyCodable?
        let error: JSONRPCError?
        
        enum CodingKeys: String, CodingKey {
            case jsonrpc, id, method, params, result, error
        }
    }
    
    public struct JSONRPCError: Codable {
        let code: Int
        let message: String
        let data: AnyCodable?
    }
    
    public enum JSONRPCId: Codable {
        case string(String)
        case number(Int)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                self = .string(str)
            } else if let num = try? container.decode(Int.self) {
                self = .number(num)
            } else {
                throw DecodingError.typeMismatch(JSONRPCId.self, .init(codingPath: [], debugDescription: "ID must be string or number"))
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let str):
                try container.encode(str)
            case .number(let num):
                try container.encode(num)
            }
        }
    }
    
    // MARK: - Properties
    
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var process: Process?
    
    private var messageBuffer = Data()
    private let messageQueue = DispatchQueue(label: "mcp.message.queue", qos: .userInitiated)
    private var pendingRequests = [String: CheckedContinuation<JSONRPCMessage, Error>]()
    private var messageHandlers = [(JSONRPCMessage) -> Void]()
    
    @Published public var isConnected = false
    @Published public var connectionError: String?
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public init() {
        encoder.outputFormatting = .sortedKeys
    }
    
    // MARK: - Connection Management
    
    /// Start the MCP server process with proper stdio handling
    public func connect(serverPath: String, arguments: [String] = [], environment: [String: String] = [:]) async throws {
        // Clean up any existing connection
        await disconnect()
        
        // Create pipes for bidirectional communication
        inputPipe = Pipe()
        outputPipe = Pipe()
        
        // Configure process
        process = Process()
        guard let process = process else { throw MCPError.connectionFailed("Failed to create process") }
        
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe() // Capture but don't process stderr for now
        
        // Set up environment
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env
        
        // Set up output handling before starting process
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task { @MainActor [weak self] in
                    self?.handleIncomingData(data)
                }
            }
        }
        
        // Start the process
        try process.run()
        
        // Verify process started
        if !process.isRunning {
            throw MCPError.connectionFailed("Process failed to start")
        }
        
        isConnected = true
        connectionError = nil
        
        // Initialize MCP connection
        try await initializeMCPConnection()
    }
    
    /// Disconnect and clean up resources
    public func disconnect() async {
        isConnected = false
        
        // Cancel all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPError.disconnected)
        }
        pendingRequests.removeAll()
        
        // Clean up process
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        messageBuffer = Data()
    }
    
    // MARK: - Message Handling
    
    /// Handle incoming data from the server with proper buffering
    private func handleIncomingData(_ data: Data) {
        messageBuffer.append(data)
        
        // Process complete messages (newline-delimited JSON)
        while let newlineIndex = messageBuffer.firstIndex(of: 0x0A) { // \n
            let messageData = messageBuffer.prefix(upTo: newlineIndex)
            messageBuffer.removeFirst(newlineIndex + 1)
            
            if messageData.isEmpty { continue }
            
            do {
                let message = try decoder.decode(JSONRPCMessage.self, from: messageData)
                Task { @MainActor in
                    self.processMessage(message)
                }
            } catch {
                print("Failed to decode message: \(error)")
                if let str = String(data: messageData, encoding: .utf8) {
                    print("Raw message: \(str)")
                }
            }
        }
    }
    
    /// Process a decoded JSON-RPC message
    private func processMessage(_ message: JSONRPCMessage) {
        // Handle responses to requests
        if let id = message.id {
            let idString = switch id {
            case .string(let s): s
            case .number(let n): String(n)
            }
            
            if let continuation = pendingRequests.removeValue(forKey: idString) {
                continuation.resume(returning: message)
            }
        }
        
        // Handle notifications and method calls
        if message.method != nil {
            for handler in messageHandlers {
                handler(message)
            }
        }
    }
    
    // MARK: - Sending Messages
    
    /// Send a JSON-RPC request and wait for response
    public func sendRequest<T: Codable>(_ method: String, params: T? = nil as String?) async throws -> JSONRPCMessage {
        let requestId = UUID().uuidString
        let message = JSONRPCMessage(
            id: .string(requestId),
            method: method,
            params: params.map { AnyCodable($0) },
            result: nil,
            error: nil
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation
            
            Task {
                do {
                    try await sendMessage(message)
                } catch {
                    pendingRequests.removeValue(forKey: requestId)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Send a notification (no response expected)
    public func sendNotification<T: Codable>(_ method: String, params: T? = nil as String?) async throws {
        let message = JSONRPCMessage(
            id: nil,
            method: method,
            params: params.map { AnyCodable($0) },
            result: nil,
            error: nil
        )
        try await sendMessage(message)
    }
    
    /// Send a raw JSON-RPC message
    private func sendMessage(_ message: JSONRPCMessage) async throws {
        guard let inputPipe = inputPipe else {
            throw MCPError.notConnected
        }
        
        let data = try encoder.encode(message)
        let messageData = data + "\n".data(using: .utf8)!
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            messageQueue.async {
                do {
                    try inputPipe.fileHandleForWriting.write(contentsOf: messageData)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - MCP Protocol Implementation
    
    /// Initialize MCP connection with proper handshake
    private func initializeMCPConnection() async throws {
        // Send initialize request
        let initParams = InitializeParams(
            protocolVersion: "1.0.0",
            clientInfo: ClientInfo(name: "XCodeFreeze", version: "1.0.0"),
            capabilities: ClientCapabilities()
        )
        
        let response = try await sendRequest("initialize", params: initParams)
        
        if let error = response.error {
            throw MCPError.initializationFailed(error.message)
        }
        
        // Send initialized notification
        try await sendNotification("initialized", params: nil as String?)
    }
    
    /// List available tools from the server
    public func listTools() async throws -> [MCPTool] {
        let response = try await sendRequest("tools/list", params: nil as String?)
        
        if let error = response.error {
            throw MCPError.serverError(error.message)
        }
        
        // Parse tools from response
        guard response.result != nil else {
            return []
        }
        
        // Convert AnyCodable result to MCPTool array
        // This is simplified - you'll need proper parsing based on your MCP server response format
        return []
    }
    
    /// Call a tool with arguments
    public func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let params = ToolCallParams(name: name, arguments: arguments)
        let response = try await sendRequest("tools/call", params: params)
        
        if let error = response.error {
            throw MCPError.toolExecutionFailed(error.message)
        }
        
        // Extract result content
        guard let resultValue = response.result?.value as? [String: Any],
              let content = resultValue["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            return "No content returned"
        }
        
        return text
    }
    
    // MARK: - Message Subscription
    
    /// Add a handler for incoming messages
    public func addMessageHandler(_ handler: @escaping (JSONRPCMessage) -> Void) {
        messageHandlers.append(handler)
    }
}

// MARK: - Supporting Types

struct InitializeParams: Codable {
    let protocolVersion: String
    let clientInfo: ClientInfo
    let capabilities: ClientCapabilities
}

struct ClientInfo: Codable {
    let name: String
    let version: String
}

struct ClientCapabilities: Codable {
    // Add capabilities as needed
}

struct ToolCallParams: Codable {
    let name: String
    let arguments: [String: Any]
    
    init(name: String, arguments: [String: Any]) {
        self.name = name
        self.arguments = arguments
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let argumentsAnyCodable = try container.decode(AnyCodable.self, forKey: .arguments)
        arguments = argumentsAnyCodable.value as? [String: Any] ?? [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(AnyCodable(arguments), forKey: .arguments)
    }
    
    enum CodingKeys: String, CodingKey {
        case name, arguments
    }
}

// MARK: - Errors

public enum MCPError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case initializationFailed(String)
    case serverError(String)
    case toolExecutionFailed(String)
    case disconnected
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MCP server"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .initializationFailed(let message):
            return "Initialization failed: \(message)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .toolExecutionFailed(let message):
            return "Tool execution failed: \(message)"
        case .disconnected:
            return "Disconnected from server"
        }
    }
}

// MARK: - AnyCodable Helper

public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Cannot encode value"))
        }
    }
}