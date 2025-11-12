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
    @State private var isOnboardingPresented = false
    
    private var paywallBinding: Binding<Bool> {
        Binding(
            get: { paywallManager.shouldShowPaywall },
            set: { paywallManager.shouldShowPaywall = $0 }
        )
    }

    var body: some View {
        MainTabView()
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                OnboardingView(isPresented: $isOnboardingPresented)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: paywallBinding) {
                PaywallView()
                    .interactiveDismissDisabled(paywallManager.remainingFreeLeads() == 0 && !paywallManager.isPremium)
            }
            .onAppear {
                isOnboardingPresented = onboardingManager.showOnboarding

                // Check subscription status when app launches
                Task {
                    await paywallManager.checkSubscriptionStatus()
                }
            }
            .onChangeCompat(of: onboardingManager.showOnboarding) { shouldShow in
                isOnboardingPresented = shouldShow
            }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
