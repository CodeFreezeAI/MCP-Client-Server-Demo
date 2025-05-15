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
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isDisabled ? Color.gray.opacity(0.05) : (configuration.isPressed ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
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
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isDisabled ? Color.blue.opacity(0.3) : (configuration.isPressed ? Color.blue.opacity(0.7) : Color(red: 0.1, green: 0.4, blue: 0.9)))
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
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected 
                              ? Color(red: 0.1, green: 0.4, blue: 0.9).opacity(0.15) 
                              : (configuration.isPressed ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color(red: 0.1, green: 0.4, blue: 0.9).opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 0.5)
                        )
                )
                .foregroundColor(isSelected ? Color(red: 0.1, green: 0.4, blue: 0.9) : .primary)
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
