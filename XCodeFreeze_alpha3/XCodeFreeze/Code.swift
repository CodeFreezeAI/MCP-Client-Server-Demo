import SwiftUI
import MCP
import Logging
import Foundation
import AppKit
import System


// Server configuration
var MCP_SERVER_NAME = "XCF_MCP_SERVER" // Default value, will be overridden by config if available
let MCP_CLIENT_NAME = "XCodeFreeze"
let MCP_CLIENT_DEFAULT_VERSION = "1.0.0" // Default version for initial connection

// MARK: - Function to determine user home directory
private func getUserHomeDirectory() -> String {
    return FileManager.default.homeDirectoryForCurrentUser.path
}

// MARK: - Function to load MCP_SERVER_NAME from config (used as fallback)
func loadMCPServerNameFromConfig(customPath: String? = nil) {
    do {
        let config = try MCPConfig.loadConfig(customPath: customPath)
        
        // If we have servers in the config, use the first one as the default/fallback
        if !config.mcpServers.isEmpty {
            if let firstServerName = config.mcpServers.keys.first {
                MCP_SERVER_NAME = firstServerName
                print("Setting initial MCP_SERVER_NAME to: \(firstServerName) (from config - will be updated with actual server name later)")
            }
        }
    } catch {
        print("Could not load MCP_SERVER_NAME from config: \(error.localizedDescription)")
        print("Using default MCP_SERVER_NAME: \(MCP_SERVER_NAME) - will attempt to update with actual server name during connection")
    }
}

// MARK: - Tool Parameter Info
struct ToolParameterInfo {
    let name: String
    let isRequired: Bool
    let type: String
    let description: String?
    
    init(name: String, isRequired: Bool, type: String, description: String? = nil) {
        self.name = name
        self.isRequired = isRequired
        self.type = type
        self.description = description
    }
}

// MARK: - Tool Registry for storing discovered tools and parameter info
class ToolRegistry {
    static let shared = ToolRegistry()
    
    private var toolParameterMap: [String: [ToolParameterInfo]] = [:]
    private var subToolMap: [String: [String]] = [:]
    private var toolSchemaMap: [String: [String: String]] = [:] // Maps tool names to their parameter schemas
    private var toolDescriptionMap: [String: [String: String]] = [:] // Maps tool names to parameter descriptions
    private var toolExampleMap: [String: [String: String]] = [:] // Maps tool names to parameter examples
    
    func registerParameterInfo(for toolName: String, parameters: [ToolParameterInfo]) {
        toolParameterMap[toolName] = parameters
    }
    
    func registerSubTools(for toolName: String, subTools: [String]) {
        subToolMap[toolName] = subTools
    }
    
    func registerToolSchema(for toolName: String, schema: [String: String]) {
        toolSchemaMap[toolName] = schema
    }
    
    func registerToolParameterDescriptions(for toolName: String, descriptions: [String: String]) {
        toolDescriptionMap[toolName] = descriptions
    }
    
    func registerToolParameterExamples(for toolName: String, examples: [String: String]) {
        toolExampleMap[toolName] = examples
    }
    
    func getParameterInfo(for toolName: String) -> [ToolParameterInfo]? {
        return toolParameterMap[toolName]
    }
    
    func getSubTools(for toolName: String) -> [String]? {
        return subToolMap[toolName]
    }
    
    func getParameterDescription(for toolName: String, paramName: String) -> String? {
        return toolDescriptionMap[toolName]?[paramName]
    }
    
    func getParameterExample(for toolName: String, paramName: String) -> String? {
        return toolExampleMap[toolName]?[paramName]
    }
    
    func getToolSchema(for toolName: String) -> [String: String]? {
        return toolSchemaMap[toolName]
    }
    
    func getParameterName(for toolName: String) -> String {
        // First check if we have discovered schema info for this tool
        if let schema = toolSchemaMap[toolName], !schema.isEmpty {
            // Use the first parameter from the schema
            if let firstParam = schema.keys.first {
                return firstParam
            }
        }
        
        // Second check if we have registered parameter info
        if let parameters = getParameterInfo(for: toolName), !parameters.isEmpty {
            return parameters[0].name
        }
        
        // Default to "text" if we don't have any info
        return "text"
    }
    
    // Add a function to check if schema was discovered
    func hasDiscoveredSchema(for toolName: String) -> Bool {
        return toolSchemaMap[toolName] != nil
    }
    
    // Add method to get parameter discovery source
    func getParameterSource(for toolName: String) -> String {
        if toolSchemaMap[toolName] != nil {
            return "(schema-discovered)"
        } else if toolParameterMap[toolName] != nil {
            return "(registered)"
        } else {
            return "(default-fallback)"
        }
    }
    
    func clear() {
        toolParameterMap.removeAll()
        subToolMap.removeAll()
        toolSchemaMap.removeAll()
        toolDescriptionMap.removeAll()
        toolExampleMap.removeAll()
    }
}

// MARK: - MCP Config
struct MCPConfig: Codable {
    let mcpServers: [String: ServerConfig]
    
    struct ServerConfig: Codable {
        let type: String?
        let command: String
        let args: [String]?
        let env: [String: String]?
        
        enum CodingKeys: String, CodingKey {
            case type, command, args, env
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Required field
            command = try container.decode(String.self, forKey: .command)
            
            // Optional fields with default values
            type = try container.decodeIfPresent(String.self, forKey: .type)
            args = try container.decodeIfPresent([String].self, forKey: .args)
            env = try container.decodeIfPresent([String: String].self, forKey: .env)
        }
    }
    
