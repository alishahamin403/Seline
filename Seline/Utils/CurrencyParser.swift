import Foundation

struct CurrencyParser {
    /// Extracts the largest currency amount found in the given string
    /// Supports formats: $50.00, 50.00, £50, €50, ¥50, Total: $50, etc.
    /// Prioritizes amounts with currency symbols and returns the largest one found
    static func extractAmount(from text: String) -> Double {
        var amounts: [(value: Double, hasCurrency: Bool)] = []

        // Pattern 1: Currency symbol followed by number (highest priority)
        // Matches: $50.00, $50, $50.5, £123.45, etc.
        if let regex = try? NSRegularExpression(pattern: "[$£€¥]\\s*([0-9]+(?:[.,][0-9]{1,2})?)", options: []) {
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in results {
                let range = match.range(at: 1)
                if range.location != NSNotFound {
                    let numberString = nsString.substring(with: range)
                    let normalized = numberString.replacingOccurrences(of: ",", with: ".")
                    if let amount = Double(normalized), amount > 0 {
                        amounts.append((value: amount, hasCurrency: true))
                    }
                }
            }
        }

        // Pattern 2: Number followed by currency symbol (high priority)
        // Matches: 50$, 50£, 123.45€, etc.
        if let regex = try? NSRegularExpression(pattern: "([0-9]+(?:[.,][0-9]{1,2})?)\\s*[$£€¥]", options: []) {
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in results {
                let range = match.range(at: 1)
                if range.location != NSNotFound {
                    let numberString = nsString.substring(with: range)
                    let normalized = numberString.replacingOccurrences(of: ",", with: ".")
                    if let amount = Double(normalized), amount > 0 {
                        amounts.append((value: amount, hasCurrency: true))
                    }
                }
            }
        }

        // If we found amounts with currency symbols, return the largest one
        if let maxAmount = amounts.filter({ $0.hasCurrency }).max(by: { $0.value < $1.value }) {
            return maxAmount.value
        }

        // Pattern 3: Standalone numbers (lower priority, only if no currency found)
        // Matches: 50, 50.00, 123.45, etc. (but not dates like 2024 or times)
        if let regex = try? NSRegularExpression(pattern: "\\b([0-9]{1,3}(?:[.,][0-9]{2})?)(?:\\s|$|[^0-9])", options: []) {
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in results {
                let range = match.range(at: 1)
                if range.location != NSNotFound {
                    let numberString = nsString.substring(with: range)
                    let normalized = numberString.replacingOccurrences(of: ",", with: ".")
                    if let amount = Double(normalized), amount > 0 && amount < 100000 {
                        amounts.append((value: amount, hasCurrency: false))
                    }
                }
            }
        }

        // Return the largest amount found, or 0 if none
        if let maxAmount = amounts.max(by: { $0.value < $1.value }) {
            return maxAmount.value
        }

        return 0.0
    }

    /// Formats a double value as currency string
    static func formatCurrency(_ amount: Double, currencySymbol: String = "$") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        return formatter.string(from: NSNumber(value: amount)) ?? "\(currencySymbol)\(String(format: "%.2f", amount))"
    }

    /// Formats amount with custom symbol
    static func formatAmount(_ amount: Double, symbol: String = "$") -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        let numberString = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        return "\(symbol)\(numberString)"
    }

    /// Formats amount with no decimal places and comma separator, rounding up (e.g., $1,234)
    static func formatAmountNoDecimals(_ amount: Double, symbol: String = "$") -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true

        let roundedAmount = ceil(amount) // Round up instead of to nearest
        let numberString = formatter.string(from: NSNumber(value: roundedAmount)) ?? String(format: "%.0f", roundedAmount)
        return "\(symbol)\(numberString)"
    }
}
