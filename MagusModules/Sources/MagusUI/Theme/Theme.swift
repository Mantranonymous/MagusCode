import SwiftUI

/// Tokens du design system Magus. Étendu et formalisé en Phase 4.
/// Pour l'instant : palette dark + spacing + radius minimaux pour les vues de P1.
public enum Theme {

    public enum Colors {
        // Backgrounds
        public static let bg = Color(red: 0.039, green: 0.043, blue: 0.055)         // #0A0B0E
        public static let surface = Color(red: 0.051, green: 0.055, blue: 0.071)    // #0D0E12
        public static let surfaceElev = Color(red: 0.071, green: 0.078, blue: 0.098) // #12141A

        // Accents
        public static let accent = Color(red: 0.486, green: 0.557, blue: 1.0)       // #7C8EFF
        public static let success = Color(red: 0.290, green: 0.871, blue: 0.502)    // #4ADE80
        public static let danger = Color(red: 0.937, green: 0.267, blue: 0.267)     // #EF4444
        public static let warning = Color(red: 0.984, green: 0.749, blue: 0.141)    // #FBBF24
        public static let gold = Color(red: 0.831, green: 0.647, blue: 0.455)       // #D4A574

        // Text
        public static let textPrimary = Color.white
        public static let textSecondary = Color.white.opacity(0.6)
        public static let textTertiary = Color.white.opacity(0.4)

        // Borders & dividers
        public static let border = Color.white.opacity(0.08)
        public static let borderStrong = Color.white.opacity(0.16)
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
    }

    public enum Radius {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let xl: CGFloat = 14
    }
}
