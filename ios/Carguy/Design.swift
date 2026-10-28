import SwiftUI
import UIKit

enum Rally {
    static let yellow = Color(red: 1, green: 0.79, blue: 0)
    static let ink = Color(red: 0.12, green: 0.13, blue: 0.15)
    static let cream = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1)
    })
    static let paleYellow = Color.yellow.opacity(0.13)
}

struct RallyButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Rally.ink)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18).fill(Rally.yellow)
                    .shadow(color: Color(red: 0.63, green: 0.43, blue: 0), radius: 0, y: configuration.isPressed ? 1 : 5)
            }
            .offset(y: configuration.isPressed ? 4 : 0)
    }
}

struct RallyGuide: View {
    var size: CGFloat = 110
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let breathing = reduceMotion ? 0 : (1 - cos(elapsed * 2 * .pi / 4.2)) / 2
            let hairSway = reduceMotion ? 0 : sin(elapsed * 2 * .pi / 5.8)
            let blinkPhase = elapsed.truncatingRemainder(dividingBy: 7.3)
            let blinking = !reduceMotion && blinkPhase >= 3.2 && blinkPhase < 3.36
            ZStack {
                Image("RallyGuide").resizable().scaledToFit()
                // Outer curls move separately; the face, hairline and outfit stay registered.
                ForEach(0..<2) { side in
                    Image("RallyGuide").resizable().scaledToFit()
                        .mask(GuideCurls(rightSide: side == 1))
                        .rotationEffect(.degrees(hairSway * (side == 0 ? 0.9 : -0.7)),
                                        anchor: UnitPoint(x: side == 0 ? 0.35 : 0.65, y: 0.25))
                }
                // Replace only the eye region, keeping the original silhouette and pose stable.
                Image("RallyGuideBlink").resizable().scaledToFit()
                    .mask {
                        GeometryReader { geometry in
                            let imageHeight = geometry.size.height
                            let imageWidth = imageHeight * (1213.0 / 1296.0)
                            Rectangle()
                                .frame(width: imageWidth * 0.26, height: imageHeight * 0.115)
                                .position(x: geometry.size.width / 2 + imageWidth * 0.01,
                                          y: imageHeight * 0.323)
                        }
                    }.opacity(blinking ? 1 : 0)
            }
            .scaleEffect(x: 1 + breathing * 0.004, y: 1 + breathing * 0.012, anchor: .bottom)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Masks follow the outer curl masses of the portrait, outside the face and suit.
private struct GuideCurls: Shape {
    var rightSide: Bool
    func path(in rect: CGRect) -> Path {
        let width = rect.height * (1213.0 / 1296.0)
        let origin = (rect.width - width) / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin + x * width, y: y * rect.height)
        }
        var path = Path()
        if rightSide {
            path.move(to: point(0.69, 0.20))
            path.addCurve(to: point(0.73, 0.56), control1: point(0.86, 0.28), control2: point(0.84, 0.44))
            path.addLine(to: point(0.66, 0.54))
            path.addCurve(to: point(0.69, 0.20), control1: point(0.69, 0.43), control2: point(0.75, 0.30))
        } else {
            path.move(to: point(0.26, 0.19))
            path.addCurve(to: point(0.09, 0.66), control1: point(0.02, 0.29), control2: point(0.02, 0.52))
            path.addLine(to: point(0.25, 0.57))
            path.addCurve(to: point(0.26, 0.19), control1: point(0.21, 0.44), control2: point(0.28, 0.30))
        }
        path.closeSubpath()
        return path
    }
}

struct GuideMessage: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            RallyGuide(size: 82)
            Text(text).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(8).background(Rally.paleYellow, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct CarThumbnail: View {
    let car: Car
    let photos: [ResearchPhoto]
    private var image: UIImage? {
        guard let encoded = photos.first?.imageData ?? car.photoData,
              let data = Data(base64Encoded: encoded) else { return nil }
        return UIImage(data: data)
    }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "car.side.fill").font(.largeTitle).foregroundStyle(Rally.ink).frame(maxWidth: .infinity, maxHeight: .infinity).background(Rally.paleYellow) }
        }.frame(width: 112, height: 88).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
    }
}
