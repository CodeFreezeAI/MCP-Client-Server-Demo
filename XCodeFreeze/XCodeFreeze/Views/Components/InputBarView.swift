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
            // AI Thinking indicator on its own line
            if viewModel.isAIProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("AI Thinking...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            // Input area with buttons
            HStack(alignment: .bottom) {
                TextEditor(text: $inputText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                    .frame(minHeight: 22, maxHeight: 88) // ~4 lines max
                    .disabled(!isConnected)
                    .focused($isInputFocused)
                    .overlay(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("Ask me anything or enter MCP commands...")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .font(.system(size: 14))
                                .allowsHitTesting(false)
                        }
                    }
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
                
                // Clear button
                Button(action: {
                    uiService.clearAndFocusInput(text: $inputText, focusState: $isInputFocused)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(BorderlessButtonStyle())
                .opacity(inputText.isEmpty ? 0 : 1)
                
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