//
//  InputBarView.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI

/// Input bar component for entering commands
struct InputBarView: View {
    @Binding var inputText: String
    @FocusState var isInputFocused: Bool
    let isConnected: Bool
    let viewModel: MCPViewModel
    let uiService: UIService
    let helperService: HelperService
    
    var body: some View {
        HStack {
            TextField("Enter command...", text: $inputText)
                .font(.system(size: 14))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(!isConnected)
                .focused($isInputFocused)
                .onSubmit {
                    helperService.submitMessage(
                        inputText: inputText,
                        viewModel: viewModel,
                        textBinding: $inputText,
                        focusState: $isInputFocused
                    )
                }
            
            // Clear button
            Button(action: {
                uiService.clearAndFocusInput(text: $inputText, focusState: $isInputFocused)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
            .buttonStyle(BorderlessButtonStyle())
            .opacity(inputText.isEmpty ? 0 : 1)
            
            Button("Send") {
                helperService.submitMessage(
                    inputText: inputText,
                    viewModel: viewModel,
                    textBinding: $inputText,
                    focusState: $isInputFocused
                )
            }
            .buttonStyle(.primary(disabled: !isConnected || inputText.isEmpty))
            .disabled(!isConnected || inputText.isEmpty)
            
            DebugButtonsView(isConnected: isConnected, viewModel: viewModel)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Debug buttons for testing server communication
struct DebugButtonsView: View {
    let isConnected: Bool
    let viewModel: MCPViewModel
    
    var body: some View {
        HStack(spacing: 6) {
            Button("Debug") {
                if isConnected {
                    Task {
                        await viewModel.startDebugMessageTest()
                    }
                }
            }
            .buttonStyle(.standard(disabled: !isConnected))
            .disabled(!isConnected)
            .help("Test server communication by sending a ping request")
            
            Button("Diagnostics") {
                if isConnected {
                    Task {
                        await viewModel.getDiagnostics()
                    }
                }
            }
            .buttonStyle(.standard(disabled: !isConnected))
            .disabled(!isConnected)
            .help("Check client and transport state")
        }
        .font(.system(size: 12))
    }
} 