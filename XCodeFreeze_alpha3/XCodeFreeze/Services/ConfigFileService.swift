//
//  ConfigFileService.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI
import AppKit
import Foundation

/// Service for handling configuration file operations
class ConfigFileService {
    /// Singleton instance
    static let shared = ConfigFileService()
    
    private init() {}
    
    /// Select a configuration file using an open dialog
    /// - Returns: The selected file path or nil if canceled
    func selectConfigFile() -> String? {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select JSON Config File"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.json]
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                // Save to UserDefaults
                UserDefaults.standard.set(url.path, forKey: "savedConfigPath")
                return url.path
            }
        }
        return nil
    }
    
    /// Create a new configuration file with a template
    /// - Parameter messageHandler: A closure that handles messages about the file creation process
    /// - Returns: The new file path or nil if canceled
    func createNewConfigFile(messageHandler: @escaping (String) -> Void) -> String? {
        let savePanel = NSSavePanel()
        savePanel.title = "Create New JSON Config File"
        savePanel.nameFieldStringValue = "mcp.json"
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.json]
        
        if savePanel.runModal() == .OK {
            if let url = savePanel.url {
                // Save to UserDefaults
                UserDefaults.standard.set(url.path, forKey: "savedConfigPath")
                
                // Create a helpful template with examples
                let templateConfig = """
                {
                    "mcpServers": {
                        "XCF_MCP_SERVER": {
                            "type": "stdio",
                            "command": "/usr/local/bin/xcf",
                            "args": [],
                            "env": {}
                        },
                        "filesystem": {
                            "type": "stdio",
                            "command": "npx",
                            "args": ["@anthropic-ai/mcp-filesystem"],
                            "env": {}
                        }
                    }
                }
                """
                
                do {
                    try templateConfig.write(to: url, atomically: true, encoding: .utf8)
                    // Show success messages
                    messageHandler("Created new config file at: \(url.path)")
                    messageHandler("IMPORTANT: Update the 'command' path to point to your xcf executable")
                    messageHandler("The server name must match MCP_SERVER_NAME in the code (XCF_MCP_SERVER)")
                } catch {
                    // Show error message
                    messageHandler("Error creating config file: \(error.localizedDescription)")
                }
                
                return url.path
            }
        }
        return nil
    }
    
    /// Loads the saved configuration path from UserDefaults
    /// - Returns: The saved path or an empty string if none exists
    func loadSavedConfigPath() -> String {
        return UserDefaults.standard.string(forKey: "savedConfigPath") ?? ""
    }
    
    /// Saves a configuration path to UserDefaults
    /// - Parameter path: The path to save
    func saveConfigPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: "savedConfigPath")
    }
} 