//
//  UIService.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/25/25.
//

import SwiftUI

/// Service for handling UI-specific operations
class UIService {
    /// Singleton instance
    static let shared = UIService()
    
    private init() {}
    
    /// Scrolls to the bottom of the scroll view with animation
    @MainActor func scrollToBottom(_ scrollView: ScrollViewProxy) {
        withAnimation {
            scrollView.scrollTo("bottom", anchor: .bottom)
        }
    }
    
    /// Sets focus to a specified focus state
    @MainActor func setFocus<Value>(_ focusState: FocusState<Value>.Binding, to value: Value) {
        focusState.wrappedValue = value
    }
    
    /// Clears a text field and sets focus
    @MainActor func clearAndFocusInput(text: Binding<String>, focusState: FocusState<Bool>.Binding, focusValue: Bool = true) {
        text.wrappedValue = ""
        focusState.wrappedValue = focusValue
    }
} 