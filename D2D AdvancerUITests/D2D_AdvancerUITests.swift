import XCTest

final class D2D_AdvancerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-skipOnboardingForUITests")
        app.launchArguments.append("-unlockPremiumForUITests")
        app.launchArguments.append("-resetMessageTemplatesForUITests")
        app.launchArguments.append("-resetAppointmentTypesForUITests")
        app.launchArguments.append("-resetServiceCategoriesForUITests")
        app.launchArguments.append("-resetSyncSettingsForUITests")
        return app
    }

    private func makeTeamEmulatorApp(
        autoAuthEmail: String? = nil,
        autoAuthDisplayName: String? = nil,
        autoAuthPassword: String? = nil,
        shouldCreateAutoAuthAccount: Bool = false
    ) -> XCUIApplication {
        let app = makeApp()
        app.launchArguments.append("-useFirebaseEmulators")
        app.launchArguments.append("-resetFirebaseAuthForUITests")
        app.launchArguments.append("-openMoreTabForUITests")
        if let emulatorHost = ProcessInfo.processInfo.environment["D2D_FIREBASE_EMULATOR_HOST"], !emulatorHost.isEmpty {
            app.launchEnvironment["D2D_FIREBASE_EMULATOR_HOST"] = emulatorHost
        }
        if let autoAuthEmail, let autoAuthPassword {
            app.launchArguments.append("-teamUITestAutoAuth")
            app.launchEnvironment["D2D_TEAM_TEST_AUTH_EMAIL"] = autoAuthEmail
            app.launchEnvironment["D2D_TEAM_TEST_AUTH_PASSWORD"] = autoAuthPassword
            app.launchEnvironment["D2D_TEAM_TEST_AUTH_CREATE"] = shouldCreateAutoAuthAccount ? "1" : "0"
            if let autoAuthDisplayName {
                app.launchEnvironment["D2D_TEAM_TEST_AUTH_DISPLAY_NAME"] = autoAuthDisplayName
            }
        }
        return app
    }

    private struct TeamUITestCredentials {
        let runId: String
        let ownerEmail: String
        let repEmail: String
        let technicianEmail: String
        let password: String
        let leadName: String
    }

    private func teamTestConfigValue(environmentKey: String, infoKey: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("$(") {
                return trimmed
            }
        }

        if let value = Bundle(for: Self.self).object(forInfoDictionaryKey: infoKey) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("$(") {
                return trimmed
            }
        }

        return nil
    }

    private func teamTestConfigBool(environmentKey: String, infoKey: String) -> Bool {
        guard let value = teamTestConfigValue(environmentKey: environmentKey, infoKey: infoKey) else {
            return false
        }

        switch value.lowercased() {
        case "1", "true", "yes", "y":
            return true
        default:
            return false
        }
    }

    private func requireTeamEmulatorUITestHarness() throws {
        guard teamTestConfigBool(
            environmentKey: "D2D_RUN_TEAM_EMULATOR_UI_TESTS",
            infoKey: "D2DRunTeamEmulatorUITests"
        ) else {
            throw XCTSkip("Team emulator UI flow requires Firebase Auth/Firestore emulators. Run npm run emulators:test:team-ui.")
        }
    }

    private func requireTeamPhysicalUITestHarness() throws {
        guard teamTestConfigBool(
            environmentKey: "D2D_RUN_TEAM_PHYSICAL_UI_TESTS",
            infoKey: "D2DRunTeamPhysicalUITests"
        ) else {
            throw XCTSkip("Team physical-device UI flow requires the two-phone harness. Run scripts/run_physical_team_flow.sh.")
        }
    }

    private func teamUITestCredentials() -> TeamUITestCredentials {
        let rawRunId = teamTestConfigValue(
            environmentKey: "D2D_TEAM_UI_RUN_ID",
            infoKey: "D2DTeamUIRunID"
        )
            ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let runId = rawRunId
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(12)
        let safeRunId = runId.isEmpty ? "teamui" : String(runId)
        let password = teamTestConfigValue(
            environmentKey: "D2D_TEAM_UI_PASSWORD",
            infoKey: "D2DTeamUIPassword"
        ) ?? "testpass123"

        return TeamUITestCredentials(
            runId: safeRunId,
            ownerEmail: "owner-ui-\(safeRunId)@example.com",
            repEmail: "rep-ui-\(safeRunId)@example.com",
            technicianEmail: "tech-ui-\(safeRunId)@example.com",
            password: password,
            leadName: "UI Interested \(safeRunId)"
        )
    }

    private func makeOnboardingApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-showOnboardingForUITests")
        app.launchArguments.append("-resetOnboardingForUITests")
        return app
    }

    private func waitForText(_ app: XCUIApplication, _ text: String, timeout: TimeInterval = 8) {
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: timeout), "Expected text to appear: \(text)")
    }

    private func waitForTextContaining(_ app: XCUIApplication, _ text: String, timeout: TimeInterval = 8) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let match = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: timeout), "Expected text containing to appear: \(text)")
    }

    private func tapButton(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 8) {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Expected button to appear: \(identifier)")
        tapElement(app, button, description: identifier)
    }

    private func tapElement(_ app: XCUIApplication, _ element: XCUIElement, description: String) {
        if element.isHittable {
            element.tap()
            return
        }

        let appFrame = app.windows.firstMatch.frame
        let elementFrame = element.frame
        let visibleFrame = elementFrame.intersection(appFrame)
        XCTAssertFalse(visibleFrame.isNull || visibleFrame.isEmpty, "Expected element to be visible enough to tap: \(description)")

        let fallbackY: CGFloat = description.hasPrefix("tab_") ? 0.25 : 0.5
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fallbackY)).tap()
    }

    private func relaunch(_ app: XCUIApplication, opening tabArgument: String) {
        let tabArguments = [
            "-openMapTabForUITests",
            "-openLeadsTabForUITests",
            "-openFollowUpTabForUITests",
            "-openAppointmentsTabForUITests",
            "-openMoreTabForUITests"
        ]
        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetFirebaseAuthForUITests" || tabArguments.contains($0) }
        app.launchArguments.append(tabArgument)
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)
    }

    private func typeText(_ text: String, into field: XCUIElement, timeout: TimeInterval = 8) {
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "Expected field to appear before typing: \(text)")
        field.tap()
        field.typeText(text)
    }

    private func teamPasswordField(_ app: XCUIApplication) -> XCUIElement {
        let secureField = app.secureTextFields["teamAccountPasswordField"]
        if secureField.exists {
            return secureField
        }
        return app.textFields["teamAccountPasswordField"]
    }

    private func dismissTeamKeyboardIfPresent(_ app: XCUIApplication) {
        let doneButton = app.buttons["teamKeyboardDoneButton"]
        if doneButton.waitForExistence(timeout: 2), doneButton.isHittable {
            doneButton.tap()
        }
    }

    private func dismissKeyboardIfPresent(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }

        for label in ["Done", "Return"] {
            let button = app.keyboards.buttons[label]
            if button.waitForExistence(timeout: 1), button.isHittable {
                button.tap()
                if !app.keyboards.firstMatch.waitForExistence(timeout: 1) {
                    return
                }
            }
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }

    private func allowLocalNetworkPermissionIfPresented(timeout: TimeInterval = 5) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: timeout) {
            allowButton.tap()
        }
    }

    private func dismissErrorAlertIfPresented(_ app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let alert = app.alerts["Error"]
        guard alert.waitForExistence(timeout: timeout) else {
            return false
        }

        let okButton = alert.buttons["OK"]
        if okButton.waitForExistence(timeout: 2) {
            okButton.tap()
        }
        return true
    }

    private func dismissKeychainPromptIfPresented(_ app: XCUIApplication, timeout: TimeInterval = 3) {
        let alert = app.alerts["Save Password to Keychain"]
        guard alert.waitForExistence(timeout: timeout) else {
            return
        }

        let notNowButton = alert.buttons["Not Now"]
        if notNowButton.waitForExistence(timeout: 2) {
            notNowButton.tap()
            return
        }

        let neverButton = alert.buttons["Never for This Account"]
        if neverButton.waitForExistence(timeout: 2) {
            neverButton.tap()
        }
    }

    private enum ScrollDirection {
        case down
        case up
    }

    private func dragContent(_ app: XCUIApplication, direction: ScrollDirection) {
        let startY: CGFloat = direction == .down ? 0.78 : 0.28
        let endY: CGFloat = direction == .down ? 0.18 : 0.82
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @discardableResult
    private func waitForIdentifiedElement(
        _ app: XCUIApplication,
        _ identifier: String,
        timeout: TimeInterval = 8
    ) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected element to appear: \(identifier)")
        return element
    }

    private func tapIdentifiedElement(
        _ app: XCUIApplication,
        _ identifier: String,
        direction: ScrollDirection = .down,
        timeout: TimeInterval = 8,
        maxSwipes: Int = 8
    ) {
        let element = waitForIdentifiedElement(app, identifier, timeout: timeout)
        for _ in 0..<maxSwipes where !element.isHittable {
            dragContent(app, direction: direction)
        }
        tapElement(app, element, description: identifier)
    }

    private func scrollToButton(
        _ app: XCUIApplication,
        _ identifier: String,
        direction: ScrollDirection = .down,
        maxSwipes: Int = 8
    ) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<maxSwipes where !button.isHittable {
            dragContent(app, direction: direction)
        }
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Expected button to appear after scrolling: \(identifier)")
        XCTAssertTrue(button.isHittable, "Expected button to be hittable after scrolling: \(identifier)")
        return button
    }

    private func scrollToButtonEitherDirection(
        _ app: XCUIApplication,
        _ identifier: String,
        maxSwipesPerDirection: Int = 5
    ) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: 1), button.isHittable {
            return button
        }

        for direction in [ScrollDirection.down, .up] {
            for _ in 0..<maxSwipesPerDirection where !button.exists || !button.isHittable {
                dragContent(app, direction: direction)
            }
            if button.waitForExistence(timeout: 1), button.isHittable {
                return button
            }
        }

        XCTAssertTrue(button.waitForExistence(timeout: 3), "Expected button to appear after scrolling both directions: \(identifier)")
        XCTAssertTrue(button.isHittable, "Expected button to be hittable after scrolling both directions: \(identifier)")
        return button
    }

    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        direction: ScrollDirection = .down,
        maxSwipes: Int = 8,
        description: String
    ) {
        for _ in 0..<maxSwipes where !element.isHittable {
            dragContent(app, direction: direction)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Expected element to exist after scrolling: \(description)")
        XCTAssertTrue(element.isHittable, "Expected element to be hittable after scrolling: \(description)")
    }

    @discardableResult
    private func scrollToIdentifiedElement(
        _ app: XCUIApplication,
        _ identifier: String,
        direction: ScrollDirection = .down,
        maxSwipes: Int = 8,
        requireHittable: Bool = true
    ) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        for _ in 0..<maxSwipes where !element.exists || (requireHittable && !element.isHittable) {
            dragContent(app, direction: direction)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Expected element to exist after scrolling: \(identifier)")
        if requireHittable {
            XCTAssertTrue(element.isHittable, "Expected element to be hittable after scrolling: \(identifier)")
        }
        return element
    }

    private func scrollToText(
        _ app: XCUIApplication,
        _ text: String,
        direction: ScrollDirection = .down,
        maxSwipes: Int = 8
    ) {
        let label = app.staticTexts[text]
        for _ in 0..<maxSwipes where !label.exists {
            dragContent(app, direction: direction)
        }
        XCTAssertTrue(label.waitForExistence(timeout: 3), "Expected text to appear after scrolling: \(text)")
    }

    private func scrollToTextContaining(
        _ app: XCUIApplication,
        _ text: String,
        direction: ScrollDirection = .down,
        maxSwipes: Int = 8
    ) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let label = app.staticTexts.matching(predicate).firstMatch
        for _ in 0..<maxSwipes where !label.exists {
            dragContent(app, direction: direction)
        }
        XCTAssertTrue(label.waitForExistence(timeout: 3), "Expected text containing to appear after scrolling: \(text)")
    }

    private func openTeamWorkspace(_ app: XCUIApplication, expectedInitialText: String = "Apple Sign-In Required") {
        let teamCard = app.descendants(matching: .any)["teamWorkspaceCard"]
        if !teamCard.waitForExistence(timeout: 3) {
            tapButton(app, "tab_More", timeout: 12)
        }
        if !teamCard.isHittable {
            app.swipeDown()
        }
        let didFindTeamCard = teamCard.waitForExistence(timeout: 8)
        XCTAssertTrue(didFindTeamCard, "Team Workspace card should exist")
        tapElement(app, teamCard, description: "teamWorkspaceCard")
        waitForText(app, expectedInitialText, timeout: 25)
    }

    private func createFirebaseAccount(_ app: XCUIApplication, email: String, displayName: String, password: String) {
        scrollToButton(app, "Create a new test account").tap()
        let emailField = app.textFields["teamAccountEmailField"]
        scrollToElement(emailField, in: app, direction: .down, description: "team account email")
        typeText(email, into: emailField)
        dismissTeamKeyboardIfPresent(app)

        let passwordField = teamPasswordField(app)
        scrollToElement(passwordField, in: app, direction: .down, description: "team account password")
        typeText(password, into: passwordField)
        dismissTeamKeyboardIfPresent(app)

        let displayNameField = app.textFields["teamAccountDisplayNameField"]
        scrollToElement(displayNameField, in: app, direction: .down, description: "team account display name")
        typeText(displayName, into: displayNameField)
        dismissTeamKeyboardIfPresent(app)
        scrollToButton(app, "teamCreateAccountButton").tap()
        allowLocalNetworkPermissionIfPresented()
        if !app.staticTexts["Create or Accept Team"].waitForExistence(timeout: 8),
           dismissErrorAlertIfPresented(app) {
            scrollToButton(app, "teamCreateAccountButton").tap()
            allowLocalNetworkPermissionIfPresented(timeout: 2)
        }
        waitForText(app, "Create or Accept Team", timeout: 25)
        dismissKeychainPromptIfPresented(app, timeout: 1)
    }

    private func signInToFirebase(_ app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["teamAccountEmailField"]
        scrollToElement(emailField, in: app, direction: .down, description: "team account email")
        typeText(email, into: emailField)
        dismissTeamKeyboardIfPresent(app)

        let passwordField = teamPasswordField(app)
        scrollToElement(passwordField, in: app, direction: .down, description: "team account password")
        typeText(password, into: passwordField)
        dismissTeamKeyboardIfPresent(app)
        scrollToButton(app, "teamSignInButton").tap()
        allowLocalNetworkPermissionIfPresented()
        if !app.staticTexts["My Team"].waitForExistence(timeout: 8),
           dismissErrorAlertIfPresented(app) {
            scrollToButton(app, "teamSignInButton").tap()
            allowLocalNetworkPermissionIfPresented(timeout: 2)
        }
        waitForText(app, "My Team", timeout: 25)
        dismissKeychainPromptIfPresented(app)
    }

    private func signOutFromMore(_ app: XCUIApplication) {
        let backToMoreButton = app.buttons["teamBackToMoreButton"]
        if backToMoreButton.waitForExistence(timeout: 2), backToMoreButton.isHittable {
            backToMoreButton.tap()
        }
        if !app.buttons["signOutButton"].waitForExistence(timeout: 2) {
            tapButton(app, "tab_More", timeout: 12)
        }
        let signOutButton = scrollToButton(app, "signOutButton", direction: .down)
        signOutButton.tap()
        let alert = app.alerts["Sign Out"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "Sign-out confirmation should appear")
        alert.buttons["Sign Out"].tap()
        XCTAssertTrue(app.buttons["signOutButton"].waitForNonExistence(timeout: 20), "Sign-out button should disappear after sign out")
    }

    private func readInviteCode(_ app: XCUIApplication) -> String {
        XCTAssertTrue(
            app.descendants(matching: .any)["teamCreatedInvitePanel"].waitForExistence(timeout: 12),
            "Created invite panel should be visible"
        )
        XCTAssertTrue(
            app.buttons["teamCopyInviteCodeButton"].waitForExistence(timeout: 3),
            "Copy invite code button should be visible"
        )
        XCTAssertTrue(
            app.buttons["teamShareInviteCodeButton"].waitForExistence(timeout: 3),
            "Share invite code button should be visible"
        )
        let codePredicate = NSPredicate(format: "label MATCHES %@", "^[A-Z0-9]{8}$")
        let code = app.staticTexts.matching(codePredicate).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 12), "Generated invite code should be visible")
        return code.label
    }

    private func selectInviteWorkerType(_ app: XCUIApplication, technician: Bool, direction: ScrollDirection = .down) {
        let buttonIdentifier = technician ? "teamInviteWorkerTypeTechnicianButton" : "teamInviteWorkerTypeSalesRepButton"
        scrollToButton(app, buttonIdentifier, direction: direction, maxSwipes: 10).tap()
    }

    private func createInterestedLead(_ app: XCUIApplication, name: String) {
        if !app.buttons["addLeadButton"].waitForExistence(timeout: 4) {
            tapButton(app, "tab_Map", timeout: 12)
        }
        XCTAssertTrue(app.buttons["addLeadButton"].waitForExistence(timeout: 12), "Map add lead button should be ready before creating a team lead")
        tapButton(app, "addLeadButton", timeout: 12)
        typeText(name, into: app.textFields["addLeadNameField"])

        let statusMenu = app.buttons["addLeadStatusMenu"]
        for _ in 0..<6 where !statusMenu.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(statusMenu.waitForExistence(timeout: 8), "Status menu should exist")
        statusMenu.tap()
        tapButton(app, "Interested", timeout: 8)

        tapButton(app, "addLeadSaveButton", timeout: 8)
        denySystemPermissionIfPresented(timeout: 2)
        XCTAssertTrue(app.buttons["addLeadButton"].waitForExistence(timeout: 15), "Map add lead button should return after saving")

        // The team write is intentionally async so field reps are not blocked by network latency.
        sleep(4)
    }

    private func createNotHomeFollowUpLead(_ app: XCUIApplication, name: String) {
        if !app.buttons["addLeadButton"].waitForExistence(timeout: 4) {
            tapButton(app, "tab_Map", timeout: 12)
        }
        XCTAssertTrue(app.buttons["addLeadButton"].waitForExistence(timeout: 12), "Map add lead button should be ready before creating a follow-up lead")
        tapButton(app, "addLeadButton", timeout: 12)

        let clearDraftButton = app.buttons["Clear"]
        if clearDraftButton.waitForExistence(timeout: 2), clearDraftButton.isHittable {
            clearDraftButton.tap()
        }

        typeText(name, into: app.textFields["addLeadNameField"])
        let notHomeButton = app.buttons["Not Home"]
        for _ in 0..<6 where !notHomeButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(notHomeButton.waitForExistence(timeout: 8), "Not Home status should be available")
        notHomeButton.tap()

        tapButton(app, "addLeadSaveButton", timeout: 10)
        denySystemPermissionIfPresented(timeout: 2)
        XCTAssertTrue(app.buttons["addLeadButton"].waitForExistence(timeout: 15), "Saving a Not Home lead should return to the map")
    }

    private func createPersonalLeadThroughUI(_ app: XCUIApplication, name: String) {
        if !app.buttons["addLeadButton"].waitForExistence(timeout: 4) {
            tapButton(app, "tab_Map", timeout: 12)
        }
        XCTAssertTrue(app.buttons["addLeadButton"].waitForExistence(timeout: 12), "Map add lead button should be ready before creating a personal lead")
        tapButton(app, "addLeadButton", timeout: 12)

        let clearDraftButton = app.buttons["Clear"]
        if clearDraftButton.waitForExistence(timeout: 2), clearDraftButton.isHittable {
            clearDraftButton.tap()
        }

        typeText(name, into: app.textFields["addLeadNameField"])
        let addressField = app.textFields["addLeadAddressField"]
        typeText("123 UI Detail Test St", into: addressField)
        dismissKeyboardIfPresent(app)

        tapButton(app, "addLeadSaveButton", timeout: 10)
        denySystemPermissionIfPresented(timeout: 2)
        XCTAssertTrue(app.buttons["addLeadButton"].waitForExistence(timeout: 15), "Saving a personal lead should return to the map")
    }

    private func scheduleAppointmentThroughUI(_ app: XCUIApplication, leadName: String) {
        tapButton(app, "tab_Appts", timeout: 12)
        waitForIdentifiedElement(app, "appointmentsScreen", timeout: 12)
        tapButton(app, "appointmentsScheduleButton", timeout: 10)

        waitForIdentifiedElement(app, "appointmentLeadPickerSheet", timeout: 10)
        typeText(leadName, into: app.textFields["appointmentLeadSearchField"])
        dismissKeyboardIfPresent(app)

        let leadRow = app.descendants(matching: .any)["appointmentLeadSelectionRow"].firstMatch
        XCTAssertTrue(leadRow.waitForExistence(timeout: 10), "Eligible lead should appear in appointment lead picker")
        tapElement(app, leadRow, description: "appointmentLeadSelectionRow")

        waitForIdentifiedElement(app, "appointmentCreateForm", timeout: 12)
        waitForIdentifiedElement(app, "appointmentTitleField", timeout: 8)
        waitForIdentifiedElement(app, "appointmentLocationField", timeout: 8)
        tapButton(app, "appointmentScheduleSaveButton", timeout: 10)
        denySystemPermissionIfPresented(timeout: 2)

        waitForIdentifiedElement(app, "appointmentsScreen", timeout: 15)
        waitForTextContaining(app, leadName, timeout: 15)
    }

    private func denySystemPermissionIfPresented(timeout: TimeInterval = 4) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denyLabels = ["Don’t Allow", "Don't Allow"]

        for label in denyLabels {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: timeout) {
                button.tap()
                return
            }
        }
    }

    @MainActor
    func testTeamWorkspaceSetupDoesNotShowStalePermissionBanner() throws {
        let app = makeApp()
        app.launchArguments.append("-openMoreTabForUITests")
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        let teamCard = app.descendants(matching: .any)["teamWorkspaceCard"]
        if !teamCard.waitForExistence(timeout: 10) {
            tapButton(app, "tab_More", timeout: 12)
        }
        tapElement(app, teamCard, description: "teamWorkspaceCard")

        let setupTitle = app.staticTexts["Create or Accept Team"]
        let appleSignInTitle = app.staticTexts["Apple Sign-In Required"]
        let myTeamTitle = app.staticTexts["My Team"]
        let stalePermissionBanner = app.staticTexts["Team permissions need updating. Refresh Team or sign in again."]
        let offlineBanner = app.staticTexts["Team is offline. Showing saved team data until the connection returns."]
        let confirmationBanner = app.staticTexts["Team could not be confirmed with the cloud. Check your connection and try again."]

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline,
              !setupTitle.exists,
              !appleSignInTitle.exists,
              !myTeamTitle.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTAssertTrue(
            setupTitle.exists || appleSignInTitle.exists || myTeamTitle.exists,
            "Team screen should settle into setup, Apple sign-in, or an active team state"
        )
        XCTAssertFalse(stalePermissionBanner.exists, "Team screen should not show a stale permission banner")
        XCTAssertFalse(offlineBanner.exists, "Team screen should not incorrectly report offline for a stale Firebase session")
        XCTAssertFalse(confirmationBanner.exists, "Team screen should not show a cloud confirmation failure while recovering stale auth")
    }

    @MainActor
    func testTeamWorkspaceFirebaseAccountInviteJoinLeadAndOwnerAlert() throws {
        try requireTeamEmulatorUITestHarness()

        let credentials = teamUITestCredentials()
        let ownerEmail = credentials.ownerEmail
        let repEmail = credentials.repEmail
        let technicianEmail = credentials.technicianEmail
        let password = credentials.password
        let leadName = credentials.leadName

        let ownerApp = makeTeamEmulatorApp(
            autoAuthEmail: ownerEmail,
            autoAuthDisplayName: "Owner UI",
            autoAuthPassword: password,
            shouldCreateAutoAuthAccount: true
        )
        ownerApp.launch()
        denySystemPermissionIfPresented(timeout: 2)

        openTeamWorkspace(ownerApp, expectedInitialText: "Create or Accept Team")
        tapButton(ownerApp, "teamCreateTeamButton", timeout: 12)
        waitForText(ownerApp, "Team plan active", timeout: 25)
        _ = scrollToButtonEitherDirection(ownerApp, "teamCloseWorkspaceButton")

        selectInviteWorkerType(ownerApp, technician: true)
        scrollToButton(ownerApp, "teamCreateInviteButton", direction: .down).tap()
        let technicianInviteCode = readInviteCode(ownerApp)

        selectInviteWorkerType(ownerApp, technician: false, direction: .up)
        scrollToButton(ownerApp, "teamCreateInviteButton", direction: .down).tap()
        let inviteCode = readInviteCode(ownerApp)
        ownerApp.terminate()

        let technicianApp = makeTeamEmulatorApp(
            autoAuthEmail: technicianEmail,
            autoAuthDisplayName: "Tech UI",
            autoAuthPassword: password,
            shouldCreateAutoAuthAccount: true
        )
        technicianApp.launch()
        denySystemPermissionIfPresented(timeout: 2)

        openTeamWorkspace(technicianApp, expectedInitialText: "Create or Accept Team")
        typeText(technicianInviteCode, into: technicianApp.textFields["teamInviteCodeField"])
        dismissTeamKeyboardIfPresent(technicianApp)
        scrollToButton(technicianApp, "teamJoinTeamButton").tap()
        waitForText(technicianApp, "Joined team.", timeout: 25)
        scrollToText(technicianApp, "My Service Jobs", direction: .down)
        _ = scrollToButtonEitherDirection(technicianApp, "teamLeaveButton")
        technicianApp.terminate()

        let repApp = makeTeamEmulatorApp(
            autoAuthEmail: repEmail,
            autoAuthDisplayName: "Rep UI",
            autoAuthPassword: password,
            shouldCreateAutoAuthAccount: true
        )
        repApp.launch()
        denySystemPermissionIfPresented(timeout: 2)

        openTeamWorkspace(repApp, expectedInitialText: "Create or Accept Team")
        typeText(inviteCode, into: repApp.textFields["teamInviteCodeField"])
        dismissTeamKeyboardIfPresent(repApp)
        scrollToButton(repApp, "teamJoinTeamButton").tap()
        waitForText(repApp, "Joined team.", timeout: 25)
        waitForText(repApp, "My Team Work", timeout: 12)
        _ = scrollToButtonEitherDirection(repApp, "teamLeaveButton")

        scrollToButton(repApp, "teamDutyToggleButton", direction: .down).tap()
        waitForText(repApp, "Go Off Duty", timeout: 12)
        tapButton(repApp, "teamDutyToggleButton", timeout: 8)
        waitForText(repApp, "Go On Duty", timeout: 12)

        relaunch(repApp, opening: "-openMapTabForUITests")
        createInterestedLead(repApp, name: String(leadName))
        repApp.terminate()

        let ownerReturnApp = makeTeamEmulatorApp(
            autoAuthEmail: ownerEmail,
            autoAuthDisplayName: "Owner UI",
            autoAuthPassword: password,
            shouldCreateAutoAuthAccount: false
        )
        ownerReturnApp.launch()
        denySystemPermissionIfPresented(timeout: 2)

        openTeamWorkspace(ownerReturnApp, expectedInitialText: "My Team")
        scrollToText(ownerReturnApp, "Owner Alerts", direction: .up)
        waitForText(ownerReturnApp, "Rep marked a lead interested", timeout: 25)
        waitForTextContaining(ownerReturnApp, String(leadName), timeout: 25)
        scrollToText(ownerReturnApp, "Seats used", direction: .down)
        waitForText(ownerReturnApp, "3/3", timeout: 8)
        scrollToText(ownerReturnApp, "Field Map", direction: .down)
        XCTAssertTrue(
            ownerReturnApp.otherElements["teamFieldMapView"].waitForExistence(timeout: 8),
            "Owner Team Workspace should render the field map for rep work"
        )
        waitForTextContaining(ownerReturnApp, String(leadName), timeout: 8)

        relaunch(ownerReturnApp, opening: "-openLeadsTabForUITests")
        XCTAssertTrue(
            ownerReturnApp.otherElements["teamWorkInlineSection"].waitForExistence(timeout: 20),
            "Team work should be visible inside the main Leads tab"
        )
        waitForTextContaining(ownerReturnApp, String(leadName), timeout: 12)
        let teamLeadRow = ownerReturnApp.buttons["teamLeadInlineRow"].firstMatch
        XCTAssertTrue(teamLeadRow.waitForExistence(timeout: 12), "Team lead row should open detail from the main Leads tab")
        tapElement(ownerReturnApp, teamLeadRow, description: "teamLeadInlineRow")
        waitForText(ownerReturnApp, "Team Lead Detail", timeout: 12)
        waitForTextContaining(ownerReturnApp, String(leadName), timeout: 8)
        waitForText(ownerReturnApp, "Assigned to", timeout: 8)
        waitForText(ownerReturnApp, "Rep UI", timeout: 8)
        tapButton(ownerReturnApp, "teamLeadViewRepButton", timeout: 8)
        waitForText(ownerReturnApp, "Sales Rep", timeout: 8)
        waitForText(ownerReturnApp, "Rep UI", timeout: 8)
        tapButton(ownerReturnApp, "teamRepDetailCloseButton", timeout: 8)
        tapButton(ownerReturnApp, "teamLeadDetailCloseButton", timeout: 8)

        relaunch(ownerReturnApp, opening: "-openMapTabForUITests")
        tapButton(ownerReturnApp, "addLeadButton", timeout: 12)
        scrollToIdentifiedElement(ownerReturnApp, "addLeadTechnicianMenu", direction: .down)
        scrollToIdentifiedElement(ownerReturnApp, "addLeadTechnicianArrivalDatePicker", direction: .down)
        scrollToIdentifiedElement(ownerReturnApp, "addLeadTechnicianDurationStepper", direction: .down, requireHittable: false)
        tapButton(ownerReturnApp, "addLeadCancelButton", timeout: 8)
        XCTAssertTrue(
            ownerReturnApp.buttons["addLeadButton"].waitForExistence(timeout: 8),
            "Cancel should dismiss Add Lead after verifying technician job controls"
        )

        tapButton(ownerReturnApp, "teamMapShortcut", timeout: 12)
        waitForText(ownerReturnApp, "Team Field Map", timeout: 12)
    }

    @MainActor
    func testTeamPhysicalOwnerCreatesTeamAndInvite() throws {
        try requireTeamPhysicalUITestHarness()

        let credentials = teamUITestCredentials()
        let app = makeTeamEmulatorApp(
            autoAuthEmail: credentials.ownerEmail,
            autoAuthDisplayName: "Owner UI",
            autoAuthPassword: credentials.password,
            shouldCreateAutoAuthAccount: true
        )
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        openTeamWorkspace(app, expectedInitialText: "Create or Accept Team")
        tapButton(app, "teamCreateTeamButton", timeout: 12)
        waitForText(app, "Team plan active", timeout: 25)

        let createInviteButton = scrollToButton(app, "teamCreateInviteButton", direction: .down)
        createInviteButton.tap()
        let inviteCode = readInviteCode(app)
        print("TEAM_PHYSICAL_INVITE_CODE=\(inviteCode)")
    }

    @MainActor
    func testTeamPhysicalRepJoinsAndCreatesInterestedLead() throws {
        try requireTeamPhysicalUITestHarness()

        let credentials = teamUITestCredentials()
        guard let inviteCode = teamTestConfigValue(
            environmentKey: "D2D_TEAM_INVITE_CODE",
            infoKey: "D2DTeamInviteCode"
        ), !inviteCode.isEmpty else {
            throw XCTSkip("D2D_TEAM_INVITE_CODE is required for the rep physical-device Team test. Run the owner leg first.")
        }

        let app = makeTeamEmulatorApp(
            autoAuthEmail: credentials.repEmail,
            autoAuthDisplayName: "Rep UI",
            autoAuthPassword: credentials.password,
            shouldCreateAutoAuthAccount: true
        )
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        openTeamWorkspace(app, expectedInitialText: "Create or Accept Team")
        typeText(inviteCode, into: app.textFields["teamInviteCodeField"])
        dismissTeamKeyboardIfPresent(app)
        scrollToButton(app, "teamJoinTeamButton").tap()
        waitForText(app, "Joined team.", timeout: 25)
        waitForText(app, "My Team Work", timeout: 12)

        tapButton(app, "teamDutyToggleButton", timeout: 8)
        waitForText(app, "Go Off Duty", timeout: 12)
        tapButton(app, "teamDutyToggleButton", timeout: 8)
        waitForText(app, "Go On Duty", timeout: 12)

        relaunch(app, opening: "-openMapTabForUITests")
        createInterestedLead(app, name: credentials.leadName)
    }

    @MainActor
    func testTeamPhysicalOwnerSeesRepWork() throws {
        try requireTeamPhysicalUITestHarness()

        let credentials = teamUITestCredentials()
        let app = makeTeamEmulatorApp(
            autoAuthEmail: credentials.ownerEmail,
            autoAuthDisplayName: "Owner UI",
            autoAuthPassword: credentials.password,
            shouldCreateAutoAuthAccount: false
        )
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        openTeamWorkspace(app, expectedInitialText: "My Team")
        scrollToText(app, "Owner Alerts", direction: .up)
        waitForText(app, "Rep marked a lead interested", timeout: 25)
        waitForTextContaining(app, credentials.leadName, timeout: 25)
        scrollToText(app, "Seats used", direction: .down)
        waitForText(app, "2/3", timeout: 8)
        scrollToText(app, "Field Map", direction: .down)
        XCTAssertTrue(
            app.otherElements["teamFieldMapView"].waitForExistence(timeout: 8),
            "Owner Team Workspace should render the field map for rep work"
        )
        waitForTextContaining(app, credentials.leadName, timeout: 8)

        relaunch(app, opening: "-openLeadsTabForUITests")
        XCTAssertTrue(
            app.otherElements["teamWorkInlineSection"].waitForExistence(timeout: 20),
            "Team work should be visible inside the main Leads tab"
        )
        waitForTextContaining(app, credentials.leadName, timeout: 12)
        let teamLeadRow = app.buttons["teamLeadInlineRow"].firstMatch
        XCTAssertTrue(teamLeadRow.waitForExistence(timeout: 12), "Team lead row should open detail from the main Leads tab")
        tapElement(app, teamLeadRow, description: "teamLeadInlineRow")
        waitForText(app, "Team Lead Detail", timeout: 12)
        waitForTextContaining(app, credentials.leadName, timeout: 8)
        waitForText(app, "Assigned to", timeout: 8)
        waitForText(app, "Rep UI", timeout: 8)
        tapButton(app, "teamLeadViewRepButton", timeout: 8)
        waitForText(app, "Sales Rep", timeout: 8)
        waitForText(app, "Rep UI", timeout: 8)
        tapButton(app, "teamRepDetailCloseButton", timeout: 8)
        tapButton(app, "teamLeadDetailCloseButton", timeout: 8)

        relaunch(app, opening: "-openMapTabForUITests")
        tapButton(app, "teamMapShortcut", timeout: 12)
        waitForText(app, "Team Field Map", timeout: 12)
    }

    private func chooseRequiredOnboardingPreferences(_ app: XCUIApplication) {
        waitForText(app, "Welcome to D2D Advancer")
        tapButton(app, "onboardingContinueButton")

        waitForText(app, "What's your main focus?")
        tapButton(app, "onboardingSalesGoal_organizePipeline")
        tapButton(app, "onboardingContinueButton")

        waitForText(app, "What features interest you?")
        tapButton(app, "onboardingFocusArea_leadOrganization")
        tapButton(app, "onboardingContinueButton")

        waitForText(app, "How do you work?")
        tapButton(app, "onboardingWorkflowStyle_structured")
        tapButton(app, "onboardingContinueButton")
    }

    private func waitForMapReady(_ app: XCUIApplication, timeout: TimeInterval = 15) -> XCUIElement {
        let searchBtn = app.buttons["searchButton"]
        XCTAssertTrue(searchBtn.waitForExistence(timeout: timeout), "Search button should exist before map interactions")

        let mapView = app.maps.firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: timeout), "Map should exist")
        return mapView
    }

    private func dismissMapSheetIfPresented(_ app: XCUIApplication) {
        let closeClusterButton = app.buttons["Close cluster"]
        if closeClusterButton.waitForExistence(timeout: 1), closeClusterButton.isHittable {
            closeClusterButton.tap()
            return
        }

        let statusCancelButton = app.buttons["statusChangeCancelButton"]
        if statusCancelButton.waitForExistence(timeout: 1), statusCancelButton.isHittable {
            statusCancelButton.tap()
            return
        }

        let closePinButton = app.buttons["Close pin actions"]
        if closePinButton.waitForExistence(timeout: 1), closePinButton.isHittable {
            closePinButton.tap()
        }
    }

    private func openLongPressMenu(_ app: XCUIApplication, on mapView: XCUIElement) {
        let menu = app.descendants(matching: .any)["longPressMenuSheet"]
        let emptyMapCandidates = [
            CGVector(dx: 0.18, dy: 0.34),
            CGVector(dx: 0.76, dy: 0.46),
            CGVector(dx: 0.28, dy: 0.58),
            CGVector(dx: 0.62, dy: 0.32)
        ]

        for candidate in emptyMapCandidates {
            mapView.coordinate(withNormalizedOffset: candidate).press(forDuration: 1.5)
            if menu.waitForExistence(timeout: 3) {
                return
            }
            dismissMapSheetIfPresented(app)
        }

        XCTFail("Long press should open dropped-pin actions when pressing an empty map area")
    }

    @MainActor
    func testAddLeadFormCoreFieldsAndDismissSmoke() throws {
        let app = makeApp()
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        _ = waitForMapReady(app)
        tapButton(app, "addLeadButton", timeout: 12)

        for identifier in [
            "addLeadCancelButton",
            "addLeadSaveButton",
            "addLeadNameField",
            "addLeadPhoneField",
            "addLeadEmailField",
            "addLeadAddressField",
            "addLeadServiceCategoryAddButton",
            "addLeadPriceField",
            "addLeadStatusMenu",
            "addLeadNotesField"
        ] {
            waitForIdentifiedElement(app, identifier, timeout: 8)
        }

        tapIdentifiedElement(app, "addLeadServiceCategoryAddButton", direction: .down, timeout: 8)
        waitForIdentifiedElement(app, "serviceCategoryEditor", timeout: 10)
        let serviceName = "UI Service \(Int(Date().timeIntervalSince1970))"
        typeText(serviceName, into: app.textFields["serviceCategoryNameField"], timeout: 8)
        dismissKeyboardIfPresent(app)
        tapIdentifiedElement(app, "serviceCategoryIcon_wind", direction: .down, timeout: 8)
        tapIdentifiedElement(app, "serviceCategoryColor_green", direction: .down, timeout: 8)
        tapButton(app, "serviceCategorySaveButton", timeout: 8)
        waitForIdentifiedElement(app, "addLeadNameField", timeout: 10)
        waitForTextContaining(app, serviceName, timeout: 10)

        tapButton(app, "addLeadCancelButton", timeout: 8)
        XCTAssertTrue(
            app.buttons["addLeadButton"].waitForExistence(timeout: 8),
            "Cancel should dismiss Add Lead and return to the map"
        )
    }

    @MainActor
    func testAppointmentLeadPickerOpensAndDismissesSmoke() throws {
        let app = makeApp()
        app.launchArguments.append("-openAppointmentsTabForUITests")
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        waitForIdentifiedElement(app, "appointmentsScreen", timeout: 12)
        tapIdentifiedElement(app, "appointmentsScheduleButton", timeout: 12)

        waitForIdentifiedElement(app, "appointmentLeadPickerSheet", timeout: 8)
        waitForText(app, "Select Customer", timeout: 8)
        waitForIdentifiedElement(app, "appointmentLeadSearchField", timeout: 8)

        let emptyState = app.descendants(matching: .any)["appointmentLeadPickerEmptyState"]
        let leadRow = app.descendants(matching: .any)["appointmentLeadSelectionRow"]
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, !emptyState.exists, !leadRow.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(
            emptyState.exists || leadRow.exists,
            "Appointment lead picker should show either eligible leads or an empty state"
        )

        tapButton(app, "appointmentLeadPickerCancelButton", timeout: 8)
        XCTAssertTrue(
            app.descendants(matching: .any)["appointmentLeadPickerSheet"].waitForNonExistence(timeout: 5),
            "Appointment lead picker should dismiss cleanly"
        )
        waitForIdentifiedElement(app, "appointmentsScreen", timeout: 8)
    }

    @MainActor
    func testLeadListDetailEditSmoke() throws {
        let app = makeApp()
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        _ = waitForMapReady(app)
        let leadName = "UI Detail \(Int(Date().timeIntervalSince1970))"
        createPersonalLeadThroughUI(app, name: leadName)

        tapButton(app, "tab_Leads", timeout: 12)
        waitForIdentifiedElement(app, "leadsScreen", timeout: 12)
        waitForTextContaining(app, leadName, timeout: 15)

        let personalLeadRow = app.descendants(matching: .any)["personalLeadRow"].firstMatch
        XCTAssertTrue(personalLeadRow.waitForExistence(timeout: 10), "Newly created personal lead row should be visible")
        tapElement(app, personalLeadRow, description: "personalLeadRow")

        waitForTextContaining(app, leadName, timeout: 8)
        waitForIdentifiedElement(app, "leadDetailDeleteButton", timeout: 8)
        tapButton(app, "leadDetailDeleteButton", timeout: 8)
        waitForText(app, "Delete Lead", timeout: 8)
        app.buttons["Cancel"].tap()
        waitForIdentifiedElement(app, "leadDetailEditButton", timeout: 8)

        tapButton(app, "leadDetailEditButton", timeout: 8)
        waitForIdentifiedElement(app, "leadDetailCancelEditButton", timeout: 8)
        tapButton(app, "leadDetailCancelEditButton", timeout: 8)
        waitForIdentifiedElement(app, "leadDetailEditButton", timeout: 8)

        tapButton(app, "leadDetailEditButton", timeout: 8)
        waitForIdentifiedElement(app, "leadDetailSaveButton", timeout: 8)
        let nameField = app.textFields["leadDetailNameField"]
        typeText(" Updated", into: nameField, timeout: 8)
        dismissKeyboardIfPresent(app)
        scrollToIdentifiedElement(app, "leadDetailStatusMenu", direction: .down)
        scrollToIdentifiedElement(app, "leadDetailNotesField", direction: .down)
        tapButton(app, "leadDetailSaveButton", timeout: 8)

        waitForTextContaining(app, "\(leadName) Updated", timeout: 8)
        waitForIdentifiedElement(app, "leadDetailEditButton", timeout: 8)
    }

    @MainActor
    func testAppointmentCreateDetailDeleteSmoke() throws {
        let app = makeApp()
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        _ = waitForMapReady(app)
        let leadName = "UI Appt \(Int(Date().timeIntervalSince1970))"
        createInterestedLead(app, name: leadName)
        scheduleAppointmentThroughUI(app, leadName: leadName)

        let appointmentRow = app.descendants(matching: .any)["appointmentRow"].firstMatch
        XCTAssertTrue(appointmentRow.waitForExistence(timeout: 10), "Scheduled appointment row should be visible")
        tapElement(app, appointmentRow, description: "appointmentRow")

        waitForIdentifiedElement(app, "appointmentDetailScreen", timeout: 10)
        waitForIdentifiedElement(app, "appointmentDetailCancelButton", timeout: 8)
        waitForIdentifiedElement(app, "appointmentDetailCompleteButton", timeout: 8)
        waitForIdentifiedElement(app, "appointmentDetailEditButton", timeout: 8)
        waitForIdentifiedElement(app, "appointmentDetailDeleteButton", timeout: 8)
        waitForIdentifiedElement(app, "appointmentDetailDoneButton", timeout: 8)

        tapButton(app, "appointmentDetailDeleteButton", timeout: 8)
        let deleteAlert = app.alerts["Delete Appointment?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 8), "Delete confirmation should appear before removing an appointment")
        deleteAlert.buttons["Delete"].tap()

        waitForIdentifiedElement(app, "appointmentsScreen", timeout: 12)
        let deletedAppointmentText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", leadName)).firstMatch
        XCTAssertFalse(deletedAppointmentText.waitForExistence(timeout: 4), "Deleted test appointment should leave the appointment list")
    }

    @MainActor
    func testFollowUpDetailRescheduleCompleteSmoke() throws {
        let app = makeApp()
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        _ = waitForMapReady(app)
        let leadName = "UI Follow \(Int(Date().timeIntervalSince1970))"
        createNotHomeFollowUpLead(app, name: leadName)

        tapButton(app, "tab_Follow_Up", timeout: 12)
        waitForIdentifiedElement(app, "followUpScreen", timeout: 12)
        waitForTextContaining(app, leadName, timeout: 15)

        let followUpRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "followUpRow", leadName))
            .firstMatch
        XCTAssertTrue(followUpRow.waitForExistence(timeout: 10), "Created follow-up row should be tappable")
        tapElement(app, followUpRow, description: "created follow-up row")
        waitForIdentifiedElement(app, "followUpDetailScreen", timeout: 10)
        waitForIdentifiedElement(app, "followUpDetailCompleteButton", timeout: 8)
        waitForIdentifiedElement(app, "followUpDetailDoneButton", timeout: 8)
        waitForIdentifiedElement(app, "followUpDetailCheckInButton", timeout: 8)
        waitForIdentifiedElement(app, "followUpDetailRescheduleButton", timeout: 8)
        waitForIdentifiedElement(app, "followUpDetailViewLeadButton", timeout: 8)

        tapIdentifiedElement(app, "followUpDetailRescheduleButton", timeout: 8)
        waitForIdentifiedElement(app, "followUpRescheduleSheet", timeout: 10)
        tapIdentifiedElement(app, "followUpReschedule3DaysButton", timeout: 8)
        tapButton(app, "followUpRescheduleSaveButton", timeout: 8)
        waitForIdentifiedElement(app, "followUpDetailScreen", timeout: 10)

        tapIdentifiedElement(app, "followUpDetailCompleteButton", timeout: 8)
        waitForIdentifiedElement(app, "followUpScreen", timeout: 12)
        let completedFollowUp = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", leadName)).firstMatch
        XCTAssertFalse(completedFollowUp.waitForExistence(timeout: 5), "Completed follow-up should leave the Follow Up list")
    }

    @MainActor
    func testMessageTemplateCreatePreviewAndEditSmoke() throws {
        let app = makeApp()
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        tapButton(app, "tab_More", timeout: 12)
        tapIdentifiedElement(app, "moreMessageTemplatesCard", timeout: 12)
        waitForIdentifiedElement(app, "messageTemplatesScreen", timeout: 10)

        tapButton(app, "messageTemplateToolbarCreateButton", timeout: 8)
        waitForIdentifiedElement(app, "customTemplateEditorSheet", timeout: 10)

        let templateTitle = "UI Template \(Int(Date().timeIntervalSince1970))"
        typeText(templateTitle, into: app.textFields["customTemplateTitleField"], timeout: 8)
        dismissKeyboardIfPresent(app)

        let messageField = app.descendants(matching: .any)["customTemplateMessageField"]
        scrollToElement(messageField, in: app, direction: .down, description: "custom template message field")
        typeText("Hi {name}, this is a reusable follow up for {address}.", into: messageField, timeout: 8)
        let messageDoneButton = app.buttons["customTemplateMessageDoneButton"]
        if messageDoneButton.waitForExistence(timeout: 3), messageDoneButton.isHittable {
            messageDoneButton.tap()
        } else {
            dismissKeyboardIfPresent(app)
        }

        tapIdentifiedElement(app, "customTemplatePreviewButton", direction: .down, timeout: 8)
        waitForText(app, "Template Preview", timeout: 8)
        let previewCloseByIdentifier = app.descendants(matching: .any)
            .matching(identifier: "customTemplatePreviewCloseButton")
            .firstMatch
        if previewCloseByIdentifier.waitForExistence(timeout: 2) {
            tapElement(app, previewCloseByIdentifier, description: "customTemplatePreviewCloseButton")
        } else {
            let previewCloseByLabel = app.buttons["Close preview"]
            XCTAssertTrue(previewCloseByLabel.waitForExistence(timeout: 8), "Expected preview close button to appear")
            tapElement(app, previewCloseByLabel, description: "Close preview")
        }
        waitForIdentifiedElement(app, "customTemplateEditorSheet", timeout: 10)

        tapButton(app, "customTemplateSaveButton", timeout: 8)
        waitForIdentifiedElement(app, "messageTemplatesScreen", timeout: 10)
        waitForTextContaining(app, templateTitle, timeout: 10)

        let savedTemplateRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "messageTemplateRow", templateTitle))
            .firstMatch
        XCTAssertTrue(savedTemplateRow.waitForExistence(timeout: 8), "Saved custom template row should be visible")
        tapElement(app, savedTemplateRow, description: "saved custom template row")
        waitForIdentifiedElement(app, "customTemplateEditorSheet", timeout: 10)
        XCTAssertTrue(app.textFields["customTemplateTitleField"].waitForExistence(timeout: 8), "Custom template title field should be editable")
        tapButton(app, "customTemplateCancelButton", timeout: 8)
        waitForIdentifiedElement(app, "messageTemplatesScreen", timeout: 10)
    }

    @MainActor
    func testMoreSyncSettingsControlsSmoke() throws {
        let app = makeApp()
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        tapButton(app, "tab_More", timeout: 12)
        waitForIdentifiedElement(app, "moreSyncSettingsButton", timeout: 12)
        tapIdentifiedElement(app, "moreSyncSettingsButton", timeout: 8)

        waitForIdentifiedElement(app, "syncSettingsSheet", timeout: 10)
        waitForText(app, "Sync Settings", timeout: 8)
        waitForIdentifiedElement(app, "syncSettingsAutoSyncToggle", timeout: 8)

        for interval in ["30min", "1hour", "3hours", "6hours", "1day"] {
            waitForIdentifiedElement(app, "syncSettingsInterval_\(interval)", timeout: 8)
        }

        tapIdentifiedElement(app, "syncSettingsCloseButton", timeout: 8)
        XCTAssertFalse(
            app.descendants(matching: .any)["syncSettingsSheet"].waitForExistence(timeout: 5),
            "Sync settings sheet should close cleanly"
        )
        waitForIdentifiedElement(app, "moreSyncSettingsButton", timeout: 8)
    }

    @MainActor
    func testMoreAccountManagementSheetsSmoke() throws {
        try requireTeamEmulatorUITestHarness()

        let runId = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(8)
        let email = "account-ui-\(runId)@example.com"
        let password = teamUITestCredentials().password
        let app = makeTeamEmulatorApp(
            autoAuthEmail: email,
            autoAuthDisplayName: "Account UI",
            autoAuthPassword: password,
            shouldCreateAutoAuthAccount: true
        )
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        waitForIdentifiedElement(app, "moreAccountCard", timeout: 20)
        waitForText(app, "Account UI", timeout: 25)
        tapIdentifiedElement(app, "moreAccountCard", timeout: 8)

        waitForIdentifiedElement(app, "accountManagementScreen", timeout: 12)
        waitForTextContaining(app, email, timeout: 12)

        scrollToButton(app, "accountNameEditButton", direction: .down).tap()
        waitForIdentifiedElement(app, "accountNameField", timeout: 8)
        waitForIdentifiedElement(app, "accountNameSaveButton", timeout: 8)
        tapButton(app, "accountNameCancelButton", timeout: 8)

        scrollToButton(app, "accountChangePasswordButton", direction: .down).tap()
        waitForIdentifiedElement(app, "passwordChangeSheet", timeout: 10)
        waitForIdentifiedElement(app, "passwordChangeCurrentField", timeout: 8)
        waitForIdentifiedElement(app, "passwordChangeNewField", timeout: 8)
        waitForIdentifiedElement(app, "passwordChangeConfirmField", timeout: 8)
        waitForIdentifiedElement(app, "passwordChangeSubmitButton", timeout: 8)
        tapIdentifiedElement(app, "passwordChangeCloseButton", timeout: 8)
        XCTAssertFalse(
            app.descendants(matching: .any)["passwordChangeSheet"].waitForExistence(timeout: 5),
            "Password change sheet should close cleanly"
        )

        scrollToButton(app, "accountDeleteAccountButton", direction: .down).tap()
        waitForIdentifiedElement(app, "deleteAccountSheet", timeout: 10)
        waitForIdentifiedElement(app, "deleteAccountPasswordField", timeout: 8)
        waitForIdentifiedElement(app, "deleteAccountSubmitButton", timeout: 8)
        tapIdentifiedElement(app, "deleteAccountCloseButton", timeout: 8)
        XCTAssertFalse(
            app.descendants(matching: .any)["deleteAccountSheet"].waitForExistence(timeout: 5),
            "Delete account sheet should close cleanly"
        )
    }

    @MainActor
    func testMorePreferencesDestinationsSmoke() throws {
        let app = makeApp()
        app.launchArguments.append("-openMoreTabForUITests")
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        scrollToIdentifiedElement(app, "moreNotificationsCard", direction: .down)
        waitForIdentifiedElement(app, "moreCalendarSettingsCard", timeout: 8)
        waitForIdentifiedElement(app, "moreAppPreferencesCard", timeout: 8)
        waitForIdentifiedElement(app, "moreAppointmentTypesCard", timeout: 8)

        tapIdentifiedElement(app, "moreNotificationsCard", direction: .down, timeout: 8)
        waitForIdentifiedElement(app, "notificationSettingsScreen", timeout: 10)
        waitForIdentifiedElement(app, "notificationPlaySoundToggle", timeout: 8)
        _ = scrollToButton(app, "notificationRefreshAllButton", direction: .down)

        relaunch(app, opening: "-openMoreTabForUITests")
        scrollToIdentifiedElement(app, "moreCalendarSettingsCard", direction: .down)
        tapIdentifiedElement(app, "moreCalendarSettingsCard", direction: .down, timeout: 8)
        waitForText(app, "Calendar Settings", timeout: 10)
        waitForIdentifiedElement(app, "calendarSettingsEnableToggle", timeout: 8)

        relaunch(app, opening: "-openMoreTabForUITests")
        scrollToIdentifiedElement(app, "moreAppPreferencesCard", direction: .down)
        tapIdentifiedElement(app, "moreAppPreferencesCard", direction: .down, timeout: 8)
        waitForIdentifiedElement(app, "appPreferencesScreen", timeout: 10)
        waitForIdentifiedElement(app, "appPreferenceLeadStatusPicker", timeout: 8)
        waitForIdentifiedElement(app, "appPreferenceLeadSortPicker", timeout: 8)
        scrollToIdentifiedElement(app, "appPreferenceBackupFrequencyPicker", direction: .down)

        relaunch(app, opening: "-openMoreTabForUITests")
        scrollToIdentifiedElement(app, "moreAppointmentTypesCard", direction: .down)
        tapIdentifiedElement(app, "moreAppointmentTypesCard", direction: .down, timeout: 8)
        waitForIdentifiedElement(app, "appointmentTypesScreen", timeout: 10)
        waitForIdentifiedElement(app, "appointmentTypesCreateButton", timeout: 8)
        waitForIdentifiedElement(app, "appointmentTypesDoneButton", timeout: 8)

        tapButton(app, "appointmentTypesCreateButton", timeout: 8)
        waitForIdentifiedElement(app, "customAppointmentTypeEditor", timeout: 10)
        let typeName = "UI Type \(Int(Date().timeIntervalSince1970))"
        typeText(typeName, into: app.textFields["customAppointmentTypeNameField"], timeout: 8)
        dismissKeyboardIfPresent(app)
        tapIdentifiedElement(app, "customAppointmentTypeColor_green", direction: .down, timeout: 8)
        tapIdentifiedElement(app, "customAppointmentTypeIconButton", direction: .up, timeout: 8)
        waitForIdentifiedElement(app, "customAppointmentTypeIconPicker", timeout: 10)
        tapButton(app, "customAppointmentTypeIconPickerDoneButton", timeout: 8)
        waitForIdentifiedElement(app, "customAppointmentTypeEditor", timeout: 10)
        tapButton(app, "customAppointmentTypeSaveButton", timeout: 8)
        waitForIdentifiedElement(app, "appointmentTypesScreen", timeout: 10)
        waitForTextContaining(app, typeName, timeout: 10)

        let customTypeRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "customAppointmentTypeRow", typeName))
            .firstMatch
        XCTAssertTrue(customTypeRow.waitForExistence(timeout: 8), "Created custom appointment type should appear in the list")
        tapElement(app, customTypeRow, description: "customAppointmentTypeRow")
        waitForIdentifiedElement(app, "customAppointmentTypeEditor", timeout: 10)
        XCTAssertTrue(app.textFields["customAppointmentTypeNameField"].waitForExistence(timeout: 8), "Custom appointment type should reopen for editing")
        tapButton(app, "customAppointmentTypeCancelButton", timeout: 8)
        waitForIdentifiedElement(app, "appointmentTypesScreen", timeout: 10)
    }

    @MainActor
    func testPrimaryTabsAndMoreSurfacesSmoke() throws {
        let app = makeApp()
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        _ = waitForMapReady(app)
        for identifier in [
            "addLeadButton",
            "mapStyleButton",
            "threeDMapButton",
            "mapToolsButton",
            "quickAction_away",
            "quickAction_later",
            "quickAction_pass",
            "quickAction_interest"
        ] {
            XCTAssertTrue(
                app.buttons[identifier].waitForExistence(timeout: 8),
                "Map control should be available: \(identifier)"
            )
        }

        tapButton(app, "tab_Leads", timeout: 12)
        waitForIdentifiedElement(app, "leadsScreen", timeout: 12)
        waitForText(app, "Leads", timeout: 8)
        let sortChipLabels = ["Date Updated", "Date", "Status", "Name", "Address"]
        var leadSortChip: XCUIElement?
        for label in sortChipLabels {
            let candidate = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", label))
                .firstMatch
            if candidate.waitForExistence(timeout: 1) {
                leadSortChip = candidate
                break
            }
        }
        XCTAssertNotNil(leadSortChip, "Lead sort chip should be visible")

        tapButton(app, "tab_Follow_Up", timeout: 12)
        waitForIdentifiedElement(app, "followUpScreen", timeout: 12)
        waitForText(app, "Follow Up", timeout: 8)

        tapButton(app, "tab_Appts", timeout: 12)
        waitForIdentifiedElement(app, "appointmentsScreen", timeout: 12)
        waitForText(app, "Appointments", timeout: 8)
        XCTAssertTrue(
            app.buttons["Schedule appointment"].waitForExistence(timeout: 8),
            "Appointment schedule button should be available"
        )
        XCTAssertTrue(
            app.buttons["Active appointments"].waitForExistence(timeout: 8),
            "Appointment status tabs should be available"
        )

        tapButton(app, "tab_More", timeout: 12)
        waitForText(app, "More", timeout: 8)
        waitForIdentifiedElement(app, "moreOverviewCard", timeout: 8)
        waitForIdentifiedElement(app, "teamWorkspaceCard", timeout: 8)
        waitForIdentifiedElement(app, "moreMessageTemplatesCard", timeout: 8)
        waitForIdentifiedElement(app, "moreCloudStorageButton", timeout: 8)
        waitForIdentifiedElement(app, "moreExportLeadsButton", timeout: 8)
        waitForIdentifiedElement(app, "moreImportLeadsButton", timeout: 8)
        scrollToIdentifiedElement(app, "moreNotificationsCard", direction: .down)
        waitForIdentifiedElement(app, "moreCalendarSettingsCard", timeout: 8)
        waitForIdentifiedElement(app, "moreAppPreferencesCard", timeout: 8)
        waitForIdentifiedElement(app, "moreAppointmentTypesCard", timeout: 8)
        scrollToIdentifiedElement(app, "moreAccountCard", direction: .down)
        scrollToIdentifiedElement(app, "moreDarkModeCard", direction: .down)

        scrollToIdentifiedElement(app, "moreCloudStorageButton", direction: .up)
        tapIdentifiedElement(app, "moreCloudStorageButton", timeout: 8)
        waitForIdentifiedElement(app, "cloudProviderSheet", timeout: 8)
        waitForText(app, "Cloud Storage", timeout: 8)
        tapIdentifiedElement(app, "cloudProviderCloseButton", timeout: 8)

        relaunch(app, opening: "-openMoreTabForUITests")
        tapIdentifiedElement(app, "moreOverviewCard", timeout: 12)
        waitForTextContaining(app, "Lead volume", timeout: 12)

        relaunch(app, opening: "-openMoreTabForUITests")
        tapIdentifiedElement(app, "moreMessageTemplatesCard", timeout: 12)
        waitForTextContaining(app, "Manage reusable SMS", timeout: 12)
    }

    @MainActor
    func testMapToolsAndQuickActionSheetsSmoke() throws {
        let app = makeApp()
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        _ = waitForMapReady(app)

        tapButton(app, "mapToolsButton", timeout: 8)
        waitForIdentifiedElement(app, "mapToolsSheet", timeout: 8)
        waitForText(app, "Map Tools", timeout: 8)

        for identifier in [
            "mapWorkflowMode_all",
            "mapWorkflowMode_hot",
            "mapWorkflowMode_due",
            "mapWorkflowMode_sold",
            "mapStyle_standard",
            "mapStyle_satellite",
            "mapStyle_hybrid",
            "nextBestLeadButton",
            "routePlannerButton"
        ] {
            waitForIdentifiedElement(app, identifier, timeout: 8)
        }

        tapIdentifiedElement(app, "mapStyle_satellite", timeout: 8)
        tapIdentifiedElement(app, "mapStyle_hybrid", timeout: 8)
        tapIdentifiedElement(app, "mapStyle_standard", timeout: 8)

        tapIdentifiedElement(app, "mapWorkflowMode_hot", timeout: 8)
        XCTAssertTrue(app.staticTexts["Map Tools"].waitForNonExistence(timeout: 5), "Map tools should close after applying Hot")
        tapButton(app, "mapToolsButton", timeout: 8)
        waitForIdentifiedElement(app, "mapWorkflowStatusCard", timeout: 8)
        waitForTextContaining(app, "hot leads", timeout: 8)

        tapIdentifiedElement(app, "mapWorkflowMode_due", timeout: 8)
        XCTAssertTrue(app.staticTexts["Map Tools"].waitForNonExistence(timeout: 5), "Map tools should close after applying Due")
        tapButton(app, "mapToolsButton", timeout: 8)
        waitForIdentifiedElement(app, "mapWorkflowStatusCard", timeout: 8)
        waitForTextContaining(app, "due leads", timeout: 8)

        tapIdentifiedElement(app, "mapWorkflowMode_sold", timeout: 8)
        XCTAssertTrue(app.staticTexts["Map Tools"].waitForNonExistence(timeout: 5), "Map tools should close after applying Sold")
        tapButton(app, "mapToolsButton", timeout: 8)
        waitForIdentifiedElement(app, "mapWorkflowStatusCard", timeout: 8)
        waitForTextContaining(app, "sold leads", timeout: 8)

        tapIdentifiedElement(app, "mapWorkflowMode_all", timeout: 8)
        XCTAssertTrue(app.staticTexts["Map Tools"].waitForNonExistence(timeout: 5), "Map tools should close after resetting to All")

        tapButton(app, "mapToolsButton", timeout: 8)
        waitForIdentifiedElement(app, "mapToolsSheet", timeout: 8)
        tapIdentifiedElement(app, "routePlannerButton", timeout: 8)
        waitForIdentifiedElement(app, "routePlannerSheet", timeout: 10)
        waitForIdentifiedElement(app, "routePlannerFilter_followUps", timeout: 8)
        waitForIdentifiedElement(app, "routePlannerFilter_thisArea", timeout: 8)
        waitForIdentifiedElement(app, "routePlannerRecomputeButton", timeout: 8)
        tapIdentifiedElement(app, "routePlannerFilter_thisArea", timeout: 8)
        tapIdentifiedElement(app, "routePlannerRecomputeButton", timeout: 8)
        waitForIdentifiedElement(app, "routePlannerSheet", timeout: 8)
        tapIdentifiedElement(app, "routePlannerCloseButton", timeout: 8)
        XCTAssertTrue(app.descendants(matching: .any)["routePlannerSheet"].waitForNonExistence(timeout: 5), "Route planner should dismiss cleanly")

        tapButton(app, "quickAction_later", timeout: 8)
        waitForIdentifiedElement(app, "comeBackLaterSheet", timeout: 8)
        waitForText(app, "Come Back Later", timeout: 8)
        for identifier in [
            "comeBackQuickTime_1",
            "comeBackQuickTime_2",
            "comeBackQuickTime_4",
            "comeBackQuickTime_24",
            "saveCustomComeBackLeadButton"
        ] {
            waitForIdentifiedElement(app, identifier, timeout: 8)
        }
        tapButton(app, "Close come back later", timeout: 8)
        XCTAssertTrue(app.staticTexts["Come Back Later"].waitForNonExistence(timeout: 5), "Come Back Later sheet should dismiss cleanly")

        tapButton(app, "quickAction_interest", timeout: 8)
        waitForIdentifiedElement(app, "interestedQuickFormSheet", timeout: 8)
        waitForText(app, "Interested Lead", timeout: 8)
        waitForIdentifiedElement(app, "interestedQuickFormNameField", timeout: 8)
        waitForIdentifiedElement(app, "interestedQuickFormPhoneField", timeout: 8)
        waitForIdentifiedElement(app, "interestedQuickFormNoteField", timeout: 8)
        waitForIdentifiedElement(app, "saveInterestedLeadButton", timeout: 8)
    }

    @MainActor
    func testOnboardingCompletesIntoMainApp() throws {
        let app = makeOnboardingApp()
        app.launch()

        chooseRequiredOnboardingPreferences(app)

        waitForText(app, "Enable location services")
        tapButton(app, "onboardingContinueButton")
        denySystemPermissionIfPresented()

        waitForText(app, "Enable notifications")
        tapButton(app, "onboardingContinueButton")
        denySystemPermissionIfPresented()

        waitForText(app, "You're all set!")
        tapButton(app, "onboardingContinueButton")

        XCTAssertTrue(app.staticTexts["You're all set!"].waitForNonExistence(timeout: 8), "Onboarding should dismiss after completion")
        XCTAssertTrue(app.buttons["searchButton"].waitForExistence(timeout: 12), "Map search should be available after onboarding")
        XCTAssertTrue(app.buttons["tab_Map"].exists, "Main tab bar should be available after onboarding")
    }

    @MainActor
    func testSearchPinAndTap() throws {
        let app = makeApp()
        app.launch()
        sleep(5)
        screenshot(app, name: "01-MapLoaded")

        // Step 1: Tap search button
        let searchBtn = app.buttons["searchButton"]
        XCTAssertTrue(searchBtn.waitForExistence(timeout: 5), "Search button should exist")
        searchBtn.tap()
        sleep(2)
        screenshot(app, name: "02-SearchSheetOpen")

        // Step 2: Type address
        let searchField = app.textFields["mapSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should exist")
        searchField.tap()
        searchField.typeText("1 Dr Carlton B Goodlett Pl")
        sleep(3)
        screenshot(app, name: "03-SearchResults")

        // Step 3: Tap first result
        let firstResult = app.buttons["mapSearchResult_0"]
        XCTAssertTrue(firstResult.waitForExistence(timeout: 8), "Search should return at least one result")
        firstResult.tap()
        sleep(4)
        screenshot(app, name: "04-PinActionsPresented")

        // Selecting a result should open actions directly; a tiny pin tap is too brittle for users and tests.
        XCTAssertTrue(
            app.staticTexts["searchPinActionsTitle"].waitForExistence(timeout: 8),
            "Selecting a search result should show the search pin actions sheet"
        )
        XCTAssertTrue(
            app.buttons["searchPinAddLeadButton"].waitForExistence(timeout: 3),
            "Search pin actions should include Add New Lead Here"
        )
        screenshot(app, name: "06-PinActionsSheet")
    }

    @MainActor
    func testLongPressMenu() throws {
        let app = makeApp()
        app.launch()
        sleep(5)

        let mapView = waitForMapReady(app)

        openLongPressMenu(app, on: mapView)
        screenshot(app, name: "07-LongPressMenu")

        // Check for menu items
        let addLeadBtn = app.buttons["longPressAddLeadButton"]
        let streetViewBtn = app.buttons["longPressStreetViewButton"]
        waitForIdentifiedElement(app, "longPressMenuSheet", timeout: 5)
        waitForIdentifiedElement(app, "longPressConfirmedAddressField", timeout: 5)
        XCTAssertTrue(addLeadBtn.waitForExistence(timeout: 5), "Long press should show the Add Lead action")
        screenshot(app, name: "08-LongPressMenuVisible")
        XCTAssertTrue(streetViewBtn.exists, "Street View Here should exist")

        tapElement(app, streetViewBtn, description: "longPressStreetViewButton")
        waitForIdentifiedElement(app, "lookAroundSheet", timeout: 10)
        waitForIdentifiedElement(app, "streetViewLocationSummary", timeout: 8)
        waitForIdentifiedElement(app, "streetViewPreviewTitle", timeout: 8)
        waitForIdentifiedElement(app, "streetViewProvider_apple", timeout: 8)
        tapIdentifiedElement(app, "streetViewProvider_google", timeout: 8)
        waitForText(app, "Google Street View", timeout: 8)
        tapIdentifiedElement(app, "streetViewCloseButton", timeout: 8)
        XCTAssertTrue(
            app.descendants(matching: .any)["lookAroundSheet"].waitForNonExistence(timeout: 8),
            "Street View sheet should dismiss cleanly"
        )
    }

    @MainActor
    func testInterestedQuickFormHeaderDoesNotCrowdFirstField() throws {
        let app = makeApp()
        app.launch()

        _ = waitForMapReady(app)
        tapButton(app, "quickAction_interest", timeout: 8)

        let cancelButton = app.buttons["interestedQuickFormCloseButton"]
        let title = app.staticTexts["Interested Lead"]
        let nameField = app.textFields["interestedQuickFormNameField"]

        XCTAssertTrue(cancelButton.waitForExistence(timeout: 8), "Cancel button should appear in interested form")
        XCTAssertTrue(title.waitForExistence(timeout: 8), "Interested form title should appear")
        XCTAssertTrue(nameField.waitForExistence(timeout: 8), "Name field should appear")

        XCTAssertGreaterThanOrEqual(
            nameField.frame.minY - cancelButton.frame.maxY,
            12,
            "Cancel button should have clear vertical separation from the first field"
        )
        XCTAssertGreaterThanOrEqual(
            cancelButton.frame.minX - title.frame.maxX,
            8,
            "Close button should not crowd the title"
        )
    }
}
