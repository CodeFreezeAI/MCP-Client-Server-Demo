import SwiftUI

// MARK: - Message View
struct MessageView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(message.sender)
                    .fontWeight(.bold)
                    .font(.caption)
                
                Spacer()
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Text(message.content)
                .padding([.top], 2)
                .textSelection(.enabled)
        }
        .padding()
        .background(
            message.isFromServer
            ? Color.blue.opacity(0.1)
            : Color.green.opacity(0.1)
        )
        .cornerRadius(8)
        .padding(.horizontal, 5)
    }
}
