//
//  HeaderView.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI

/// Header component for the app's title
struct HeaderView: View {
    var title: String = MCPConstants.Client.name + " Demo"
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .padding(.bottom, 5)
            Spacer()
        }
    }
}

#Preview {
    HeaderView()
}
