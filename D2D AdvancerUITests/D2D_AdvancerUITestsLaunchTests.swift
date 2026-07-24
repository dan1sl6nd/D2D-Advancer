//
//  D2D_AdvancerUITestsLaunchTests.swift
//  D2D AdvancerUITests
//
//  Created by Daniil Mukashev on 17/08/2025.
//

import XCTest

final class D2D_AdvancerUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func denySystemPermissionIfPresented(timeout: TimeInterval = 5) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denialLabels = ["Don’t Allow", "Don't Allow", "Ask App Not to Track", "Not Now"]
        for label in denialLabels {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: timeout) {
                button.tap()
                return
            }
        }
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-completeOnboardingForLaunchTests")
        app.launchArguments.append("-unlockPremiumForUITests")
        app.launch()

        denySystemPermissionIfPresented(timeout: 4)
        denySystemPermissionIfPresented(timeout: 2)

        XCTAssertTrue(app.buttons["searchButton"].waitForExistence(timeout: 15), "Map should finish launching into the main app")
        XCTAssertFalse(app.alerts["Error"].waitForExistence(timeout: 5), "Launch should not show the global generic error alert")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
