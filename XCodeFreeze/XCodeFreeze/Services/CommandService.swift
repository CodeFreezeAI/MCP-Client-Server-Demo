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
        if originalInput.lowercased() == "use \(MCPConstants.Server.name)" {
            LoggingService.shared.debug(String(format: MCPConstants.Messages.Command.detectedSpecialCommand, MCPConstants.Server.name))
            let toolName = MCPConstants.Server.name
            let toolArgs = "use \(MCPConstants.Server.name)"
            LoggingService.shared.debug(String(format: MCPConstants.Messages.Command.transformedSpecialCommand, MCPConstants.Server.name, MCPConstants.Server.name))
            return (toolName, toolArgs)
        }
        
        // Extract the tool name and arguments
        let components = inputText.split(separator: " ", maxSplits: 1)
        var toolName = String(components[0])
        var toolArgs = components.count > 1 ? String(components[1]) : ""
        
        // Check if this is a direct server command
        var isKnownCommand = false
        
        // Special handling for server sub-tools
        if let serverActions = ToolRegistry.shared.getSubTools(for: MCPConstants.Server.name) {
            // Case 1: Direct server command like "xcf help"
            if toolName.lowercased() == MCPConstants.Server.name.lowercased() {
                // Already properly formatted, no need to change
                LoggingService.shared.debug(String(format: MCPConstants.Messages.Command.directCommand, MCPConstants.Server.name, toolName, toolArgs))
                isKnownCommand = true
            }
            // Case 2: First token is a server action like "help" or "grant"
            else if serverActions.contains(where: { $0.lowercased() == toolName.lowercased() }) {
                LoggingService.shared.debug(String(format: MCPConstants.Messages.Command.detectedDirectAction, MCPConstants.Server.name, toolName, toolArgs))
                toolArgs = toolArgs.isEmpty ? toolName : "\(toolName) \(toolArgs)"
                toolName = MCPConstants.Server.name
                LoggingService.shared.debug(String(format: MCPConstants.Messages.Command.transformedAction, toolName, toolArgs))
                isKnownCommand = true
            }
            // Case 3: Handle special cases
            else {
                // See if any server action is a prefix of the command
                for action in serverActions {
                    if toolName.lowercased() == action.lowercased() && !toolArgs.isEmpty {
                        // This is a multi-word server command - the first word is a server action
                        LoggingService.shared.debug(String(format: MCPConstants.Messages.Command.detectedMultiwordCommand, MCPConstants.Server.name, action, originalInput))
                        toolArgs = originalInput // Pass the entire command as the action
                        toolName = MCPConstants.Server.name
                        LoggingService.shared.debug(String(format: MCPConstants.Messages.Command.transformedAction, toolName, toolArgs))
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
                LoggingService.shared.debug(String(format: MCPConstants.Messages.Command.unrecognizedMultiwordCommand, originalInput, MCPConstants.Server.name))
                toolName = MCPConstants.Server.name
                toolArgs = originalInput
                LoggingService.shared.debug(String(format: MCPConstants.Messages.Command.transformedAction, toolName, toolArgs))
            }
        }
        
        return (toolName, toolArgs)
    }
} 