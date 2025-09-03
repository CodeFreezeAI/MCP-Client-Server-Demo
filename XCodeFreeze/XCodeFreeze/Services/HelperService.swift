//
//  HelperService.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI

/// Service for handling helper functions from ContentView
class HelperService {
    /// Singleton instance
    static let shared = HelperService()
    
    // Services
    private let uiService = UIService.shared
    private let configService = ConfigFileService.shared
    private let commandService = CommandService.shared
    
    private init() {}
    
    /// Handles connection to the server and post-connection UI updates
    func connectToServer(viewModel: MCPViewModel, configPath: String, focusState: FocusState<Bool>.Binding) {
        Task {
            await viewModel.startClientServer(configPath: configPath)
            await uiService.setFocus(focusState, to: true)
        }
    }
    
    /// Handles selecting a config file using the ConfigFileService
    func selectConfigFile() -> String? {
        return configService.selectConfigFile()
    }
    
    /// Handles creating a new config file using the ConfigFileService
    func createNewConfigFile(messageHandler: @escaping (String) -> Void) -> String? {
        return configService.createNewConfigFile(messageHandler: messageHandler)
    }
    
    /// Processes and submits the current message
    func submitMessage(inputText: String, 
                      viewModel: MCPViewModel, 
                      textBinding: Binding<String>,
                      focusState: FocusState<Bool>.Binding) {
        guard !inputText.isEmpty else { return }
        
        // Check if message should go to AI or MCP tools
        if shouldSendToAI(inputText: inputText, availableTools: viewModel.availableTools) {
            submitToAI(inputText: inputText, viewModel: viewModel, textBinding: textBinding, focusState: focusState)
        } else {
            submitToMCP(inputText: inputText, viewModel: viewModel, textBinding: textBinding, focusState: focusState)
        }
    }
    
    /// Submit message to AI service
    private func submitToAI(inputText: String,
                           viewModel: MCPViewModel,
                           textBinding: Binding<String>,
                           focusState: FocusState<Bool>.Binding) {
        Task {
            await viewModel.sendToAI(inputText, includeThinking: true)
            await uiService.clearAndFocusInput(text: textBinding, focusState: focusState)
        }
    }
    
    /// Submit message to MCP tools
    private func submitToMCP(inputText: String,
                            viewModel: MCPViewModel,
                            textBinding: Binding<String>,
                            focusState: FocusState<Bool>.Binding) {
        // Apply command mapping first
        let mappedInput = mapInputToCommand(inputText, availableTools: viewModel.availableTools)
        
        let (toolName, toolArgs) = commandService.processCommand(
            inputText: mappedInput,
            availableTools: viewModel.availableTools
        )
        
        Task {
            await viewModel.callTool(name: toolName, text: toolArgs)
            await uiService.clearAndFocusInput(text: textBinding, focusState: focusState)
        }
    }
    
    /// Map user-friendly input to actual MCP commands
    private func mapInputToCommand(_ inputText: String, availableTools: [MCPTool]) -> String {
        let lowerInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let discoveredToolNames = availableTools.map { $0.name.lowercased() }
        
        // Handle "use [tool_name]" pattern - strip "use " prefix
        if lowerInput.hasPrefix("use ") {
            return String(lowerInput.dropFirst(4)) // Remove "use "
        }
        
        // Dynamic mapping: convert "word word" to "word_word" if that tool exists
        let spaceToUnderscore = lowerInput.replacingOccurrences(of: " ", with: "_")
        if discoveredToolNames.contains(spaceToUnderscore) {
            return spaceToUnderscore
        }
        
        // Handle dynamic command shortcuts with arguments
        let inputParts = lowerInput.split(separator: " ")
        if let firstWord = inputParts.first, inputParts.count > 1 {
            let firstWordStr = String(firstWord)
            let remainingArgs = inputParts.dropFirst().joined(separator: " ")
            
            // Look for tools that start with the first word followed by underscore
            for toolName in discoveredToolNames {
                if toolName.hasPrefix(firstWordStr + "_") {
                    return "\(toolName) \(remainingArgs)"
                }
            }
        }
        
        return inputText
    }
    
    /// Determine whether message should be sent to AI or MCP tools
    private func shouldSendToAI(inputText: String, availableTools: [MCPTool]) -> Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Send to MCP tools directly if:
        // 1. Starts with explicit MCP tool commands
        // 2. Contains MCP-specific patterns
        // 3. Matches known tool names (with variations)
        // 4. Matches any discovered tool from listTools()
        
        let mcpPatterns = ["xcf ", "mcp__", "--", "diagnostics", "debug"]
        let lowerInput = trimmed.lowercased()
        
        // Check for explicit MCP tool commands
        if mcpPatterns.contains(where: { lowerInput.hasPrefix($0) }) {
            return false
        }
        
        // Check against dynamically discovered tools from listTools()
        let discoveredToolNames = availableTools.map { $0.name.lowercased() }
        
        // Check for exact tool name match or tool name with arguments
        if discoveredToolNames.contains(where: { toolName in
            lowerInput == toolName || lowerInput.hasPrefix(toolName + " ")
        }) {
            return false
        }
        
        // Check if "word word" maps to "word_word" tool
        let spaceToUnderscore = lowerInput.replacingOccurrences(of: " ", with: "_")
        if discoveredToolNames.contains(spaceToUnderscore) {
            return false
        }
        
        // Handle "use [tool_name]" pattern - check if any discovered tool matches
        if lowerInput.hasPrefix("use ") {
            let toolPart = String(lowerInput.dropFirst(4)) // Remove "use "
            if discoveredToolNames.contains(toolPart) {
                return false
            }
        }
        
        // Handle partial matches and variations dynamically
        let inputWords = lowerInput.split(separator: " ")
        if let firstWord = inputWords.first {
            let firstWordStr = String(firstWord)
            
            // Check if first word matches any discovered tool exactly
            if discoveredToolNames.contains(firstWordStr) {
                return false
            }
            
            // Check for reasonable partial matches (tool names with underscores)
            if discoveredToolNames.contains(where: { toolName in
                toolName.hasPrefix(firstWordStr + "_")
            }) {
                return false
            }
        }
        
        // Default: send to AI for natural conversation
        // This makes it a true chat interface where AI can use tools as needed
        return true
    }
}

// End of HelperService
