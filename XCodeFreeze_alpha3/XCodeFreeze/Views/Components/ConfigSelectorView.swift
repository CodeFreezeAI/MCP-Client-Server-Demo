//
//  ConfigSelectorView.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI

/// Config file selector component
struct ConfigSelectorView: View {
    @Binding var configFilePath: String
    let isConnected: Bool
    let showConfigAlert: Binding<Bool>
    let viewModel: MCPViewModel
    let helperService: HelperService
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        HStack(spacing: 15) {
            // JSON Config file selector
            HStack {
                TextField("Config JSON path", text: $configFilePath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(isConnected)
                
                Button("Select") {
                    if let newPath = helperService.selectConfigFile() {
                        configFilePath = newPath
                    }
                }
                .buttonStyle(.standard(disabled: isConnected))
                .disabled(isConnected)
                
                Button("New") {
                    if let newPath = helperService.createNewConfigFile(messageHandler: { message in
                        viewModel.addInfoMessage(message)
                    }) {
                        configFilePath = newPath
                    }
                }
                .buttonStyle(.standard(disabled: isConnected))
                .disabled(isConnected)
                
                Button(isConnected ? "Disconnect" : "Connect") {
                    if isConnected {
                        viewModel.stopClientServer()
                    } else {
                        if configFilePath.isEmpty {
                            showConfigAlert.wrappedValue = true
                        } else {
                            helperService.connectToServer(
                                viewModel: viewModel,
                                configPath: configFilePath,
                                focusState: $isInputFocused
                            )
                        }
                    }
                }
                .buttonStyle(.primary(disabled: false))
            }
            .frame(maxWidth: .infinity)
            
            // Status indicator
            StatusIndicatorView(
                isConnected: isConnected, 
                statusMessage: viewModel.statusMessage
            )
        }
        .padding(.horizontal)
        .padding(.bottom)
        .alert("Configuration Required", isPresented: showConfigAlert) {
            Button("OK") { }
        } message: {
            Text("Please select or create a JSON configuration file before connecting.")
        }
    }
}

/// Status indicator component
struct StatusIndicatorView: View {
    let isConnected: Bool
    let statusMessage: String
    
    var body: some View {
        HStack {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(statusMessage)
                .font(.subheadline)
                .textSelection(.enabled)
        }
        .frame(minWidth: 150)
    }
} 