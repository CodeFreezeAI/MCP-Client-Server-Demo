//
//  ButtonStyles.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI

/// Collection of reusable button styles for the app
struct ButtonStyles {
    /// Standard bordered button style
    struct StandardButton: ButtonStyle {
        let isDisabled: Bool
        
        init(isDisabled: Bool = false) {
            self.isDisabled = isDisabled
        }
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDisabled ? Color.gray.opacity(0.1) : (configuration.isPressed ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray, lineWidth: 0.5)
                        )
                )
                .foregroundColor(isDisabled ? .gray : .primary)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    
    /// Primary action button style
    struct PrimaryButton: ButtonStyle {
        let isDisabled: Bool
        
        init(isDisabled: Bool = false) {
            self.isDisabled = isDisabled
        }
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDisabled ? Color.blue.opacity(0.3) : (configuration.isPressed ? Color.blue.opacity(0.7) : Color.blue))
                )
                .foregroundColor(.white)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    
    /// Tool button style
    struct ToolButton: ButtonStyle {
        let isSelected: Bool
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue.opacity(0.2) : (configuration.isPressed ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)))
                )
                .foregroundColor(isSelected ? .blue : .primary)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == ButtonStyles.StandardButton {
    static var standard: ButtonStyles.StandardButton {
        ButtonStyles.StandardButton()
    }
    
    static func standard(disabled: Bool) -> ButtonStyles.StandardButton {
        ButtonStyles.StandardButton(isDisabled: disabled)
    }
}

extension ButtonStyle where Self == ButtonStyles.PrimaryButton {
    static var primary: ButtonStyles.PrimaryButton {
        ButtonStyles.PrimaryButton()
    }
    
    static func primary(disabled: Bool) -> ButtonStyles.PrimaryButton {
        ButtonStyles.PrimaryButton(isDisabled: disabled)
    }
}

extension ButtonStyle where Self == ButtonStyles.ToolButton {
    static func tool(selected: Bool) -> ButtonStyles.ToolButton {
        ButtonStyles.ToolButton(isSelected: selected)
    }
} 