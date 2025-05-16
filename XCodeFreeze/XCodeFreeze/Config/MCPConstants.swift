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
    
    /// Command names and prefixes
    public struct Commands {
        /// Basic commands
        public static let help = "help"
        public static let list = "list"
        public static let ping = "ping"
        
        /// Command prefixes
        public static func serverPrefixedCommand(_ command: String) -> String {
            return "mcp_\(Server.name)_\(command)"
        }
    }
    
    /// API and Protocol constants
    public struct API {
        /// JSON-RPC constants
        public struct JSONRPC {
            public static let version = "2.0"
            public static let callToolMethod = "callTool"
            public static let pingMethod = "ping"
        }
        
        /// Parameter types
        public struct ParameterTypes {
            public static let string = "string"
            public static let boolean = "boolean"
            public static let integer = "integer"
            public static let number = "number"
            public static let array = "array"
            public static let object = "object"
        }
        
        /// Content types
        public struct ContentTypes {
            public static let text = "text"
            public static let image = "image"
            public static let audio = "audio"
            public static let resource = "resource"
            public static let unknown = "unknown"
        }
    }
    
    /// File system and paths
    public struct FileSystem {
        /// Log file constants
        public struct Logs {
            public static let directoryName = "Logs"
            public static let fileNamePrefix = "xcodefreeze-"
            public static let fileExtension = ".log"
        }
    }
    
    /// Message constants for user-facing text
    public struct Messages {
        /// Error messages
        public struct Errors {
            /// Server connection errors
            public static let serverConnectionFailed = "Error connecting to server"
            public static let serverNotConfigured = "Server not configured"
            public static let transportUnavailable = "Transport is not available"
            public static let jsonEncodingError = "JSON encoding error"
            public static let failedToWriteLogFile = "Failed to write to log file"
            public static let failedToCreateLogDir = "Failed to create log directory"
            public static let failedToOpenLogFile = "Failed to open log file"
            public static let failedToCloseLogFile = "Failed to close log file"
            public static let clientNotConnected = "Error: Client not connected"
            public static let errorFromServer = "Error from server"
            public static let initializationError = "Error during initialization: %@"
        }
        
        /// Info messages
        public struct Info {
            /// Server connection info
            public static let connecting = "Connecting..."
            public static let connected = "Connected to server"
            public static let disconnected = "Disconnected"
            public static let connectedToServer = "Connected to server: %@ v%@"
            public static let serverResponse = "Result:\n%@"
        }
        
        /// Logging messages
        public struct Logging {
            public static let failedToWriteLog = "Failed to write to log file"
            public static let failedToCreateLogDir = "Failed to create log directory"
            public static let failedToOpenLogFile = "Failed to open log file"
            public static let failedToCloseLogFile = "Failed to close log file"
        }
        
        /// Transport service messages
        public struct Transport {
            public static let willUseServer = "Will use %@ server from config: %@"
            public static let withArguments = "With arguments: %@"
            public static let serverStderr = "%@ Server stderr: %@"
            public static let serverProcessStarted = "%@ Server process started with PID: %d"
            public static let sendingTestMessage = "Sending transport test message: %@"
            public static let testMessageSent = "Transport test message sent successfully"
            public static let sendingRawMessage = "Sending raw message: %@"
            public static let rawMessageSent = "Raw message sent successfully"
        }
        
        /// Server config messages
        public struct ServerConfig {
            public static let settingInitialServerName = "Setting initial server name to: %@ (from config - will be updated with actual server name later)"
            public static let couldNotLoadServerName = "Could not load server name from config: %@"
            public static let usingDefaultServerName = "Using default server name: %@ - will attempt to update with actual server name during connection"
            public static let loadingCustomConfig = "Attempting to load MCP config from custom path: %@"
            public static let configFileLoaded = "Config file loaded from custom path, size: %d bytes"
            public static let foundServersInConfig = "Found servers in config: %@"
            public static let customConfigNotExist = "Custom config file does not exist at path: %@"
            public static let checkingSavedConfig = "Checking saved config path from UserDefaults: %@"
            public static let savedConfigLoaded = "Config file loaded from saved path, size: %d bytes"
            public static let savedConfigNotExist = "Saved config file does not exist at path: %@"
        }
        
        /// Client server service messages
        public struct ClientServer {
            public static let attemptingToConnect = "Attempting to connect client to %@ server"
            public static let transportConnected = "Transport connected successfully"
            public static let clientConnected = "Client successfully connected to %@ server"
            public static let connectionFailed = "Failed to connect client to %@ server: %@"
            public static let settingServerName = "Setting server name to: %@ (from server response)"
            public static let sendRawMsgFailed = "Failed to send raw debug message: %@"
            public static let connectedToNPXFilesystem = "Connected to NPX Filesystem server. Note: Using configured name '%@' for server commands."
            public static let availableServerActions = "You can use %@ actions by typing %@ <%@> or just the %@ name directly."
        }
        
        /// Command service messages
        public struct Command {
            public static let detectedSpecialCommand = "Detected special 'use %@' command"
            public static let transformedSpecialCommand = "Transformed to: %@ action='use %@'"
            public static let directCommand = "Direct %@ command: %@ action=%@"
            public static let detectedDirectAction = "Detected direct %@ action: %@ with args: %@"
            public static let transformedAction = "Transformed to: %@ action=%@"
            public static let detectedMultiwordCommand = "Detected multi-word %@ command starting with %@: %@"
            public static let unrecognizedMultiwordCommand = "Unrecognized multi-word command: %@. Treating as %@ command."
        }
        
        /// Tool discovery messages
        public struct ToolDiscovery {
            public static let usingServerParameter = "Using server parameter name from schema: %@"
            public static let extractedParameterName = "Extracted parameter name from description using pattern: %@"
            public static let parameterNameWarning = "WARNING: Unable to determine parameter name, using generic 'input'"
            public static let registeredSchema = "Registered schema for %@ with parameter: %@"
            public static let actionsError = "\n===== %@ ACTIONS ERROR ====="
            public static let couldNotParse = "Could not parse %@ actions from help text"
            public static let extractedServerParamName = "Extracted server parameter name from schema: %@"
            public static let extractedParamFromDesc = "Extracted parameter name '%@' from tool description"
            public static let unableToDetermineParam = "WARNING: Unable to determine parameter name for tool %@, using generic 'input'"
            public static let examiningSchema = "Examining schema for tool: %@"
            public static let rawSchema = "Raw schema for %@: %@"
            
            // Additional tool discovery constants
            public static let extractedServerParameterName = "Extracted server parameter name from schema: %@"
            public static let foundDirectParameter = "  Found direct parameter: %@, Type: %@"
            public static let foundParameterInProperties = "  Found parameter in properties: %@, Type: %@"
            public static let foundParameterIn = "  Found parameter in %@: %@, Type: %@"
            public static let foundArrayItemProperty = "  Found array item property: %@, Type: %@"
            public static let foundArrayItem = "  Found array item property: %@, Type: array<%@>"
            public static let found = "  Found %@ option property: %@.%@, Type: %@"
            public static let foundRequiredParameter = "  Found required parameter: %@"
            public static let foundRequiredParam = "  Found required parameter: %@"
            public static let foundParameterInArrayProperties = "  Found parameter in array properties: %@, Type: %@"
            public static let foundRequiredParameterFromStringFormat = "  Found required parameter from string format: %@"
            public static let foundParameterFromStringFormat = "  Found parameter from string format: %@, Type: %@"
            public static let extractedParameterFromDescription = "  Extracted parameter from description: %@, Type: %@"
            public static let extractedParameterFromSchemaJSONStructure = "  Extracted parameter '%@' from schema JSON structure"
            public static let extractedParameterFromQuotedNameInSchema = "  Extracted parameter '%@' from quoted name in schema"
            public static let unableToExtractParameterNameFromSchemaWarning = "  WARNING: Unable to extract parameter name from schema, using generic 'input'"
            
            // Previous constants (can be consolidated later)
            public static let foundDirectParam = "  Found direct parameter: %@, Type: %@"
            public static let foundParamInProps = "  Found parameter in properties: %@, Type: %@"
            public static let foundParamInKey = "  Found parameter in %@: %@, Type: %@"
            public static let foundOptionProperty = "  Found %@ option property: %@, Type: %@"
            public static let foundParamInArray = "  Found parameter in array properties: %@, Type: %@"
            public static let foundRequiredFromString = "  Found required parameter from string format: %@"
            public static let foundParamFromString = "  Found parameter from string format: %@, Type: %@"
            public static let extractedParamFromDesc2 = "  Extracted parameter from description: %@, Type: %@"
            public static let extractedFromSchemaJSON = "  Extracted parameter '%@' from schema JSON structure"
            public static let extractedFromQuoted = "  Extracted parameter '%@' from quoted name in schema"
            public static let unableToExtract = "  WARNING: Unable to extract parameter name from schema, using generic 'input'"
            public static let noParametersFound = "  No parameters found in schema for %@"
        }
        
        /// JSON formatter messages
        public struct JSON {
            public static let encodingError = "JSON encoding error: %@"
        }
        
        /// Diagnostic messages
        public struct Diagnostics {
            public static let clientNotConnected = "[DIAGNOSTICS] Client is not connected"
            public static let checkingConnection = "[DIAGNOSTICS] Checking client-server connection..."
            public static let clientExists = "[DIAGNOSTICS] Client exists (%@ v%@)"
            public static let clientIsNil = "[DIAGNOSTICS] Client is nil"
            public static let availableTools = "[DIAGNOSTICS] Available tools: %d"
            public static let testingWithPing = "[DIAGNOSTICS] Testing client with ping..."
            public static let pingSuccessful = "[DIAGNOSTICS] Ping successful"
            public static let pingFailed = "[DIAGNOSTICS] Ping failed: %@"
            public static let debugSendingPing = "[DEBUG] Sending ping message to test communication"
            public static let debugPingSuccess = "[DEBUG] Ping successful! Communication with server is working."
            public static let debugPingError = "[DEBUG] Error during ping test: %@"
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
