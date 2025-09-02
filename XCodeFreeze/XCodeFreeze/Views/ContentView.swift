//
//  ContentView.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/13/25.
//

import SwiftUI

// MARK: - Main View
struct ContentView: View {
    @StateObject private var viewModel = MCPViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State var configFilePath = ConfigFileService.shared.loadSavedConfigPath()
    @State private var showConfigAlert = false
    
    // Services
    private let uiService = UIService.shared
    private let configService = ConfigFileService.shared
    private let commandService = CommandService.shared
    private let helperService = HelperService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Single-line JSON-style header with all controls
            JSONHeaderView(
                configFilePath: $configFilePath,
                isConnected: viewModel.isConnected,
                showConfigAlert: $showConfigAlert,
                viewModel: viewModel,
                helperService: helperService,
                aiService: AIService.shared
            )
            
            // Chat area with auto-scrolling
            ChatView(
                messages: viewModel.messages,
                uiService: uiService
            )
            
            // Input area
            InputBarView(
                inputText: $inputText,
                isInputFocused: _isInputFocused,
                isConnected: viewModel.isConnected,
                viewModel: viewModel,
                uiService: uiService,
                helperService: helperService
            )
            
            // Tool list section
            ToolsListView(
                availableTools: viewModel.availableTools,
                serverSubtools: viewModel.serverSubtools,
                inputText: $inputText,
                uiService: uiService,
                isInputFocused: _isInputFocused
            )
        }
        .padding(.top, 0)
        .padding(.horizontal, 15)
        .padding(.bottom, 15)
        .onAppear {
            handleOnAppear()
        }
        .onDisappear {
            viewModel.stopClientServer()
        }
    }
    
    /// Handle setup when the view appears
    private func handleOnAppear() {
        if !configFilePath.isEmpty {
            helperService.connectToServer(
                viewModel: viewModel,
                configPath: configFilePath,
                focusState: $isInputFocused
            )
        } else {
            viewModel.addInfoMessage("Please select a configuration file to connect.")
        }
        
        // Initialize AI service
        Task {
            await viewModel.initializeAI()
        }
    }
}

#Preview {
    ContentView()
}
