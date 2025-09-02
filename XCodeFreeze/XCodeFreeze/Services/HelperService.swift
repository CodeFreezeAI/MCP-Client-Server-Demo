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
        
        // Send to AI if:
        // 1. Starts with "@ai" or "/ai"
        // 2. Is a natural language question/request
        // 3. Contains keywords that suggest AI assistance
        
        if trimmed.lowercased().hasPrefix("@ai ") || trimmed.lowercased().hasPrefix("/ai ") {
            return true
        }
        
        // Check if it looks like a natural language query rather than a tool command
        let aiKeywords = ["help", "explain", "how", "what", "why", "can you", "please", "write", "create", "implement", "fix", "debug", "optimize"]
        let lowerInput = trimmed.lowercased()
        
        // If it contains AI keywords and doesn't look like a tool command, send to AI
        if aiKeywords.contains(where: { lowerInput.contains($0) }) && !lowerInput.contains(" --") && !lowerInput.contains("xcf ") {
            return true
        }
        
        // Default: send to MCP tools for backwards compatibility
        return false
    }
}

// End of HelperService
