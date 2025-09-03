import SwiftUI

// MARK: - Message View
struct MessageView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Sender label outside the bubble
            Text(message.sender)
                .fontWeight(message.sender == "You" ? .bold : .semibold)
                .font(.system(size: 14))
                .foregroundColor(senderColor)
                .padding(.leading, 4)
            
            // Message content in bubble
            Text(message.content)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .padding(10)
                .background(
                    message.isFromServer 
                    ? Color.blue.opacity(0.05)
                    : Color.gray.opacity(0.05)
                )
                .cornerRadius(8)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }
    
    // Determine sender color based on the sender name
    private var senderColor: Color {
        if message.sender == "Server" {
            return .yellow
        } else if message.sender == "You" {
            return .green
        } else if message.sender == "Client" {
            return Color(red: 0.1, green: 0.7, blue: 0.1)
        } else {
            // LLM names (like "Gpt-Oss:20B", "Qwen3-Coder", etc.) get orange color
            return .orange
        }
    }
}
