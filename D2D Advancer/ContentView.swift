//
//  ContentView.swift
//  D2D Advancer
//
//  Created by Daniil Mukashev on 17/08/2025.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var paywallManager = PaywallManager.shared

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { onboardingManager.showOnboarding },
            set: { onboardingManager.showOnboarding = $0 }
        )
    }
    
    private var paywallBinding: Binding<Bool> {
        Binding(
            get: { paywallManager.shouldShowPaywall },
            set: { paywallManager.shouldShowPaywall = $0 }
        )
    }

    var body: some View {
        ZStack {
            Color.obsidianBlack
                .ignoresSafeArea()

            MainTabView()
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView(isPresented: onboardingBinding)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: paywallBinding) {
            PaywallView()
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-showPaywallForUITests") {
                paywallManager.setPremiumStatus(false)
                paywallManager.shouldShowPaywall = true
            }

            // Check subscription status when app launches
            Task {
                await paywallManager.checkSubscriptionStatus()
            }
        }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
