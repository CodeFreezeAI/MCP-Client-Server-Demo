import Foundation

// MARK: - Tool Info Models
struct MCPTool {
    let name: String
    let description: String
}

struct ToolParameterInfo {
    let name: String
    let isRequired: Bool
    let type: String
    let description: String?
}

// MARK: - Tool Registry (Singleton)
class ToolRegistry {
    static let shared = ToolRegistry()
    
    private let concurrentQueue = DispatchQueue(label: "com.mcp.toolregistry.queue", attributes: .concurrent)
    
    private var availableTools: [MCPTool] = []
    private var subTools: [String: [String]] = [:]
    private var schemaMap: [String: [String: String]] = [:]
    private var parameterDescriptions: [String: [String: String]] = [:]
    private var parameterExamples: [String: [String: String]] = [:]
    private var parameterInfoMap: [String: [ToolParameterInfo]] = [:]
    
    private init() {}
    
    // MARK: - Tool Registration
    
    func registerTools(_ tools: [MCPTool]) {
        concurrentQueue.async(flags: .barrier) { [weak self] in
            self?.availableTools = tools
        }
    }
    
    func getAvailableTools() -> [MCPTool] {
        var result: [MCPTool] = []
        concurrentQueue.sync {
            result = self.availableTools
        }
        return result
    }
    
    // MARK: - Sub-tool Registration
    
    func registerSubTools(for server: String, subTools: [String]) {
        concurrentQueue.async(flags: .barrier) { [weak self] in
            self?.subTools[server] = subTools
        }
    }
    
    func getSubTools(for server: String) -> [String]? {
        var result: [String]?
        concurrentQueue.sync {
            result = self.subTools[server]
        }
        return result
    }
    
    // MARK: - Schema Registration
    
    func registerToolSchema(for tool: String, schema: [String: String]) {
        concurrentQueue.async(flags: .barrier) { [weak self] in
            self?.schemaMap[tool] = schema
        }
    }
    
    func getToolSchema(for tool: String) -> [String: String]? {
        var result: [String: String]?
        concurrentQueue.sync {
            result = self.schemaMap[tool]
        }
        return result
    }
    
    func hasDiscoveredSchema(for tool: String) -> Bool {
        var result = false
        concurrentQueue.sync {
            result = self.schemaMap[tool] != nil
        }
        return result
    }
    
    // MARK: - Parameter Info Registration
    
    func registerParameterInfo(for tool: String, parameters: [ToolParameterInfo]) {
        concurrentQueue.async(flags: .barrier) { [weak self] in
            self?.parameterInfoMap[tool] = parameters
        }
    }
    
    func getParameterInfo(for tool: String) -> [ToolParameterInfo]? {
        var result: [ToolParameterInfo]?
        concurrentQueue.sync {
            result = self.parameterInfoMap[tool]
        }
        return result
    }
    
    func registerToolParameterDescriptions(for tool: String, descriptions: [String: String]) {
        concurrentQueue.async(flags: .barrier) { [weak self] in
            self?.parameterDescriptions[tool] = descriptions
        }
    }
    
    func getParameterDescription(for tool: String, paramName: String) -> String? {
        var result: String?
        concurrentQueue.sync {
            result = self.parameterDescriptions[tool]?[paramName]
        }
        return result
    }
    
    func registerToolParameterExamples(for tool: String, examples: [String: String]) {
        concurrentQueue.async(flags: .barrier) { [weak self] in
            self?.parameterExamples[tool] = examples
        }
    }
    
    func getParameterExample(for tool: String, paramName: String) -> String? {
        var result: String?
        concurrentQueue.sync {
            result = self.parameterExamples[tool]?[paramName]
        }
        return result
    }
    
    // MARK: - Parameter Name Resolution
    
    func getParameterName(for tool: String) -> String {
        var result = "text" // Default fallback
        
        concurrentQueue.sync {
            // First check if we have explicit parameter info for this tool
            if let params = self.parameterInfoMap[tool], let first = params.first {
                result = first.name
                return
            }
            
            // Next, check if we have schema info for this tool
            if let schema = self.schemaMap[tool], let first = schema.keys.first {
                result = first
                return
            }
            
            // If tool is a server action, use the parameter name for the server
            for (server, actions) in self.subTools {
                if actions.contains(tool) {
                    if let serverSchema = self.schemaMap[server], let first = serverSchema.keys.first {
                        result = first
                        return
                    }
                }
            }
        }
        
        return result
    }
    
    func getParameterSource(for tool: String) -> String {
        var result = "(default)"
        
        concurrentQueue.sync {
            // For debugging - gives info about how the parameter name was determined
            if let params = self.parameterInfoMap[tool], let _ = params.first {
                result = "(from registered parameter info)"
                return
            } else if let schema = self.schemaMap[tool], let _ = schema.keys.first {
                result = "(from schema)"
                return
            } else {
                for (_, actions) in self.subTools {
                    if actions.contains(tool) {
                        result = "(from server action parameter)"
                        return
                    }
                }
            }
        }
        
        return result
    }
} 
