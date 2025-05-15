import SwiftUI
import MCP
import Logging
import Foundation
import AppKit
import System

// MARK: - MCP Server Configuration Functions

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