import Foundation
import Combine

/// NOTICE: This service is currently not integrated into the main app.
/// The app uses ToolDiscoveryService instead for tool management.
/// This implementation provides enhanced tool discovery but needs integration work.
///
/// Enhanced tool discovery service for smooth MCP integration
/// Provides automatic tool discovery, parameter inference, and caching
@MainActor
public class MCPToolDiscoveryService: ObservableObject {
    
    // MARK: - Tool Models
    
    public struct Tool: Codable, Identifiable, Equatable {
        public let id = UUID()
        public let name: String
        public let description: String
        public let parameters: [Parameter]
        public let category: String?
        public let examples: [String]?
        
        public struct Parameter: Codable, Equatable {
            public let name: String
            public let type: ParameterType
            public let description: String?
            public let required: Bool
            public let defaultValue: String?
            public let enumValues: [String]?
        }
        
        public enum ParameterType: String, Codable {
            case string
            case integer
            case boolean
            case number
            case array
            case object
        }
        
        private enum CodingKeys: String, CodingKey {
            case name, description, parameters, category, examples
        }
    }
    
    // MARK: - Properties
    
    @Published public private(set) var discoveredTools: [Tool] = []
    @Published public private(set) var isDiscovering = false
    @Published public private(set) var lastDiscoveryError: String?
    
    private let communicationService: MCPCommunicationService
    private var cancellables = Set<AnyCancellable>()
    private let toolCache = ToolCache()
    
    // Tool categorization for better organization
    private let toolCategories = [
        "file": ["read", "write", "create", "delete", "list"],
        "project": ["build", "run", "test", "clean"],
        "code": ["analyze", "format", "refactor", "snippet"],
        "git": ["commit", "push", "pull", "status", "diff"],
        "system": ["exec", "env", "info", "help"]
    ]
    
    // MARK: - Initialization
    
    public init(communicationService: MCPCommunicationService) {
        self.communicationService = communicationService
        setupBindings()
    }
    
