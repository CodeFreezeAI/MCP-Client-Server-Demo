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

// MARK: - Function to load server name from config (used as fallback)
func loadServerNameFromConfig(customPath: String? = nil) {
    do {
        let config = try MCPConfig.loadConfig(customPath: customPath)
        
        // If we have servers in the config, use the first one as the default/fallback
        if !config.mcpServers.isEmpty {
            if let firstServerName = config.mcpServers.keys.first {
                MCPConstants.Server.name = firstServerName
                // Initial server name setting shown via UI
            }
        }
    } catch {
        LoggingService.shared.error(String(format: MCPConstants.Messages.ServerConfig.couldNotLoadServerName, error.localizedDescription))
        // Default server name message shown via UI
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
    
    // MARK: - Load Config
    
    static func loadConfig(customPath: String? = nil) throws -> MCPConfig {
        // First, try custom path if provided
        if let customPath = customPath {
            // Loading message shown via UI
            
            let customURL = URL(fileURLWithPath: customPath)
            
            if FileManager.default.fileExists(atPath: customPath) {
                let data = try Data(contentsOf: customURL)
                // Config loaded message shown via UI
                
                // Basic validation to ensure it's valid JSON
                do {
                    _ = try JSONSerialization.jsonObject(with: data, options: [])
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
                
                // Log found servers
                let serverKeys = Array(config.mcpServers.keys)
                // Server discovery message shown via UI
                
                // Set initial server name from config
                if !config.mcpServers.isEmpty {
                    if let firstServerName = config.mcpServers.keys.first {
                        MCPConstants.Server.name = firstServerName
                        // Server name setting shown via UI
                    }
                }
                
                return config
            } else {
                LoggingService.shared.warning(String(format: MCPConstants.Messages.ServerConfig.customConfigNotExist, customPath))
                throw NSError(domain: "MCPConfig", code: 404, userInfo: [NSLocalizedDescriptionKey: "Specified config file does not exist: \(customPath)"])
            }
        }
        
        // Try the path from UserDefaults if available
        if let savedPath = UserDefaults.standard.string(forKey: "mcpConfigPath") {
            // Saved config check shown via UI
            
            let savedURL = URL(fileURLWithPath: savedPath)
            
            if FileManager.default.fileExists(atPath: savedPath) {
                let data = try Data(contentsOf: savedURL)
                // Saved config loaded message shown via UI
                
                // Basic validation to ensure it's valid JSON
                do {
                    _ = try JSONSerialization.jsonObject(with: data, options: [])
                } catch {
                    throw NSError(domain: "MCPConfig", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format in saved config: \(error.localizedDescription)"])
                }
                
                // If validation passes, decode normally
                let decoder = JSONDecoder()
                let config = try decoder.decode(MCPConfig.self, from: data)
                
                // Log found servers
                let serverKeys = Array(config.mcpServers.keys)
                // Server discovery message shown via UI
                
                // Set initial server name from config
                if !config.mcpServers.isEmpty {
                    if let firstServerName = config.mcpServers.keys.first {
                        MCPConstants.Server.name = firstServerName
                        // Server name setting shown via UI
                    }
                }
                
                return config
            } else {
                LoggingService.shared.warning(String(format: MCPConstants.Messages.ServerConfig.savedConfigNotExist, savedPath))
            }
        }
        
        // Default to using an empty config
        return MCPConfig(mcpServers: [:])
    }
} 