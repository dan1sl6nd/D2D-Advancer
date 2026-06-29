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
        let button = app.buttons[identifier]
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
        let element = app.descendants(matching: .any)[identifier]
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

        let createInviteButton = scrollToButton(ownerApp, "teamCreateInviteButton", direction: .down)
        createInviteButton.tap()
        let inviteCode = readInviteCode(ownerApp)
        ownerApp.terminate()

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

        tapButton(repApp, "teamDutyToggleButton", timeout: 8)
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
        waitForText(ownerReturnApp, "2/3", timeout: 8)
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
            "addLeadPriceField",
            "addLeadStatusMenu",
            "addLeadNotesField"
        ] {
            waitForIdentifiedElement(app, identifier, timeout: 8)
        }

        tapButton(app, "addLeadCancelButton", timeout: 8)
        XCTAssertTrue(
            app.buttons["addLeadButton"].waitForExistence(timeout: 8),
            "Cancel should dismiss Add Lead and return to the map"
        )
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
        waitForIdentifiedElement(app, "moreAccountCard", timeout: 8)
        waitForIdentifiedElement(app, "moreDarkModeCard", timeout: 8)

        tapIdentifiedElement(app, "moreCloudStorageButton", timeout: 8)
        waitForIdentifiedElement(app, "cloudProviderSheet", timeout: 8)
        waitForText(app, "Cloud Storage", timeout: 8)
        tapButton(app, "Close cloud storage", timeout: 8)

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

        tapButton(app, "Close map tools", timeout: 8)
        XCTAssertTrue(app.staticTexts["Map Tools"].waitForNonExistence(timeout: 5), "Map tools should dismiss cleanly")

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

        // Long press on center of map
        mapView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.5)
        sleep(3)
        screenshot(app, name: "07-LongPressMenu")

        // Check for menu items
        let addLeadBtn = app.buttons["longPressAddLeadButton"]
        let streetViewBtn = app.buttons["longPressStreetViewButton"]
        waitForIdentifiedElement(app, "longPressMenuSheet", timeout: 5)
        waitForIdentifiedElement(app, "longPressConfirmedAddressField", timeout: 5)
        XCTAssertTrue(addLeadBtn.waitForExistence(timeout: 5), "Long press should show the Add Lead action")
        screenshot(app, name: "08-LongPressMenuVisible")
        XCTAssertTrue(streetViewBtn.exists, "Street View Here should exist")
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
