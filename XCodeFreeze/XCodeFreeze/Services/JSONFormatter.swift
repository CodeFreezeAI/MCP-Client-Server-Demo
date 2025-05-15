import Foundation

/// A utility for formatting and generating JSON content with consistent styling
public final class JSONFormatter {
    
    // MARK: - Public API
    
    /// Formats a raw JSON string with proper indentation
    /// - Parameter jsonString: Raw JSON string to format
    /// - Returns: Properly formatted JSON string
    public static func format(jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8) else { return jsonString }
        
        return formatJSONData(data) ?? jsonString
    }
    
    /// Converts an Encodable object to a formatted JSON string
    /// - Parameter object: Any Encodable object
    /// - Returns: Formatted JSON string representation
    public static func toJSON<T: Encodable>(_ object: T) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(object)
            
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            print("JSON encoding error: \(error)")
            return "{\"error\": \"Failed to encode object\"}"
        }
    }
    
    /// Creates a formatted JSON array from multiple items with a custom formatter
    /// - Parameters:
    ///   - items: Collection of items to format
    ///   - itemFormatter: Closure that converts each item to a JSON string
    /// - Returns: Formatted JSON array string
    public static func formatArray<T>(_ items: [T], using itemFormatter: (T) -> String) -> String {
        if items.isEmpty {
            return "[]"
        }
        
        return "[\n" + items.map(itemFormatter).joined(separator: ",\n") + "\n]"
    }
    
    /// Creates a formatted JSON object from a dictionary
    /// - Parameter properties: Dictionary of property names and values
    /// - Returns: Formatted JSON object string
    public static func buildObject(_ properties: [String: Any?]) -> String {
        let validProperties = properties.compactMapValues { $0 }
        if validProperties.isEmpty {
            return "{}"
        }
        
        let propertiesString = validProperties.map { key, value -> String in
            let valueString = stringRepresentation(of: value)
            return "  \"\(escapeString(key))\": \(valueString)"
        }.joined(separator: ",\n")
        
        return "{\n\(propertiesString)\n}"
    }
    
    // MARK: - Private Helpers
    
    /// Creates a string representation of a value for JSON
    private static func stringRepresentation(of value: Any) -> String {
        switch value {
        case let strValue as String:
            return "\"\(escapeString(strValue))\""
        case let numValue as NSNumber:
            return numValue.stringValue
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        case let dictValue as [String: Any]:
            return buildObject(dictValue)
        case let arrayValue as [Any]:
            return formatArray(arrayValue) { stringRepresentation(of: $0) }
        case is NSNull:
            return "null"
        default:
            return "\"\(escapeString(String(describing: value)))\""
        }
    }
    
    /// Escapes special characters in JSON string values
    private static func escapeString(_ string: String) -> String {
        var result = ""
        for char in string {
            switch char {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(char)
            }
        }
        return result
    }
    
    /// Formats JSON data using Foundation's JSONSerialization
    private static func formatJSONData(_ data: Data) -> String? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: prettyData, encoding: .utf8)
        } catch {
            return nil
        }
    }
} 