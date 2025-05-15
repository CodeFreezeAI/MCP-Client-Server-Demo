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
    
    private var availableTools: [MCPTool] = []
    private var subTools: [String: [String]] = [:]
    private var schemaMap: [String: [String: String]] = [:]
    private var parameterDescriptions: [String: [String: String]] = [:]
    private var parameterExamples: [String: [String: String]] = [:]
    private var parameterInfoMap: [String: [ToolParameterInfo]] = [:]
    
    private init() {}
    
    // MARK: - Tool Registration
    
    func registerTools(_ tools: [MCPTool]) {
        availableTools = tools
    }
    
    func getAvailableTools() -> [MCPTool] {
        return availableTools
    }
    
    // MARK: - Sub-tool Registration
    
    func registerSubTools(for server: String, subTools: [String]) {
        self.subTools[server] = subTools
    }
    
    func getSubTools(for server: String) -> [String]? {
        return subTools[server]
    }
    
    // MARK: - Schema Registration
    
    func registerToolSchema(for tool: String, schema: [String: String]) {
        schemaMap[tool] = schema
    }
    
    func getToolSchema(for tool: String) -> [String: String]? {
        schemaMap[tool]
    }
    
    func hasDiscoveredSchema(for tool: String) -> Bool {
        schemaMap[tool] != nil
    }
    
    // MARK: - Parameter Info Registration
    
    func registerParameterInfo(for tool: String, parameters: [ToolParameterInfo]) {
        parameterInfoMap[tool] = parameters
    }
    
    func getParameterInfo(for tool: String) -> [ToolParameterInfo]? {
        return parameterInfoMap[tool]
    }
    
    func registerToolParameterDescriptions(for tool: String, descriptions: [String: String]) {
        parameterDescriptions[tool] = descriptions
    }
    
    func getParameterDescription(for tool: String, paramName: String) -> String? {
        parameterDescriptions[tool]?[paramName]
    }
    
    func registerToolParameterExamples(for tool: String, examples: [String: String]) {
        parameterExamples[tool] = examples
    }
    
    func getParameterExample(for tool: String, paramName: String) -> String? {
        parameterExamples[tool]?[paramName]
    }
    
    // MARK: - Parameter Name Resolution
    
    func getParameterName(for tool: String) -> String {
        // First check if we have explicit parameter info for this tool
        if let params = parameterInfoMap[tool], let first = params.first {
            return first.name
        }
        
        // Next, check if we have schema info for this tool
        if let schema = schemaMap[tool], let first = schema.keys.first {
            return first
        }
        
        // If tool is a server action, use the parameter name for the server
        for (server, actions) in subTools {
            if actions.contains(tool) {
                if let serverSchema = schemaMap[server], let first = serverSchema.keys.first {
                    return first
                }
            }
        }
        
        // Default fallback
        return "text"
    }
    
    func getParameterSource(for tool: String) -> String {
        // For debugging - gives info about how the parameter name was determined
        if let params = parameterInfoMap[tool], let _ = params.first {
            return "(from registered parameter info)"
        } else if let schema = schemaMap[tool], let _ = schema.keys.first {
            return "(from schema)"
        } else {
            for (_, actions) in subTools {
                if actions.contains(tool) {
                    return "(from server action parameter)"
                }
            }
            return "(default)"
        }
    }
} 
