//
//  ToolsListView.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI

/// Tools list component for displaying available tools
struct ToolsListView: View {
    let availableTools: [MCPTool]
    let serverSubtools: [String]
    @Binding var inputText: String
    let uiService: UIService
    @FocusState var isInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Available Tools")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)
                .textSelection(.enabled)
            
            Divider()
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Display main tools
                    ForEach(availableTools, id: \.name) { tool in
                        ToolButtonView(
                            tool: tool,
                            isSelected: inputText == tool.name,
                            onSelect: {
                                inputText = tool.name
                                uiService.setFocus($isInputFocused, to: true)
                            }
                        )
                    }
                    
                    // Display server subtools
                    ForEach(serverSubtools, id: \.self) { subtool in
                        SubtoolButtonView(
                            name: subtool,
                            isSelected: inputText == subtool,
                            onSelect: {
                                inputText = subtool
                                uiService.setFocus($isInputFocused, to: true)
                            }
                        )
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
}

/// Individual tool button component
struct ToolButtonView: View {
    let tool: MCPTool
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            Text(tool.name)
                .textSelection(.enabled)
        }
        .buttonStyle(.tool(selected: isSelected))
    }
}

/// Individual subtool button component
struct SubtoolButtonView: View {
    let name: String
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            Text(name)
                .textSelection(.enabled)
        }
        .buttonStyle(.tool(selected: isSelected))
    }
} 