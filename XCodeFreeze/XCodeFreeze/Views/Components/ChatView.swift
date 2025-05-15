//
//  ChatView.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI

/// Chat message display component with auto-scrolling
struct ChatView: View {
    let messages: [ChatMessage]
    let uiService: UIService
    
    var body: some View {
        ScrollViewReader { scrollView in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages, id: \.id) { message in
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
            .background(Color.gray.opacity(0.03))
            .cornerRadius(6)
            .onChange(of: messages.count) { oldValue, newValue in
                uiService.scrollToBottom(scrollView)
            }
            .onAppear {
                uiService.scrollToBottom(scrollView)
            }
            .onChange(of: messages.last?.id) { _, _ in
                uiService.scrollToBottom(scrollView)
            }
        }
    }
} 