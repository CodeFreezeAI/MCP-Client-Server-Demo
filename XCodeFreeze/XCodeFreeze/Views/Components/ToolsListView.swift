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
        VStack(alignment: .leading, spacing: 4) {
            Text("Available Tools")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal)
                .padding(.top, 6)
                .textSelection(.enabled)
            
            Divider()
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                .padding(.vertical, 6)
            }
        }
        .background(Color.gray.opacity(0.03))
        .frame(height: 82)
        .cornerRadius(6)
        .padding(.horizontal)
        .padding(.bottom, 8)
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