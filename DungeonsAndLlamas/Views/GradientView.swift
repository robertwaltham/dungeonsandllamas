//
//  GradientView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-01.
//
// Adapted from https://www.rudrank.com/exploring-swiftui-animating-mesh-gradient-with-colors-in-ios-18/

import SwiftUI

struct GradientView: View {
    
    private let baseColors: [Color] = [
        Color(red: 1.00, green: 0.42, blue: 0.42),
        Color(red: 1.00, green: 0.55, blue: 0.00),
        Color(red: 1.00, green: 0.27, blue: 0.00),
        
        Color(red: 1.00, green: 0.41, blue: 0.71),
        Color(red: 0.85, green: 0.44, blue: 0.84),
        Color(red: 0.54, green: 0.17, blue: 0.89),
        
        Color(red: 0.29, green: 0.00, blue: 0.51),
        Color(red: 0.00, green: 0.00, blue: 0.55),
        Color(red: 0.10, green: 0.10, blue: 0.44)
    ]
    
    private let greyColors: [Color] = [
        Color(red: 0.8, green: 0.8, blue: 0.8),
        Color(red: 0.8, green: 0.8, blue: 0.8),
        Color(red: 0.8, green: 0.8, blue: 0.8),

        Color(red: 0.5, green: 0.5, blue: 0.5),
        Color(red: 0.5, green: 0.5, blue: 0.5),
        Color(red: 0.5, green: 0.5, blue: 0.5),
        
        Color(red: 0.2, green: 0.2, blue: 0.2),
        Color(red: 0.2, green: 0.2, blue: 0.2),
        Color(red: 0.2, green: 0.2, blue: 0.2),
    ]
    
    private let colors: [Color]
    private let type: GradientView.ColorType
    let speed = 0.2
    
    init(colors: [Color], type: ColorType) {
        self.colors = colors
        self.type = type
    }
    
    init(type: ColorType) {
        switch type {
        case .hue:
            self.colors = baseColors
        case .greyscale:
            self.colors = greyColors
        case .saturation:
            self.colors = baseColors
        case .brightness:
            self.colors = baseColors
        }
        self.type = type
    }
    
    private let points: [SIMD2<Float>] = [
        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
        SIMD2<Float>(0.0, 0.5), SIMD2<Float>(0.5, 0.5), SIMD2<Float>(1.0, 0.5),
        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0)
    ]
    
    enum ColorType {
        case hue
        case saturation
        case brightness
        case greyscale
    }
}

extension GradientView {
    var body: some View {
        TimelineView(.animation) { timeline in
            MeshGradient(
                width: 3,
                height: 3,
                locations: .points(points),
                colors: .colors(animatedColors(for: timeline.date)),
                background: .black,
                smoothsColors: true
            )
        }
        .ignoresSafeArea()
    }
}

extension GradientView {
    private enum ShiftMode {
        case hue
        case saturation
        case brightness
        case alpha
    }
    
    private func animatedColors(for date: Date) -> [Color] {
        let phase = CGFloat(date.timeIntervalSince1970)
        
        switch type {
            
        case .hue:
            return colors.enumerated().map { index, color in
                let hueShift = cos(phase + Double(index) * speed) * 0.1
                return shift(mode: .hue, of: color, by: hueShift)
            }
        case .greyscale:
            return colors.enumerated().map { index, color in
                let hueShift = cos(phase + Double(index) * speed) * 0.1
                return shift(mode: .brightness, of: color, by: hueShift)
            }
        case .saturation:
            return colors.enumerated().map { index, color in
                let hueShift = cos(phase + Double(index) * speed) * 0.5
                return shift(mode: .saturation, of: color, by: hueShift)
            }
        case .brightness:
            return colors.enumerated().map { index, color in
                let hueShift = cos(phase + Double(index) * speed) * 0.5
                return shift(mode: .brightness, of: color, by: hueShift)
            }
        }
        
    }
    
    private func shift(mode: ShiftMode, of color: Color, by amount: Double) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        switch mode {
        case .hue:
            hue += CGFloat(amount)
            hue = hue.truncatingRemainder(dividingBy: 1.0)
            
            if hue < 0 {
                hue += 1
            }
            
        case .saturation:
            saturation += CGFloat(amount)
            
            if saturation < 0 {
                saturation = 0
            } else if saturation > 1 {
                saturation = 1
            }
            
        case .brightness:
            brightness += CGFloat(amount)
            if brightness < 0 {
                brightness = 0
            } else if saturation > 1 {
                brightness = 1
            }
            
        case .alpha:
            alpha += CGFloat(amount)
            alpha = alpha.truncatingRemainder(dividingBy: 1.0)
            
            if alpha < 0 {
                alpha += 1
            }
        }
        
        return Color(hue: Double(hue),
                     saturation: Double(saturation),
                     brightness: Double(brightness),
                     opacity: Double(alpha))
    }
}

#Preview {
//    GradientView(type: .hue)
//    GradientView(type: .saturation)
    GradientView(type: .brightness)
    GradientView(type: .greyscale)
}
