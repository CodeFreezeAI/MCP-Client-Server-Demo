import SwiftUI

// MARK: - AI Model Selector View

struct AIModelSelectorView: View {
    @ObservedObject var aiService: AIService
    @State private var showModelPicker = false
    
    var body: some View {
        HStack(spacing: 8) {
            // AI connection status indicator
            Circle()
                .fill(aiService.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            // Model selector button
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
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
            .disabled(aiService.availableModels.isEmpty)
            .popover(isPresented: $showModelPicker) {
                modelPickerContent
            }
            
            // Refresh models button
            Button(action: {
                Task {
                    await aiService.fetchAvailableModels()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .disabled(aiService.isLoading)
            
            if aiService.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
    }
    
    private var selectedModelDisplayText: String {
        if let selectedModel = aiService.selectedModel {
            return aiService.getModelDisplayName(selectedModel)
        } else if aiService.isLoading {
            return "Loading..."
        } else if aiService.availableModels.isEmpty {
            return "No models"
        } else {
            return "Select model"
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
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                        )
                        .onHover { isHovered in
                            // Add hover effect if needed
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 280)
    }
}

#Preview {
    AIModelSelectorView(aiService: AIService.shared)
}