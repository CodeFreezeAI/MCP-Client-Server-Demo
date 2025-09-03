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
        VStack(spacing: 8) {
            // Input area - full width
            ZStack(alignment: .topLeading) {
                TextEditor(text: $inputText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 22, maxHeight: 88) // ~4 lines max
                    .disabled(!isConnected)
                    .focused($isInputFocused)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                
                if inputText.isEmpty {
                    Text("Ask me anything or enter MCP commands...")
                        .foregroundColor(.secondary)
                        .padding(.leading, 10)
                        .padding(.trailing, 5)
                        .padding(.vertical, 8)
                        .font(.system(size: 14))
                        .allowsHitTesting(false)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            )
            .onKeyPress(keys: [.return]) { _ in
                if NSEvent.modifierFlags.contains(.command) {
                    helperService.submitMessage(
                        inputText: inputText,
                        viewModel: viewModel,
                        textBinding: $inputText,
                        focusState: $isInputFocused
                    )
                    return .handled
                }
                return .ignored
            }
            .padding(.horizontal)
            
            // Buttons section with thinking indicator
            HStack {
                Spacer()
                
                // AI Thinking indicator
                if viewModel.isAIProcessing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("AI Thinking...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Buttons
                HStack(spacing: 8) {
                    // Clear button
                    Button(action: {
                        uiService.clearAndFocusInput(text: $inputText, focusState: $isInputFocused)
                    }) {
                        Text("Clear")
                    }
                    .buttonStyle(.standard(disabled: inputText.isEmpty))
                    .disabled(inputText.isEmpty)
                    
                    Button(action: {
                        helperService.submitMessage(
                            inputText: inputText,
                            viewModel: viewModel,
                            textBinding: $inputText,
                            focusState: $isInputFocused
                        )
                    }) {
                        Text("Send")
                    }
                    .buttonStyle(.primary(disabled: !isConnected || inputText.isEmpty || viewModel.isAIProcessing))
                    .disabled(!isConnected || inputText.isEmpty || viewModel.isAIProcessing)
                    
                    DebugButtonsView(isConnected: isConnected, viewModel: viewModel)
                }
            }
            .padding(.horizontal)
        }
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