//
//  CommandService.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import Foundation

/// Service for processing and executing commands
class CommandService {
    /// Singleton instance
    static let shared = CommandService()
    
    private init() {}
    
    /// Process a user input command and determine the appropriate tool and arguments
    /// - Parameters:
    ///   - inputText: The raw user input
    ///   - availableTools: Available tools to check against
    /// - Returns: A tuple containing the tool name and arguments
    func processCommand(inputText: String, availableTools: [MCPTool]) -> (toolName: String, args: String) {
        // Store original input for debugging
        let originalInput = inputText
        
        // Special handling for "use [server]" which is a common command
        if originalInput.lowercased() == "use \(MCP_SERVER_NAME)" {
            print("Detected special 'use \(MCP_SERVER_NAME)' command")
            let toolName = MCP_SERVER_NAME
            let toolArgs = "use \(MCP_SERVER_NAME)"
            print("Transformed to: \(MCP_SERVER_NAME) action='use \(MCP_SERVER_NAME)'")
            return (toolName, toolArgs)
        }
        
        // Extract the tool name and arguments
        let components = inputText.split(separator: " ", maxSplits: 1)
        var toolName = String(components[0])
        var toolArgs = components.count > 1 ? String(components[1]) : ""
        
        // Check if this is a direct server command
        var isKnownCommand = false
        
        // Special handling for server sub-tools
        if let serverActions = ToolRegistry.shared.getSubTools(for: MCP_SERVER_NAME) {
            // Case 1: Direct server command like "xcf help"
            if toolName.lowercased() == MCP_SERVER_NAME {
                // Already properly formatted, no need to change
                print("Direct \(MCP_SERVER_NAME) command: \(toolName) action=\(toolArgs)")
                isKnownCommand = true
            }
            // Case 2: First token is a server action like "help" or "grant"
            else if serverActions.contains(where: { $0.lowercased() == toolName.lowercased() }) {
                print("Detected direct \(MCP_SERVER_NAME) action: \(toolName) with args: \(toolArgs)")
                toolArgs = toolArgs.isEmpty ? toolName : "\(toolName) \(toolArgs)"
                toolName = MCP_SERVER_NAME
                print("Transformed to: \(toolName) action=\(toolArgs)")
                isKnownCommand = true
            }
            // Case 3: Handle special cases
            else {
                // See if any server action is a prefix of the command
                for action in serverActions {
                    if toolName.lowercased() == action.lowercased() && !toolArgs.isEmpty {
                        // This is a multi-word server command - the first word is a server action
                        print("Detected multi-word \(MCP_SERVER_NAME) command starting with \(action): \(originalInput)")
                        toolArgs = originalInput // Pass the entire command as the action
                        toolName = MCP_SERVER_NAME
                        print("Transformed to: \(toolName) action=\(toolArgs)")
                        isKnownCommand = true
                        break
                    }
                }
            }
        }
        
        // Check if the command is a known tool
        if !isKnownCommand {
            let isKnownTool = availableTools.contains(where: { $0.name == toolName })
            
            // If it's not a known tool and has multiple words, assume it's a server command
            if !isKnownTool && components.count > 1 {
                print("Unrecognized multi-word command: \(originalInput). Treating as \(MCP_SERVER_NAME) command.")
                toolName = MCP_SERVER_NAME
                toolArgs = originalInput
                print("Transformed to: \(toolName) action=\(toolArgs)")
            }
        }
        
        return (toolName, toolArgs)
    }
} 