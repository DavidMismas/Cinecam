import SwiftUI

struct CineTheme {
    static let orange = Color(red: 1.0, green: 0.6, blue: 0.0) // Cinema Orange
    static let darkBackground = Color.black
    static let darkGray = Color(white: 0.15)
    static let textMain = Color.white
    static let textSecondary = Color.gray
    
    static let fontTitle = Font.custom("AvenirNext-Bold", size: 24)
    static let fontHeadline = Font.custom("AvenirNext-DemiBold", size: 18)
    static let fontBody = Font.custom("AvenirNext-Regular", size: 16)
    
    // UI Constants
    static let buttonCornerRadius: CGFloat = 12
    static let controlPadding: CGFloat = 20
}

extension View {
    func cineButtonStyle(isPrimary: Bool = true) -> some View {
        self
            .font(CineTheme.fontHeadline)
            .foregroundColor(isPrimary ? CineTheme.darkBackground : CineTheme.orange)
            .padding()
            .frame(maxWidth: .infinity)
            .background(isPrimary ? CineTheme.orange : CineTheme.darkGray)
            .cornerRadius(CineTheme.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: CineTheme.buttonCornerRadius)
                    .stroke(CineTheme.orange, lineWidth: isPrimary ? 0 : 2)
            )
    }
}
