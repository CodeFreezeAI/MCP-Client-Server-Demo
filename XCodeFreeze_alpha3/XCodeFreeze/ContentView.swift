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
    @State private var scrollToBottom = true
    @State var configFilePath = UserDefaults.standard.string(forKey: "savedConfigPath") ?? ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("MCP Client-Server Demo")
                .font(.largeTitle)
                .padding()
            
            // Config file selector and status indicator
            HStack(spacing: 15) {
                // JSON Config file selector
                HStack {
                    TextField("Config JSON path", text: $configFilePath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(viewModel.isConnected)
                    
                    Button("Select") {
                        selectConfigFile()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isConnected)
                    
                    Button("New") {
                        createNewConfigFile()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isConnected)
                    
                    Button(viewModel.isConnected ? "Disconnect" : "Connect") {
                        if viewModel.isConnected {
                            viewModel.stopClientServer()
                        } else {
                            Task {
                                await viewModel.startClientServer(configPath: configFilePath.isEmpty ? nil : configFilePath)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                
                // Status indicator
                HStack {
                    Circle()
                        .fill(viewModel.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                .frame(minWidth: 150)
            }
            .padding(.horizontal)
            .padding(.bottom)
            
            // Chat area with auto-scrolling
            ScrollViewReader { scrollView in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.messages, id: \.id) { message in
                            MessageView(message: message)
                                .id(message.id) // Use message.id for scrolling targets
                        }
                        
                        // Invisible spacer view at the bottom for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .onChange(of: viewModel.messages.count) { oldValue, newValue in
                    // Scroll to bottom when messages are added
                    if scrollToBottom {
                        withAnimation {
                            scrollView.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input area - simple text field with no dropdown or prefilling
            HStack {
                TextField("Enter command...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(!viewModel.isConnected)
                    .focused($isInputFocused)
                    .onSubmit {
                        submitMessage()
                    }
                
                // Clear button
                Button(action: {
                    inputText = ""
                    isInputFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(BorderlessButtonStyle())
                .opacity(inputText.isEmpty ? 0 : 1)
                
                Button("Send") {
                    submitMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isConnected || inputText.isEmpty)
            }
            .padding()
            
            // Tool list section (below chat entry)
            VStack(alignment: .leading) {
                Text("Available Tools")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .textSelection(.enabled)
                
                Divider()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.availableTools, id: \.name) { tool in
                            Button(action: {
                                // Add the selected tool to the input text field
                                inputText = tool.name
                                isInputFocused = true
                            }) {
                                Text(tool.name)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(inputText == tool.name ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .foregroundColor(inputText == tool.name ? .blue : .primary)
                                    .textSelection(.enabled)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .background(Color.gray.opacity(0.05))
            .frame(height: 90)
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
        .onAppear {
            // Start the client and server when the view appears
            Task {
                await viewModel.startClientServer(configPath: configFilePath.isEmpty ? nil : configFilePath)
                // Focus the text field after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isInputFocused = true
                }
            }
        }
        .onDisappear {
            // Stop the client and server when the view disappears
            viewModel.stopClientServer()
        }
    }
    
    private func selectConfigFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select JSON Config File"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.json]
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                configFilePath = url.path
                // Save to UserDefaults
                UserDefaults.standard.set(configFilePath, forKey: "savedConfigPath")
            }
        }
    }
    
    private func createNewConfigFile() {
        let savePanel = NSSavePanel()
        savePanel.title = "Create New JSON Config File"
        savePanel.nameFieldStringValue = "mcp.json"
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.json]
        
        if savePanel.runModal() == .OK {
            if let url = savePanel.url {
                configFilePath = url.path
                // Save to UserDefaults
                UserDefaults.standard.set(configFilePath, forKey: "savedConfigPath")
                
                // Create default config content
                let defaultConfig = """
                {
                    "mcpServers": {
                        "xcf": {
                            "type": "stdio",
                            "command": "/usr/local/bin/xcf",
                            "args": [],
                            "env": {}
                        }
                    }
                }
                """
                
                do {
                    try defaultConfig.write(to: url, atomically: true, encoding: .utf8)
                    // Show success message
                    viewModel.addInfoMessage("Created new config file at: \(url.path)")
                } catch {
                    // Show error message 
                    viewModel.addInfoMessage("Error creating config file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func submitMessage() {
        guard !inputText.isEmpty else { return }
        
        // Store original input for debugging
        let originalInput = inputText
        
        // Special handling for "use [server]" which is a common command
        if originalInput.lowercased() == "use \(MCP_SERVER_NAME)" {
            print("Detected special 'use \(MCP_SERVER_NAME)' command")
            let toolName = MCP_SERVER_NAME
            let toolArgs = "use \(MCP_SERVER_NAME)"
            print("Transformed to: \(MCP_SERVER_NAME) action='use \(MCP_SERVER_NAME)'")
            
            Task {
                await viewModel.callTool(name: toolName, text: toolArgs)
                inputText = ""
                // Re-focus the input field after sending
                isInputFocused = true
            }
            return
        }
        
        // Extract the tool name and arguments
        let components = inputText.split(separator: " ", maxSplits: 1)
        var toolName = String(components[0])
        var toolArgs = components.count > 1 ? String(components[1]) : ""
        
        // Check if this is a direct server command
        var isKnownCommand = false
        
        // Special handling for server sub-tools
        if let serverActions = ToolRegistry.shared.getSubTools(for: MCP_SERVER_NAME) {
            // Case 1: Direct server command like "xcf help"
            if toolName.lowercased() == MCP_SERVER_NAME {
                // Already properly formatted, no need to change
                print("Direct \(MCP_SERVER_NAME) command: \(toolName) action=\(toolArgs)")
                isKnownCommand = true
            }
            // Case 2: First token is a server action like "help" or "grant"
            else if serverActions.contains(where: { $0.lowercased() == toolName.lowercased() }) {
                print("Detected direct \(MCP_SERVER_NAME) action: \(toolName) with args: \(toolArgs)")
                toolArgs = toolArgs.isEmpty ? toolName : "\(toolName) \(toolArgs)"
                toolName = MCP_SERVER_NAME
                print("Transformed to: \(toolName) action=\(toolArgs)")
                isKnownCommand = true
            }
            // Case 3: Handle special cases
            else {
                // See if any server action is a prefix of the command
                for action in serverActions {
                    if toolName.lowercased() == action.lowercased() && !toolArgs.isEmpty {
                        // This is a multi-word server command - the first word is a server action
                        print("Detected multi-word \(MCP_SERVER_NAME) command starting with \(action): \(originalInput)")
                        toolArgs = originalInput // Pass the entire command as the action
                        toolName = MCP_SERVER_NAME
                        print("Transformed to: \(toolName) action=\(toolArgs)")
                        isKnownCommand = true
                        break
                    }
                }
            }
        }
        
        // Check if the command is a known tool
        if !isKnownCommand {
            let isKnownTool = viewModel.availableTools.contains(where: { $0.name == toolName })
            
            // If it's not a known tool and has multiple words, assume it's a server command
            if !isKnownTool && components.count > 1 {
                print("Unrecognized multi-word command: \(originalInput). Treating as \(MCP_SERVER_NAME) command.")
                toolName = MCP_SERVER_NAME
                toolArgs = originalInput
                print("Transformed to: \(toolName) action=\(toolArgs)")
            }
        }
        
        Task {
            await viewModel.callTool(name: toolName, text: toolArgs)
            inputText = ""
            // Re-focus the input field after sending
            isInputFocused = true
        }
    }
}


#Preview {
    ContentView()
}