    static func loadConfig(customPath: String? = nil) throws -> MCPConfig {
        // If a custom path is provided, use it
        if let customPath = customPath, !customPath.isEmpty {
            print("Attempting to load MCP config from custom path: \(customPath)")
            
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: customPath) {
                let data = try Data(contentsOf: URL(fileURLWithPath: customPath))
                print("Config file loaded from custom path, size: \(data.count) bytes")
                
                // First validate JSON structure
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    
                    // Check if mcpServers key exists
                    guard let mcpServers = json?["mcpServers"] as? [String: Any], !mcpServers.isEmpty else {
                        throw NSError(domain: "MCPConfig", code: 400, userInfo: [NSLocalizedDescriptionKey: "Config file is missing or has empty 'mcpServers' section. Please add server configuration."])
                    }
                    
                    // Check at least one server configuration
                    let serverKeys = mcpServers.keys
                    print("Found servers in config: \(serverKeys.joined(separator: ", "))")
                    
                    // Check that servers have required fields
                    for (serverName, serverConfig) in mcpServers {
                        guard let serverDict = serverConfig as? [String: Any],
                              let _ = serverDict["command"] as? String else {
                            throw NSError(domain: "MCPConfig", code: 400, userInfo: [NSLocalizedDescriptionKey: "Server '\(serverName)' is missing required 'command' field."])
                        }
                    }
                } catch let validationError as NSError {
                    if validationError.domain == "MCPConfig" {
                        throw validationError
                    } else {
                        throw NSError(domain: "MCPConfig", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format: \(validationError.localizedDescription)"])
                    }
                }
                
                // If validation passes, decode normally
                let decoder = JSONDecoder()
                let config = try decoder.decode(MCPConfig.self, from: data)
                
                // Set initial MCP_SERVER_NAME from config
                if !config.mcpServers.isEmpty {
                    if let firstServerName = config.mcpServers.keys.first {
                        MCP_SERVER_NAME = firstServerName
                        print("Setting initial MCP_SERVER_NAME to: \(firstServerName) (from config - will be updated with actual server name later)")
                    }
                }
                
                return config
            } else {
                print("Custom config file does not exist at path: \(customPath)")
                throw NSError(domain: "MCPConfig", code: 404, userInfo: [NSLocalizedDescriptionKey: "Specified config file does not exist: \(customPath)"])
            }
        }
        
        // Try the path from UserDefaults if available
        if let savedPath = UserDefaults.standard.string(forKey: "savedConfigPath"), !savedPath.isEmpty {
            print("Checking saved config path from UserDefaults: \(savedPath)")
            
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: savedPath) {
                let data = try Data(contentsOf: URL(fileURLWithPath: savedPath))
                print("Config file loaded from saved path, size: \(data.count) bytes")
                
                // Validate JSON structure
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    
                    // Check if mcpServers key exists
                    guard let mcpServers = json?["mcpServers"] as? [String: Any], !mcpServers.isEmpty else {
                        throw NSError(domain: "MCPConfig", code: 400, userInfo: [NSLocalizedDescriptionKey: "Config file is missing or has empty 'mcpServers' section. Please add server configuration."])
                    }
                    
                    // Check at least one server configuration
                    let serverKeys = mcpServers.keys
                    print("Found servers in config: \(serverKeys.joined(separator: ", "))")
                    
                    // Check that servers have required fields
                    for (serverName, serverConfig) in mcpServers {
                        guard let serverDict = serverConfig as? [String: Any],
                              let _ = serverDict["command"] as? String else {
                            throw NSError(domain: "MCPConfig", code: 400, userInfo: [NSLocalizedDescriptionKey: "Server '\(serverName)' is missing required 'command' field."])
                        }
                    }
                } catch let validationError as NSError {
                    if validationError.domain == "MCPConfig" {
                        throw validationError
                    } else {
                        throw NSError(domain: "MCPConfig", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format: \(validationError.localizedDescription)"])
                    }
                }
                
                // If validation passes, decode normally
                let decoder = JSONDecoder()
                let config = try decoder.decode(MCPConfig.self, from: data)
                
                // Set initial MCP_SERVER_NAME from config
                if !config.mcpServers.isEmpty {
                    if let firstServerName = config.mcpServers.keys.first {
                        MCP_SERVER_NAME = firstServerName
                        print("Setting initial MCP_SERVER_NAME to: \(firstServerName) (from config - will be updated with actual server name later)")
                    }
                }
                
                return config
            } else {
                print("Saved config file does not exist at path: \(savedPath)")
                throw NSError(domain: "MCPConfig", code: 404, userInfo: [NSLocalizedDescriptionKey: "Saved config file no longer exists: \(savedPath)"])
            }
        }
        
        // If we get here, no config file was found
        throw NSError(domain: "MCPConfig", code: 404, userInfo: [NSLocalizedDescriptionKey: "No configuration file selected. Please select or create a configuration file."])
    }
}


// MARK: - Message View
struct MessageView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(message.sender)
                    .font(.headline)
                    .foregroundColor(senderColor)
                
                Spacer()
                
                Text(message.timestamp, formatter: timeFormatter)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Text(message.content)
                .padding(8)
                .background(message.isFromServer ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(8)
                .textSelection(.enabled)  // Enable text selection
        }
        .padding(.vertical, 4)
    }
    
    private var senderColor: Color {
        switch message.sender {
        case "Server":
            return Color(red: 0.0, green: 0.7, blue: 0.0)  // Slightly darker medium green
        case "Client":
            return Color(red: 0.95, green: 0.5, blue: 0.0)  // Slightly darker medium orange
        case "You":
            return .blue
        default:
            return .primary
        }
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Chat Message Model
struct ChatMessage: Identifiable {
    let id = UUID()
    let sender: String
    let content: String
    let timestamp: Date
    let isFromServer: Bool
}

// MARK: - MCP Tool Model
struct MCPTool {
    let name: String
    let description: String
}

