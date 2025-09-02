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
            // JSON opening brace
            Text("{")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Config section
            HStack(spacing: 4) {
                Text("\"config\":")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                TextField("path/to/config.json", text: $configFilePath)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                    .disabled(isConnected)
                    .frame(width: 150)
            }
            
            Text(",")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Actions section
            HStack(spacing: 4) {
                Text("\"actions\":")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Text("[")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Button("Select") {
                    if let newPath = helperService.selectConfigFile() {
                        configFilePath = newPath
                    }
                }
                .buttonStyle(JSONButtonStyle(disabled: isConnected))
                .disabled(isConnected)
                
                Text(",")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Button("New") {
                    if let newPath = helperService.createNewConfigFile(messageHandler: { message in
                        viewModel.addInfoMessage(message)
                    }) {
                        configFilePath = newPath
                    }
                }
                .buttonStyle(JSONButtonStyle(disabled: isConnected))
                .disabled(isConnected)
                
                Text(",")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
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
                .buttonStyle(JSONButtonStyle(disabled: false, isPrimary: true))
                
                Text("]")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Text(",")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.secondary)
            
            // LLM Server section
            HStack(spacing: 4) {
                Text("\"llm\":")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                TextField("IP:port", text: $llmServerAddress)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                    .frame(width: 120)
            }
            
            Text(",")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Model section
            HStack(spacing: 4) {
                Text("\"model\":")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Button(action: {
                    showModelPicker.toggle()
                }) {
                    HStack(spacing: 2) {
                        Text(selectedModelDisplayText)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                }
                .buttonStyle(JSONButtonStyle(disabled: aiService.availableModels.isEmpty))
                .disabled(aiService.availableModels.isEmpty)
                .popover(isPresented: $showModelPicker) {
                    modelPickerContent
                }
            }
            
            Text(",")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Status section
            HStack(spacing: 4) {
                Text("\"status\":")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 6, height: 6)
                    
                    Text(connectionStatusText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(connectionStatusColor)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            }
            
            // Refresh button
            Button(action: {
                Task {
                    await aiService.fetchAvailableModels()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(JSONButtonStyle(disabled: aiService.isLoading))
            .disabled(aiService.isLoading)
            
            // JSON closing brace
            Text("}")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
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