import Foundation

//struct MCPConfig: Codable {
//    let mcpServers: [String: ServerConfig]
//    
//    struct ServerConfig: Codable {
//        let type: String
//        let command: String
//    }
//}
//
//extension MCPConfig {
//    static func loadConfig() throws -> MCPConfig {
//        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
//        let configPath = homeDirectory.appendingPathComponent(".cursor/mcp.json")
//        
//        let data = try Data(contentsOf: configPath)
//        let decoder = JSONDecoder()
//        return try decoder.decode(MCPConfig.self, from: data)
//    }
//} 
