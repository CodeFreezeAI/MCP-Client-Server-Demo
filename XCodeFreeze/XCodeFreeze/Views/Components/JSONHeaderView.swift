import SwiftUI

/// JSON-style single-line header with all controls
struct JSONHeaderView: View {
    @Binding var configFilePath: String
    let isConnected: Bool
    let showConfigAlert: Binding<Bool>
    let viewModel: MCPViewModel
    let helperService: HelperService
    @ObservedObject var aiService: AIService
    
    @FocusState private var isInputFocused: Bool
    @State private var llmServerAddress = "192.168.1.135:11434"
    @State private var showModelPicker = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Just the config file path and essential buttons
            TextField("Path to MCP JSON config file", text: $configFilePath)
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
            
            // LLM Server Address
            TextField("IP:Port", text: $llmServerAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 170)
                .font(.system(size: 12))
                .onChange(of: llmServerAddress) { oldValue, newValue in
                    aiService.updateServerAddress(newValue)
                }
            
            // AI Model dropdown
            Button(action: {
                showModelPicker.toggle()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                    
                    Text(selectedModelDisplayText)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.standard(disabled: aiService.availableModels.isEmpty))
            .disabled(aiService.availableModels.isEmpty)
            .popover(isPresented: $showModelPicker) {
                modelPickerContent
            }
            
            // Refresh models
            Button(action: {
                Task {
                    await aiService.fetchAvailableModels()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.standard(disabled: aiService.isLoading))
            .disabled(aiService.isLoading)
            
            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 8, height: 8)
                
                Text(connectionStatusText)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onAppear {
            // Sync initial LLM server address from AIService
            if let url = URL(string: aiService.baseURL) {
                llmServerAddress = url.host.map { host in
                    let port = url.port ?? 11434
                    return "\(host):\(port)"
                } ?? "192.168.1.135:11434"
            }
        }
        .alert("Configuration Required", isPresented: showConfigAlert) {
            Button("OK") { }
        } message: {
            Text("Please select or create a JSON configuration file before connecting.")
        }
    }
    
    private var selectedModelDisplayText: String {
        if let selectedModel = aiService.selectedModel {
            return aiService.getModelDisplayName(selectedModel)
        } else if aiService.isLoading {
            return "loading..."
        } else if aiService.availableModels.isEmpty {
            return "none"
        } else {
            return "select"
        }
    }
    
    private var connectionStatusColor: Color {
        if isConnected && aiService.isConnected {
            return .green
        } else if isConnected || aiService.isConnected {
            return .orange
        } else {
            return .red
        }
    }
    
    private var connectionStatusText: String {
        if isConnected && aiService.isConnected {
            return "ready"
        } else if isConnected {
            return "mcp_only"
        } else if aiService.isConnected {
            return "ai_only"
        } else {
            return "disconnected"
        }
    }
    
    private var modelPickerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Select AI Model")
                .font(.headline)
                .padding()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(aiService.availableModels, id: \.id) { model in
                        Button(action: {
                            aiService.selectedModel = model
                            showModelPicker = false
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(aiService.getModelDisplayName(model))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    Text(model.id)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if aiService.selectedModel?.id == model.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 280)
    }
}

/// JSON-style button style
struct JSONButtonStyle: ButtonStyle {
    let disabled: Bool
    let isPrimary: Bool
    
    init(disabled: Bool, isPrimary: Bool = false) {
        self.disabled = disabled
        self.isPrimary = isPrimary
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(backgroundColor(configuration: configuration))
            )
            .foregroundColor(foregroundColor(configuration: configuration))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
    
    private func backgroundColor(configuration: Configuration) -> Color {
        if disabled {
            return Color.gray.opacity(0.2)
        } else if isPrimary {
            return configuration.isPressed ? Color.accentColor.opacity(0.8) : Color.accentColor
        } else {
            return configuration.isPressed ? Color.gray.opacity(0.3) : Color.gray.opacity(0.15)
        }
    }
    
    private func foregroundColor(configuration: Configuration) -> Color {
        if disabled {
            return Color.gray
        } else if isPrimary {
            return Color.white
        } else {
            return Color.primary
        }
    }
}

#Preview {
    JSONHeaderView(
        configFilePath: .constant("/path/to/config.json"),
        isConnected: false,
        showConfigAlert: .constant(false),
        viewModel: MCPViewModel(),
        helperService: HelperService.shared,
        aiService: AIService.shared
    )
}