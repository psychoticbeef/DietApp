//
//  NutritionParser.swift
//  Haesslon
//
//  Created by Daniel Arndt on 12.01.26.
//

import Foundation

struct NutritionParser {
    
    struct Result {
        var kcal: Double?
        var fat: Double?
        var satFat: Double?
        var carbs: Double?
        var sugar: Double?
        var protein: Double?
        var fiber: Double?
        var salt: Double?
        
        var hasData: Bool {
            return [kcal, fat, satFat, carbs, sugar, protein, fiber, salt].contains { $0 != nil }
        }
    }
    
    enum NutrientType {
        case energy
        case fat
        case satFat
        case carbs
        case sugar
        case protein
        case fiber
        case salt
    }
    
    static func parse(_ text: String) -> Result {
        var result = Result()
        
        // 1. Pre-processing: Handle common OCR merging issues
        // e.g. "1625kJ" -> "1625 kJ" to ensure regex sees the number
        let cleanedText = text
            .replacingOccurrences(of: "kJ", with: " kJ")
            .replacingOccurrences(of: "kcal", with: " kcal")
            .replacingOccurrences(of: "g", with: " g")
        
        let lines = cleanedText.components(separatedBy: .newlines)
        
        // 2. Identify Locale (Decimal Separator)
        // If we see "davon" or "gesättigte", it's likely German -> Expect comma decimals
        let isGerman = cleanedText.lowercased().contains("davon") || cleanedText.lowercased().contains("gesätt")
        
        // 3. Extract all valid numbers (Values)
        // We filter out years (2020-2030) and barcodes (>10000 unless explicit kJ)
        var values: [Double] = []
        var explicitKcal: Double? = nil
        var explicitKJ: Double? = nil
        
        for line in lines {
            let lower = line.lowercased()
            
            // Check for explicit Energy lines first to grab them safely
            if lower.contains("kcal") {
                if let val = extractNumber(from: lower, isGerman: isGerman) { explicitKcal = val }
            } else if lower.contains("kj") {
                if let val = extractNumber(from: lower, isGerman: isGerman) { explicitKJ = val }
            } else {
                // Collect other numbers
                if let val = extractNumber(from: lower, isGerman: isGerman) {
                    // Filter noise
                    if isLikelyNoise(val) { continue }
                    values.append(val)
                }
            }
        }
        
        // Set Energy immediately if found explicitly
        if let k = explicitKcal { result.kcal = k }
        else if let kj = explicitKJ { result.kcal = kj / 4.184 }
        
        // 4. Extract all Keywords (Headers) in order
        var foundKeywords: [NutrientType] = []
        
        for line in lines {
            let lower = line.lowercased()
            
            // Order matters: specific checks before general ones
            if lower.contains("gesätt") || lower.contains("saturated") { foundKeywords.append(.satFat) }
            else if lower.contains("fett") || lower.contains("fat") { foundKeywords.append(.fat) }
            
            else if lower.contains("zucker") || lower.contains("sugar") { foundKeywords.append(.sugar) }
            else if lower.contains("kohlenhydrat") || lower.contains("carb") { foundKeywords.append(.carbs) }
            
            else if lower.contains("eiweiß") || lower.contains("eiweiss") || lower.contains("protein") { foundKeywords.append(.protein) }
            
            else if lower.contains("ballast") || lower.contains("fiber") || lower.contains("fibre") { foundKeywords.append(.fiber) }
            
            else if lower.contains("salz") || lower.contains("salt") || lower.contains("sodium") { foundKeywords.append(.salt) }
        }
        
        // 5. Match Stream (Zip Keywords to Values)
        // If we found a disconnected list (e.g. 6 keywords and 6 numbers), map them 1:1.
        // We skip Energy from this mapping as it's usually handled explicitly above.
        
        let validKeywords = foundKeywords // Keywords found in order
        let validValues = values // Numbers found in order (excluding explicit energy lines)
        
        // Heuristic: If we have roughly the same amount of keywords and values, assume sequential mapping.
        // This handles the "Columnar Read" from the screenshot.
        let limit = min(validKeywords.count, validValues.count)
        
        for i in 0..<limit {
            let value = validValues[i]
            switch validKeywords[i] {
            case .fat: if result.fat == nil { result.fat = value }
            case .satFat: if result.satFat == nil { result.satFat = value }
            case .carbs: if result.carbs == nil { result.carbs = value }
            case .sugar: if result.sugar == nil { result.sugar = value }
            case .protein: if result.protein == nil { result.protein = value }
            case .fiber: if result.fiber == nil { result.fiber = value }
            case .salt: if result.salt == nil { result.salt = value }
            default: break
            }
        }
        
        // 6. Fallback: Standard Order
        // If keywords were missed (OCR error) but we have a big block of numbers, assume standard EU label order.
        // Standard: Fat -> SatFat -> Carbs -> Sugar -> (Fiber?) -> Protein -> Salt
        if !result.hasData && values.count >= 5 {
             // This is a "Hail Mary" pass if keywords failed completely
             if result.fat == nil { result.fat = values.first }
             // ... logic could continue here, but keyword matching is safer.
        }
        
        return result
    }
    
    private static func isLikelyNoise(_ val: Double) -> Bool {
        // Filter Years
        if val >= 2020 && val <= 2030 && val.truncatingRemainder(dividingBy: 1) == 0 { return true }
        // Filter Barcodes / Phone numbers (arbitrary high cap, macro per 100g rarely > 1000 except kJ)
        if val > 5000 { return true }
        // Filter codes like "6013.5354" (treated as 6013.5)
        if val > 2000 { return true }
        return false
    }
    
    private static func extractNumber(from line: String, isGerman: Bool) -> Double? {
        // 1. Clean string
        var cleanLine = line.replacingOccurrences(of: "g", with: "")
                            .replacingOccurrences(of: "ml", with: "")
        
        // 2. Handle Decimal Separators based on detected locale
        if isGerman {
            // German: "4,1" -> "4.1"
            cleanLine = cleanLine.replacingOccurrences(of: ",", with: ".")
        } else {
            // English: Remove commas (thousands sep), keep dots
            cleanLine = cleanLine.replacingOccurrences(of: ",", with: "")
        }
        
        // 3. Regex for first float
        let pattern = "[0-9]+[.]?[0-9]*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(cleanLine.startIndex..<cleanLine.endIndex, in: cleanLine)
        
        if let match = regex.firstMatch(in: cleanLine, range: nsRange),
           let range = Range(match.range, in: cleanLine),
           let val = Double(String(cleanLine[range])) {
            return val
        }
        return nil
    }
}