    private func setupBindings() {
        // Listen for connection changes
        communicationService.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    Task {
                        await self?.discoverTools()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Tool Discovery
    
    /// Discover all available tools from the MCP server
    public func discoverTools() async {
        isDiscovering = true
        lastDiscoveryError = nil
        
        defer { isDiscovering = false }
        
        // Check cache first
        if let cachedTools = toolCache.getCachedTools() {
            discoveredTools = cachedTools
            return
        }
        
        do {
            // Request tool list from server
            let response = try await communicationService.sendRequest("tools/list", params: nil as String?)
            
            // Parse tools from response
            let tools = try parseToolsFromResponse(response)
            
            // Categorize and enhance tools
            let enhancedTools = await enhanceTools(tools)
            
            // Update discovered tools
            discoveredTools = enhancedTools
            
            // Cache the results
            toolCache.cacheTools(enhancedTools)
            
        } catch {
            lastDiscoveryError = error.localizedDescription
            print("Tool discovery failed: \(error)")
        }
    }
    
    /// Parse tools from JSON-RPC response
    private func parseToolsFromResponse(_ response: MCPCommunicationService.JSONRPCMessage) throws -> [Tool] {
        guard let result = response.result?.value as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }
        
        var tools: [Tool] = []
        
        for toolData in toolsArray {
            guard let name = toolData["name"] as? String,
                  let description = toolData["description"] as? String else {
                continue
            }
            
            // Parse parameters from input schema
            let parameters = parseParameters(from: toolData["inputSchema"] as? [String: Any])
            
            // Determine category
            let category = determineCategory(for: name)
            
            // Generate examples if available
            let examples = generateExamples(for: name, parameters: parameters)
            
            let tool = Tool(
                name: name,
                description: description,
                parameters: parameters,
                category: category,
                examples: examples
            )
            
            tools.append(tool)
        }
        
        return tools
    }
    
    /// Parse parameters from input schema
    private func parseParameters(from schema: [String: Any]?) -> [Tool.Parameter] {
        guard let schema = schema,
              let properties = schema["properties"] as? [String: Any] else {
            return []
        }
        
        let required = schema["required"] as? [String] ?? []
        var parameters: [Tool.Parameter] = []
        
        for (name, value) in properties {
            guard let paramData = value as? [String: Any] else { continue }
            
            let type = parseParameterType(from: paramData["type"] as? String)
            let description = paramData["description"] as? String
            let isRequired = required.contains(name)
            let defaultValue = paramData["default"] as? String
            let enumValues = paramData["enum"] as? [String]
            
            let parameter = Tool.Parameter(
                name: name,
                type: type,
                description: description,
                required: isRequired,
                defaultValue: defaultValue,
                enumValues: enumValues
            )
            
            parameters.append(parameter)
        }
        
        return parameters.sorted { $0.required && !$1.required }
    }
    
    /// Parse parameter type from string
    private func parseParameterType(from typeString: String?) -> Tool.ParameterType {
        switch typeString?.lowercased() {
        case "string":
            return .string
        case "integer", "int":
            return .integer
        case "boolean", "bool":
            return .boolean
        case "number", "float", "double":
            return .number
        case "array":
            return .array
        case "object":
            return .object
        default:
            return .string
        }
    }
    
    /// Determine category for a tool based on its name
    private func determineCategory(for toolName: String) -> String? {
        let lowercaseName = toolName.lowercased()
        
        for (category, keywords) in toolCategories {
            if keywords.contains(where: { lowercaseName.contains($0) }) {
                return category
            }
        }
        
        return nil
    }
    
    /// Generate usage examples for a tool
    private func generateExamples(for toolName: String, parameters: [Tool.Parameter]) -> [String] {
        var examples: [String] = []
        
        // Basic example with required parameters
        if !parameters.isEmpty {
            let requiredParams = parameters.filter { $0.required }
            if !requiredParams.isEmpty {
                let paramExamples = requiredParams.map { param in
                    "\(param.name): <\(param.type.rawValue)>"
                }.joined(separator: ", ")
                examples.append("\(toolName) \(paramExamples)")
            }
        } else {
            examples.append(toolName)
        }
        
        // Add specific examples based on tool name patterns
        if toolName.contains("file") || toolName.contains("read") {
            examples.append("\(toolName) path: /Users/example/file.txt")
        } else if toolName.contains("project") {
            examples.append("\(toolName) name: MyProject")
        }
        
        return examples
    }
    
    /// Enhance tools with additional metadata and capabilities
    private func enhanceTools(_ tools: [Tool]) async -> [Tool] {
        // In production, this could query additional metadata from the server
        // or apply machine learning to improve tool descriptions
        return tools.sorted { $0.name < $1.name }
    }
    
    // MARK: - Tool Execution
    
    /// Execute a tool with the given arguments
    public func executeTool(_ tool: Tool, arguments: [String: Any]) async throws -> String {
        // Validate required parameters
        for parameter in tool.parameters where parameter.required {
            guard arguments[parameter.name] != nil else {
                throw ToolError.missingRequiredParameter(parameter.name)
            }
        }
        
        // Validate parameter types
        for (name, value) in arguments {
            if let parameter = tool.parameters.first(where: { $0.name == name }) {
                try validateParameterType(value, for: parameter)
            }
        }
        
        // Execute via communication service
        return try await communicationService.callTool(name: tool.name, arguments: arguments)
    }
    
    /// Validate parameter type
    private func validateParameterType(_ value: Any, for parameter: Tool.Parameter) throws {
        switch parameter.type {
        case .string:
            guard value is String else {
                throw ToolError.invalidParameterType(parameter.name, expected: "string")
            }
        case .integer:
            guard value is Int else {
                throw ToolError.invalidParameterType(parameter.name, expected: "integer")
            }
        case .boolean:
            guard value is Bool else {
                throw ToolError.invalidParameterType(parameter.name, expected: "boolean")
            }
        case .number:
            guard value is Double || value is Float || value is Int else {
                throw ToolError.invalidParameterType(parameter.name, expected: "number")
            }
        case .array:
            guard value is [Any] else {
                throw ToolError.invalidParameterType(parameter.name, expected: "array")
            }
        case .object:
            guard value is [String: Any] else {
                throw ToolError.invalidParameterType(parameter.name, expected: "object")
            }
        }
        
        // Validate enum values if specified
        if let enumValues = parameter.enumValues,
           let stringValue = value as? String {
            guard enumValues.contains(stringValue) else {
                throw ToolError.invalidEnumValue(parameter.name, allowed: enumValues)
            }
        }
    }
    
    // MARK: - Tool Search
    
    /// Search for tools matching the query
    public func searchTools(query: String) -> [Tool] {
        let lowercaseQuery = query.lowercased()
        
        return discoveredTools.filter { tool in
            tool.name.lowercased().contains(lowercaseQuery) ||
            tool.description.lowercased().contains(lowercaseQuery) ||
            tool.category?.lowercased().contains(lowercaseQuery) == true
        }
    }
    
    /// Get tools by category
    public func toolsByCategory(_ category: String) -> [Tool] {
        return discoveredTools.filter { $0.category == category }
    }
    
    /// Get tool by name
    public func tool(named name: String) -> Tool? {
        return discoveredTools.first { $0.name == name }
    }
    
    // MARK: - Export for AI
    
    /// Export tools in OpenAI function calling format
    public func exportForOpenAI() -> [[String: Any]] {
        return discoveredTools.map { tool in
            var function: [String: Any] = [
                "name": tool.name,
                "description": tool.description
            ]
            
            if !tool.parameters.isEmpty {
                var properties: [String: Any] = [:]
                var required: [String] = []
                
                for param in tool.parameters {
                    var paramSchema: [String: Any] = [
                        "type": param.type.rawValue
                    ]
                    
                    if let description = param.description {
                        paramSchema["description"] = description
                    }
                    
                    if let enumValues = param.enumValues {
                        paramSchema["enum"] = enumValues
                    }
                    
                    properties[param.name] = paramSchema
                    
                    if param.required {
                        required.append(param.name)
                    }
                }
                
                function["parameters"] = [
                    "type": "object",
                    "properties": properties,
                    "required": required
                ]
            }
            
            return [
                "type": "function",
                "function": function
            ]
        }
    }
}

// MARK: - Tool Cache

private class ToolCache {
    private let cacheKey = "MCPToolDiscovery.cachedTools"
    private let cacheExpiration: TimeInterval = 3600 // 1 hour
    
    func getCachedTools() -> [MCPToolDiscoveryService.Tool]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(CachedTools.self, from: data) else {
            return nil
        }
        
        // Check if cache is expired
        if Date().timeIntervalSince(cache.timestamp) > cacheExpiration {
            return nil
        }
        
        return cache.tools
    }
    
    func cacheTools(_ tools: [MCPToolDiscoveryService.Tool]) {
        let cache = CachedTools(tools: tools, timestamp: Date())
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    struct CachedTools: Codable {
        let tools: [MCPToolDiscoveryService.Tool]
        let timestamp: Date
    }
}

// MARK: - Errors

public enum ToolError: LocalizedError {
    case missingRequiredParameter(String)
    case invalidParameterType(String, expected: String)
    case invalidEnumValue(String, allowed: [String])
    case toolNotFound(String)
    case executionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingRequiredParameter(let name):
            return "Missing required parameter: \(name)"
        case .invalidParameterType(let name, let expected):
            return "Invalid type for parameter '\(name)'. Expected: \(expected)"
        case .invalidEnumValue(let name, let allowed):
            return "Invalid value for parameter '\(name)'. Allowed values: \(allowed.joined(separator: ", "))"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        }
    }
}