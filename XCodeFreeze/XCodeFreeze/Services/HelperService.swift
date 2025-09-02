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
        if shouldSendToAI(inputText: inputText) {
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
        let (toolName, toolArgs) = commandService.processCommand(
            inputText: inputText,
            availableTools: viewModel.availableTools
        )
        
        Task {
            await viewModel.callTool(name: toolName, text: toolArgs)
            await uiService.clearAndFocusInput(text: textBinding, focusState: focusState)
        }
    }
    
    /// Determine whether message should be sent to AI or MCP tools
    private func shouldSendToAI(inputText: String) -> Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Send to MCP tools directly if:
        // 1. Starts with explicit MCP tool commands
        // 2. Contains MCP-specific patterns
        
        let mcpPatterns = ["xcf ", "mcp__", "--", "diagnostics", "debug"]
        let lowerInput = trimmed.lowercased()
        
        // Check for explicit MCP tool commands
        if mcpPatterns.contains(where: { lowerInput.hasPrefix($0) }) {
            return false
        }
        
        // Check for tool names from available tools - if it matches, send to MCP
        // This will be handled by checking against actual available tools
        
        // Default: send to AI for natural conversation
        // This makes it a true chat interface where AI can use tools as needed
        return true
    }
}

// End of HelperService
