import Foundation

/// MCP Constants namespace for application-wide constants
/// Structured to support future localization
public struct MCPConstants {
    
    /// Client configuration constants
    public struct Client {
        /// The name of the MCP client application
        public static var name = "XCodeFreeze"
        
        /// The default version of the client application
        public static let defaultVersion = "1.0.0"
    }
    
    /// Server configuration constants
    public struct Server {
        /// The name of the MCP server
        public static var name = "XCF_MCP_SERVER"
    }
    
    /// Message constants for user-facing text
    public struct Messages {
        /// Error messages
        public struct Errors {
            /// Server connection errors
            public static let serverConnectionFailed = "Error connecting to server"
            public static let serverNotConfigured = "Server not configured"
            public static let transportUnavailable = "Transport is not available"
        }
        
        /// Info messages
        public struct Info {
            /// Server connection info
            public static let connecting = "Connecting..."
            public static let connected = "Connected to server"
            public static let disconnected = "Disconnected"
        }
    }
}

// Legacy global variables - these will be deprecated
// Keep them for backward compatibility during migration
var MCP_CLIENT_NAME: String {
    get { return MCPConstants.Client.name }
    set { MCPConstants.Client.name = newValue }
}

let MCP_CLIENT_DEFAULT_VERSION: String = MCPConstants.Client.defaultVersion

var MCP_SERVER_NAME: String {
    get { return MCPConstants.Server.name }
    set { MCPConstants.Server.name = newValue }
} 