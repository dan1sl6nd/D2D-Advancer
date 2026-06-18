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

    private func makeTeamEmulatorApp() -> XCUIApplication {
        let app = makeApp()
        app.launchArguments.append("-useFirebaseEmulators")
        app.launchArguments.append("-resetFirebaseAuthForUITests")
        app.launchArguments.append("-openMoreTabForUITests")
        return app
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

    private func dismissTeamKeyboardIfPresent(_ app: XCUIApplication) {
        let doneButton = app.buttons["teamKeyboardDoneButton"]
        if doneButton.waitForExistence(timeout: 2), doneButton.isHittable {
            doneButton.tap()
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

    private func openTeamWorkspace(_ app: XCUIApplication) {
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
        waitForText(app, "Apple Sign-In Required", timeout: 12)
    }

    private func createFirebaseAccount(_ app: XCUIApplication, email: String, displayName: String, password: String) {
        scrollToButton(app, "Create a new test account").tap()
        let emailField = app.textFields["teamAccountEmailField"]
        scrollToElement(emailField, in: app, direction: .down, description: "team account email")
        typeText(email, into: emailField)
        dismissTeamKeyboardIfPresent(app)

        let passwordField = app.secureTextFields["teamAccountPasswordField"]
        scrollToElement(passwordField, in: app, direction: .down, description: "team account password")
        typeText(password, into: passwordField)
        dismissTeamKeyboardIfPresent(app)

        let displayNameField = app.textFields["teamAccountDisplayNameField"]
        scrollToElement(displayNameField, in: app, direction: .down, description: "team account display name")
        typeText(displayName, into: displayNameField)
        dismissTeamKeyboardIfPresent(app)
        scrollToButton(app, "teamCreateAccountButton").tap()
        waitForText(app, "Create or Accept Team", timeout: 25)
    }

    private func signInToFirebase(_ app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["teamAccountEmailField"]
        scrollToElement(emailField, in: app, direction: .down, description: "team account email")
        typeText(email, into: emailField)
        dismissTeamKeyboardIfPresent(app)

        let passwordField = app.secureTextFields["teamAccountPasswordField"]
        scrollToElement(passwordField, in: app, direction: .down, description: "team account password")
        typeText(password, into: passwordField)
        dismissTeamKeyboardIfPresent(app)
        scrollToButton(app, "teamSignInButton").tap()
        waitForText(app, "My Team", timeout: 25)
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
        let codePredicate = NSPredicate(format: "label MATCHES %@", "^[A-Z0-9]{8}$")
        let code = app.staticTexts.matching(codePredicate).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 12), "Generated invite code should be visible")
        return code.label
    }

    private func createInterestedLead(_ app: XCUIApplication, name: String) {
        if !app.buttons["addLeadButton"].waitForExistence(timeout: 4) {
            tapButton(app, "tab_Map", timeout: 12)
        }
        XCTAssertTrue(app.buttons["teamMapShortcut"].waitForExistence(timeout: 15), "Team summary should load before creating a team lead")
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
    func testTeamWorkspaceFirebaseAccountInviteJoinLeadAndOwnerAlert() throws {
        let runId = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let ownerEmail = "owner-ui-\(runId)@example.com"
        let repEmail = "rep-ui-\(runId)@example.com"
        let password = "TestPass123!"
        let leadName = "UI Interested \(runId)"

        let app = makeTeamEmulatorApp()
        app.launch()
        denySystemPermissionIfPresented(timeout: 2)

        openTeamWorkspace(app)
        createFirebaseAccount(app, email: ownerEmail, displayName: "Owner UI", password: password)
        tapButton(app, "teamCreateTeamButton", timeout: 12)
        waitForText(app, "Team plan active", timeout: 25)

        let createInviteButton = scrollToButton(app, "teamCreateInviteButton", direction: .down)
        createInviteButton.tap()
        waitForText(app, "Invite code created.", timeout: 20)
        let inviteCode = readInviteCode(app)

        signOutFromMore(app)

        openTeamWorkspace(app)
        createFirebaseAccount(app, email: repEmail, displayName: "Rep UI", password: password)
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
        createInterestedLead(app, name: String(leadName))
        relaunch(app, opening: "-openMoreTabForUITests")
        signOutFromMore(app)

        openTeamWorkspace(app)
        signInToFirebase(app, email: ownerEmail, password: password)
        waitForText(app, "Field Map", timeout: 25)
        waitForText(app, "Rep Work", timeout: 25)
        waitForText(app, "Owner Alerts", timeout: 25)
        waitForText(app, "Rep marked a lead interested", timeout: 25)
        waitForTextContaining(app, String(leadName), timeout: 25)
        waitForText(app, "Seats used", timeout: 8)
        waitForText(app, "2/3", timeout: 8)

        relaunch(app, opening: "-openLeadsTabForUITests")
        XCTAssertTrue(
            app.otherElements["teamWorkInlineSection"].waitForExistence(timeout: 20),
            "Team work should be visible inside the main Leads tab"
        )
        waitForTextContaining(app, String(leadName), timeout: 12)

        relaunch(app, opening: "-openMapTabForUITests")
        XCTAssertTrue(
            app.buttons["teamMapShortcut"].waitForExistence(timeout: 12),
            "Team map shortcut should be visible inside the main Map tab"
        )
    }

    private func chooseRequiredOnboardingPreferences(_ app: XCUIApplication) {
        waitForText(app, "Set up your field workspace")
        tapButton(app, "onboardingContinueButton")

        waitForText(app, "What are you focused on?")
        tapButton(app, "Manage my leads")
        tapButton(app, "onboardingContinueButton")

        waitForText(app, "Choose your tools")
        tapButton(app, "Lead management")
        tapButton(app, "onboardingContinueButton")

        waitForText(app, "How do you like to work?")
        tapButton(app, "I like planning ahead")
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
    func testOnboardingCompletesIntoMainApp() throws {
        let app = makeOnboardingApp()
        app.launch()

        chooseRequiredOnboardingPreferences(app)

        waitForText(app, "Use your location?")
        tapButton(app, "onboardingContinueButton")
        denySystemPermissionIfPresented()

        waitForText(app, "Use reminders?")
        tapButton(app, "onboardingContinueButton")
        denySystemPermissionIfPresented()

        waitForText(app, "You're ready")
        tapButton(app, "onboardingContinueButton")

        XCTAssertTrue(app.staticTexts["You're ready"].waitForNonExistence(timeout: 8), "Onboarding should dismiss after completion")
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
        if firstResult.waitForExistence(timeout: 5) {
            firstResult.tap()
            sleep(4)
            screenshot(app, name: "04-PinDropped")

            // Step 4: Tap the blue pin on the map (center of screen where pin should be)
            let mapView = app.maps.firstMatch
            if mapView.waitForExistence(timeout: 3) {
                // The pin should be near the center after search zoomed there
                mapView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
                sleep(3)
                screenshot(app, name: "05-AfterPinTap")

                // Check if the search pin actions sheet appeared
                let addLeadBtn = app.buttons["Add New Lead Here"]
                let doneBtn = app.buttons["Done"]
                if addLeadBtn.waitForExistence(timeout: 3) {
                    screenshot(app, name: "06-PinActionsSheet")
                    XCTAssertTrue(addLeadBtn.exists, "Add New Lead Here button should exist")
                } else if doneBtn.exists {
                    screenshot(app, name: "06-PinActionsSheet-Done")
                }
            }
        }
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
        let addLeadBtn = app.staticTexts["Add Lead Here"]
        let streetViewBtn = app.staticTexts["Street View Here"]
        if addLeadBtn.waitForExistence(timeout: 3) {
            screenshot(app, name: "08-LongPressMenuVisible")
            XCTAssertTrue(streetViewBtn.exists, "Street View Here should exist")
        }
    }

    @MainActor
    func testInterestedQuickFormHeaderDoesNotCrowdFirstField() throws {
        let app = makeApp()
        app.launch()

        _ = waitForMapReady(app)
        tapButton(app, "quickAction_interest", timeout: 8)

        let cancelButton = app.buttons["Cancel"]
        let title = app.staticTexts["Interested Lead"]
        let nameField = app.textFields["Name"]

        XCTAssertTrue(cancelButton.waitForExistence(timeout: 8), "Cancel button should appear in interested form")
        XCTAssertTrue(title.waitForExistence(timeout: 8), "Interested form title should appear")
        XCTAssertTrue(nameField.waitForExistence(timeout: 8), "Name field should appear")

        XCTAssertGreaterThanOrEqual(
            nameField.frame.minY - cancelButton.frame.maxY,
            12,
            "Cancel button should have clear vertical separation from the first field"
        )
        XCTAssertLessThanOrEqual(
            cancelButton.frame.maxX + 8,
            title.frame.minX,
            "Cancel button should not crowd the centered title"
        )
    }
}
