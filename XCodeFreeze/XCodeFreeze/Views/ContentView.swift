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
            // Header
            HeaderView()
            
            // Config file selector and status indicator
            ConfigSelectorView(
                configFilePath: $configFilePath,
                isConnected: viewModel.isConnected,
                showConfigAlert: $showConfigAlert,
                viewModel: viewModel,
                helperService: helperService
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
        .padding()
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
    }
}

#Preview {
    ContentView()
}
