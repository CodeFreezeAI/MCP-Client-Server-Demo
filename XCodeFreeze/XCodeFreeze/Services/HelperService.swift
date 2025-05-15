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
        
        let (toolName, toolArgs) = commandService.processCommand(
            inputText: inputText,
            availableTools: viewModel.availableTools
        )
        
        Task {
            await viewModel.callTool(name: toolName, text: toolArgs)
            await uiService.clearAndFocusInput(text: textBinding, focusState: focusState)
        }
    }
} 
