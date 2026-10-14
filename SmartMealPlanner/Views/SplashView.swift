//
//  SplashView.swift
//  SmartMealPlanner
//

import SwiftUI

/// Branded launch screen shown briefly while the app starts.
struct SplashView: View {

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.bgCanvas.ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color.brandPrimary)
                        .frame(width: 112, height: 112)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.white)
                    IconCircle(systemName: "leaf.fill", tint: .brandPrimary, background: .brandPrimarySoft, size: 40)
                        .overlay(Circle().strokeBorder(Color.bgCanvas, lineWidth: 4))
                        .offset(x: 50, y: -50)
                }
                .scaleEffect(appeared ? 1 : 0.85)

                VStack(spacing: 6) {
                    Text("Smart Meal Planner")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.textPrimary)
                    Text("Plan your week. Shop smarter.")
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .opacity(appeared ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("splash")
        .onAppear {
            withAnimation(.spring(duration: 0.5)) { appeared = true }
        }
    }
}

#Preview {
    SplashView()
}
