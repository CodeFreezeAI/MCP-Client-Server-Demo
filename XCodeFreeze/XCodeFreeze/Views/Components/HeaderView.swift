//
//  HeaderView.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI

/// Header component for the app's title
struct HeaderView: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.largeTitle)
            .fontWeight(.bold)
            .padding()
    }
}
