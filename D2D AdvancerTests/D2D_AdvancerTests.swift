//
//  D2D_AdvancerTests.swift
//  D2D AdvancerTests
//
//  Created by Daniil Mukashev on 17/08/2025.
//

import CoreLocation
import CoreGraphics
import CoreData
import Foundation
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import D2D_Advancer

struct D2D_AdvancerTests {

    @Test func cloudKitBackupServicesDoNotCrashUnentitledSimulatorLaunches() async throws {
        #if targetEnvironment(simulator)
        #expect(CloudKitLeadBackupService.shared == nil)
        #expect(CloudKitAppointmentBackupService.shared == nil)
        #expect(CloudKitAccountBackupService.shared == nil)
        #endif
    }

    @Test func cloudKitQueryCompatibilityDetectsRecordNameQueryableSchemaError() {
        let error = NSError(
            domain: "CKErrorDomain",
            code: 12,
            userInfo: [
                NSLocalizedDescriptionKey: "Field 'recordName' is not marked queryable"
            ]
        )

        #expect(CloudKitQueryCompatibility.isRecordNameNotQueryableError(error))
    }

    @Test func cloudKitQueryCompatibilityDetectsNestedRecordNameQueryableSchemaError() {
        let nestedError = NSError(
            domain: "CKErrorDomain",
            code: 12,
            userInfo: [
                NSLocalizedDescriptionKey: "Field 'recordName' is not marked queryable"
            ]
        )
        let wrappedError = NSError(
            domain: "CKErrorDomain",
            code: 2,
            userInfo: [
                NSUnderlyingErrorKey: nestedError
            ]
        )

        #expect(CloudKitQueryCompatibility.isRecordNameNotQueryableError(wrappedError))
    }

    @Test func cloudKitQueryCompatibilityIgnoresUnrelatedErrors() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [
                NSLocalizedDescriptionKey: "The Internet connection appears to be offline."
            ]
        )

        #expect(!CloudKitQueryCompatibility.isRecordNameNotQueryableError(error))
    }

    @Test func syncStatusSummaryExplainsCloudKitUnavailableFailures() async throws {
        let status = UserDataSyncManager.SyncStatus.failed(
            "CloudKit container unavailable or not entitled (iCloud.com.dan1sland.d2d.advancer)."
        )

        #expect(
            SyncStatusSummaryPolicy.shortText(
                for: status,
                autoSyncEnabled: true,
                intervalShortName: "1hr"
            ) == "iCloud unavailable"
        )
    }

    @Test func syncStatusSummaryDistinguishesOfflineFailuresFromGenericFailures() async throws {
        #expect(SyncStatusSummaryPolicy.failedShortText("Failed to get document because the client is offline.") == "Offline")
        #expect(SyncStatusSummaryPolicy.failedShortText("Permission denied") == "Failed")
    }

    @Test func initialMapCenterAcceptsRecentAccurateLocation() async throws {
        let now = Date()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-30)
        )

        #expect(LocationManager.isUsableForInitialMapCenter(location, now: now))
    }

    @Test func initialMapCenterRegionUsesLocationCoordinateAndAccuracySpan() async throws {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 1_000,
            verticalAccuracy: 10,
            timestamp: Date()
        )

        let region = LocationManager.initialMapCenterRegion(for: location)

        #expect(region.center.latitude == location.coordinate.latitude)
        #expect(region.center.longitude == location.coordinate.longitude)
        #expect(region.span.latitudeDelta == LocationManager.initialMapCenterSpan(for: location).latitudeDelta)
        #expect(region.span.longitudeDelta == LocationManager.initialMapCenterSpan(for: location).longitudeDelta)
    }

    @Test func initialMapCenterRegionDetectsAlreadyCenteredMap() async throws {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 40,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        let centeredRegion = LocationManager.initialMapCenterRegion(for: location)
        let shiftedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.5700, longitude: -79.7200),
            span: centeredRegion.span
        )

        #expect(LocationManager.isInitialMapCenterRegion(centeredRegion, centeredOn: location))
        #expect(!LocationManager.isInitialMapCenterRegion(shiftedRegion, centeredOn: location))
    }

    @Test func authorizationRefreshDoesNotRecenterWhenLaunchCenteringIsNotActive() async throws {
        #expect(
            !LocationManager.shouldApplyCachedAuthorizationRefreshLocation(
                startIfAuthorized: false,
                isLaunchLocationCenteringActive: false
            )
        )
        #expect(
            LocationManager.shouldApplyCachedAuthorizationRefreshLocation(
                startIfAuthorized: true,
                isLaunchLocationCenteringActive: false
            )
        )
        #expect(
            LocationManager.shouldApplyCachedAuthorizationRefreshLocation(
                startIfAuthorized: false,
                isLaunchLocationCenteringActive: true
            )
        )
    }

    @Test func launchMapCenterUsesSystemCachedLocationWhenAppLocationIsMissing() async throws {
        let now = Date()
        let systemCachedLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-20)
        )

        let candidate = try #require(
            LocationManager.bestLaunchMapCenterCandidate(from: [systemCachedLocation], now: now)
        )

        #expect(candidate.coordinate.latitude == systemCachedLocation.coordinate.latitude)
        #expect(candidate.coordinate.longitude == systemCachedLocation.coordinate.longitude)
    }

    @Test func launchMapCenterPrefersUsableSystemLocationOverStaleAppLocation() async throws {
        let now = Date()
        let staleAppLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-30 * 60)
        )
        let systemCachedLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 55,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-45)
        )

        let candidate = try #require(
            LocationManager.bestLaunchMapCenterCandidate(
                from: [staleAppLocation, systemCachedLocation],
                now: now
            )
        )

        #expect(candidate.coordinate.latitude == systemCachedLocation.coordinate.latitude)
        #expect(candidate.coordinate.longitude == systemCachedLocation.coordinate.longitude)
    }

    @Test func launchMapCenterPrefersNewerDistantLocationOverOlderAccurateCache() async throws {
        let now = Date()
        let olderAccurateButWrongLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-90)
        )
        let newerCurrentLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.559673, longitude: -79.707246),
            altitude: 0,
            horizontalAccuracy: 80,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-5)
        )

        let candidate = try #require(
            LocationManager.bestLaunchMapCenterCandidate(
                from: [olderAccurateButWrongLocation, newerCurrentLocation],
                now: now
            )
        )

        #expect(candidate.coordinate.latitude == newerCurrentLocation.coordinate.latitude)
        #expect(candidate.coordinate.longitude == newerCurrentLocation.coordinate.longitude)
    }

    @Test func launchMapCenterKeepsOlderAccurateLocationWhenNewerPointIsSamePlace() async throws {
        let now = Date()
        let olderAccurateLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.559673, longitude: -79.707246),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-90)
        )
        let newerNearbyLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.559690, longitude: -79.707260),
            altitude: 0,
            horizontalAccuracy: 90,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-5)
        )

        let candidate = try #require(
            LocationManager.bestLaunchMapCenterCandidate(
                from: [olderAccurateLocation, newerNearbyLocation],
                now: now
            )
        )

        #expect(candidate.coordinate.latitude == olderAccurateLocation.coordinate.latitude)
        #expect(candidate.coordinate.longitude == olderAccurateLocation.coordinate.longitude)
    }

    @Test func launchMapCenterRejectsOnlyStaleCachedCandidates() async throws {
        let now = Date()
        let staleLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-45 * 60)
        )

        #expect(LocationManager.bestLaunchMapCenterCandidate(from: [staleLocation], now: now) == nil)
    }

    @Test func launchMapUpdatePrefersBestLaunchCandidateOverDeliveredLastLocation() async throws {
        let now = Date()
        let freshCurrentLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-5)
        )
        let staleDeliveredLastLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0,
            horizontalAccuracy: 30,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-45 * 60)
        )

        let selectedLaunchLocation = try #require(
            LocationManager.locationForLaunchMapUpdate(
                deliveredLocations: [freshCurrentLocation, staleDeliveredLastLocation],
                currentLocation: nil,
                managerLocation: nil,
                isLaunchLocationCenteringActive: true,
                now: now
            )
        )
        let selectedRegularLocation = try #require(
            LocationManager.locationForLaunchMapUpdate(
                deliveredLocations: [freshCurrentLocation, staleDeliveredLastLocation],
                currentLocation: nil,
                managerLocation: nil,
                isLaunchLocationCenteringActive: false,
                now: now
            )
        )

        #expect(selectedLaunchLocation.coordinate.latitude == freshCurrentLocation.coordinate.latitude)
        #expect(selectedLaunchLocation.coordinate.longitude == freshCurrentLocation.coordinate.longitude)
        #expect(selectedRegularLocation.coordinate.latitude == staleDeliveredLastLocation.coordinate.latitude)
        #expect(selectedRegularLocation.coordinate.longitude == staleDeliveredLastLocation.coordinate.longitude)
    }

    @Test func initialMapCenterRejectsStaleCachedLocation() async throws {
        let now = Date()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-600)
        )

        #expect(!LocationManager.isUsableForInitialMapCenter(location, now: now))
    }

    @Test func provisionalLaunchMapCenterAcceptsSlightlyStaleAccurateLocation() async throws {
        let now = Date()
        let cachedLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 45,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-8 * 60)
        )

        #expect(!LocationManager.isUsableForInitialMapCenter(cachedLocation, now: now))
        #expect(LocationManager.isUsableForProvisionalInitialMapCenter(cachedLocation, now: now))
        #expect(
            LocationManager.shouldApplyProvisionalInitialMapCenter(
                hasInitialLocation: false,
                hasProvisionalInitialLocation: false,
                isLaunchLocationCenteringActive: true,
                candidateLocation: cachedLocation,
                now: now
            )
        )
    }

    @Test func provisionalLaunchMapCenterRejectsOldOrRepeatedLocations() async throws {
        let now = Date()
        let tooOldLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 45,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-45 * 60)
        )
        let freshLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 45,
            verticalAccuracy: 10,
            timestamp: now
        )

        #expect(!LocationManager.isUsableForProvisionalInitialMapCenter(tooOldLocation, now: now))
        #expect(
            !LocationManager.shouldApplyProvisionalInitialMapCenter(
                hasInitialLocation: false,
                hasProvisionalInitialLocation: false,
                isLaunchLocationCenteringActive: true,
                candidateLocation: tooOldLocation,
                now: now
            )
        )
        #expect(
            !LocationManager.shouldApplyProvisionalInitialMapCenter(
                hasInitialLocation: true,
                hasProvisionalInitialLocation: false,
                isLaunchLocationCenteringActive: true,
                candidateLocation: tooOldLocation,
                now: now
            )
        )
        #expect(
            !LocationManager.shouldApplyProvisionalInitialMapCenter(
                hasInitialLocation: false,
                hasProvisionalInitialLocation: true,
                isLaunchLocationCenteringActive: true,
                candidateLocation: tooOldLocation,
                now: now
            )
        )
        #expect(
            !LocationManager.shouldApplyProvisionalInitialMapCenter(
                hasInitialLocation: false,
                hasProvisionalInitialLocation: false,
                isLaunchLocationCenteringActive: true,
                candidateLocation: freshLocation,
                now: now
            )
        )
    }

    @Test func initialMapCenterAcceptsRecentApproximateLocationWithWiderSpan() async throws {
        let now = Date()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 1_000,
            verticalAccuracy: 10,
            timestamp: now
        )

        #expect(LocationManager.isUsableForInitialMapCenter(location, now: now))
        #expect(LocationManager.initialMapCenterSpan(for: location).latitudeDelta > LocationManager.initialMapCenterDefaultSpanDelta)
    }

    @Test func initialMapCenterAcceptsCurrentReducedAccuracyLocation() async throws {
        let now = Date()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 20_000,
            verticalAccuracy: 10,
            timestamp: now
        )

        #expect(LocationManager.isUsableForInitialMapCenter(location, now: now))
        #expect(LocationManager.initialMapCenterSpan(for: location).latitudeDelta == LocationManager.initialMapCenterMaximumSpanDelta)
    }

    @Test func initialMapCenterRejectsExtremelyInaccurateLocation() async throws {
        let now = Date()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 50_000,
            verticalAccuracy: 10,
            timestamp: now
        )

        #expect(!LocationManager.isUsableForInitialMapCenter(location, now: now))
    }

    @Test func initialMapCenterAllowsBetterFixAfterCoarseStartupLocation() async throws {
        let now = Date()
        let coarseStartupLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5510, longitude: -79.6950),
            altitude: 0,
            horizontalAccuracy: 3_000,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-15)
        )
        let betterGPSFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 80,
            verticalAccuracy: 10,
            timestamp: now
        )

        #expect(
            LocationManager.shouldAttemptInitialMapCenter(
                hasInitialLocation: true,
                wasFirstLocation: false,
                isLaunchLocationCenteringActive: false,
                previousLocation: coarseStartupLocation,
                candidateLocation: betterGPSFix
            )
        )
    }

    @Test func initialMapCenterDoesNotKeepRecenteringAfterGoodStartupLocation() async throws {
        let now = Date()
        let goodStartupLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 60,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-15)
        )
        let slightlyBetterGPSFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5600, longitude: -79.7074),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 10,
            timestamp: now
        )

        #expect(
            !LocationManager.shouldAttemptInitialMapCenter(
                hasInitialLocation: true,
                wasFirstLocation: false,
                isLaunchLocationCenteringActive: false,
                previousLocation: goodStartupLocation,
                candidateLocation: slightlyBetterGPSFix
            )
        )
    }

    @Test func launchMapCenterDoesNotReapplySameAccurateLocationDuringStartupWindow() async throws {
        let now = Date()
        let firstFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-2)
        )
        let repeatedFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.559701, longitude: -79.707201),
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now
        )

        #expect(
            !LocationManager.shouldAttemptInitialMapCenter(
                hasInitialLocation: true,
                wasFirstLocation: false,
                isLaunchLocationCenteringActive: true,
                previousLocation: firstFix,
                candidateLocation: repeatedFix
            )
        )
    }

    @Test func initialMapCenterAllowsDistantFreshFixAfterGoodCachedLocation() async throws {
        let now = Date()
        let cachedStartupLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417),
            altitude: 0,
            horizontalAccuracy: 60,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-90)
        )
        let currentGPSFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.559673, longitude: -79.707246),
            altitude: 0,
            horizontalAccuracy: 60,
            verticalAccuracy: 10,
            timestamp: now
        )

        #expect(
            LocationManager.shouldAttemptInitialMapCenter(
                hasInitialLocation: true,
                wasFirstLocation: false,
                isLaunchLocationCenteringActive: false,
                previousLocation: cachedStartupLocation,
                candidateLocation: currentGPSFix
            )
        )
    }

    @Test func launchLocationRequestPolicySkipsDuplicateInFlightRequests() async throws {
        #expect(
            !LocationManager.shouldStartLocationRequest(
                isRequestInFlight: true,
                locationRequestAttempts: 0,
                maxLocationRequestAttempts: 3,
                lastLocationRequestTime: nil,
                locationRequestCooldown: 10,
                isLaunchLocationCenteringActive: true
            )
        )
        #expect(
            LocationManager.shouldStartLocationRequest(
                isRequestInFlight: false,
                locationRequestAttempts: 0,
                maxLocationRequestAttempts: 3,
                lastLocationRequestTime: nil,
                locationRequestCooldown: 10,
                isLaunchLocationCenteringActive: true
            )
        )
    }

    @Test func locationRequestPolicyHonorsCooldownOutsideLaunchCentering() async throws {
        let now = Date()
        #expect(
            !LocationManager.shouldStartLocationRequest(
                isRequestInFlight: false,
                locationRequestAttempts: 1,
                maxLocationRequestAttempts: 3,
                lastLocationRequestTime: now.addingTimeInterval(-2),
                locationRequestCooldown: 10,
                isLaunchLocationCenteringActive: false,
                now: now
            )
        )
        #expect(
            LocationManager.shouldStartLocationRequest(
                isRequestInFlight: false,
                locationRequestAttempts: 1,
                maxLocationRequestAttempts: 3,
                lastLocationRequestTime: now.addingTimeInterval(-2),
                locationRequestCooldown: 10,
                isLaunchLocationCenteringActive: true,
                now: now
            )
        )
        #expect(
            !LocationManager.shouldStartLocationRequest(
                isRequestInFlight: false,
                locationRequestAttempts: 3,
                maxLocationRequestAttempts: 3,
                lastLocationRequestTime: nil,
                locationRequestCooldown: 10,
                isLaunchLocationCenteringActive: true,
                now: now
            )
        )
    }

    @Test func launchLocationRequestPolicyClearsStaleInFlightRequest() async throws {
        let now = Date()

        #expect(
            LocationManager.shouldClearStaleLocationRequest(
                isRequestInFlight: true,
                lastLocationRequestTime: now.addingTimeInterval(-9),
                staleTimeout: 8,
                isLaunchLocationCenteringActive: true,
                now: now
            )
        )
        #expect(
            !LocationManager.shouldClearStaleLocationRequest(
                isRequestInFlight: true,
                lastLocationRequestTime: now.addingTimeInterval(-3),
                staleTimeout: 8,
                isLaunchLocationCenteringActive: true,
                now: now
            )
        )
        #expect(
            !LocationManager.shouldClearStaleLocationRequest(
                isRequestInFlight: true,
                lastLocationRequestTime: now.addingTimeInterval(-9),
                staleTimeout: 8,
                isLaunchLocationCenteringActive: false,
                now: now
            )
        )
    }

    @Test func launchLocationRetriesUntilLiveInitialLocationArrives() async throws {
        #expect(
            LocationManager.shouldRetryLaunchLocationRequest(
                isLaunchLocationCenteringActive: true,
                hasLiveInitialLocation: false
            )
        )
        #expect(
            !LocationManager.shouldRetryLaunchLocationRequest(
                isLaunchLocationCenteringActive: true,
                hasLiveInitialLocation: true
            )
        )
        #expect(
            !LocationManager.shouldRetryLaunchLocationRequest(
                isLaunchLocationCenteringActive: false,
                hasLiveInitialLocation: false
            )
        )
    }

    @Test func staleLaunchLocationWatchdogOnlyRetriesOriginalInFlightRequest() async throws {
        let requestStartedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let staleNow = requestStartedAt.addingTimeInterval(9)
        let freshNow = requestStartedAt.addingTimeInterval(4)
        let newerRequestStartedAt = requestStartedAt.addingTimeInterval(1)

        #expect(
            LocationManager.shouldRunStaleLaunchLocationRequestWatchdog(
                isRequestInFlight: true,
                lastLocationRequestTime: requestStartedAt,
                watchedRequestStartedAt: requestStartedAt,
                staleTimeout: 8,
                isLaunchLocationCenteringActive: true,
                hasLiveInitialLocation: false,
                now: staleNow
            )
        )
        #expect(
            !LocationManager.shouldRunStaleLaunchLocationRequestWatchdog(
                isRequestInFlight: true,
                lastLocationRequestTime: requestStartedAt,
                watchedRequestStartedAt: requestStartedAt,
                staleTimeout: 8,
                isLaunchLocationCenteringActive: true,
                hasLiveInitialLocation: false,
                now: freshNow
            )
        )
        #expect(
            !LocationManager.shouldRunStaleLaunchLocationRequestWatchdog(
                isRequestInFlight: true,
                lastLocationRequestTime: newerRequestStartedAt,
                watchedRequestStartedAt: requestStartedAt,
                staleTimeout: 8,
                isLaunchLocationCenteringActive: true,
                hasLiveInitialLocation: false,
                now: staleNow
            )
        )
        #expect(
            !LocationManager.shouldRunStaleLaunchLocationRequestWatchdog(
                isRequestInFlight: true,
                lastLocationRequestTime: requestStartedAt,
                watchedRequestStartedAt: requestStartedAt,
                staleTimeout: 8,
                isLaunchLocationCenteringActive: true,
                hasLiveInitialLocation: true,
                now: staleNow
            )
        )
        #expect(
            !LocationManager.shouldRunStaleLaunchLocationRequestWatchdog(
                isRequestInFlight: false,
                lastLocationRequestTime: requestStartedAt,
                watchedRequestStartedAt: requestStartedAt,
                staleTimeout: 8,
                isLaunchLocationCenteringActive: true,
                hasLiveInitialLocation: false,
                now: staleNow
            )
        )
    }

    @Test func launchLocationOnlyTreatsCurrentLaunchWindowFixAsLive() async throws {
        let launchStartedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let now = launchStartedAt.addingTimeInterval(8)

        func makeLocation(timestamp: Date, accuracy: CLLocationAccuracy = 35) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
                altitude: 0,
                horizontalAccuracy: accuracy,
                verticalAccuracy: 10,
                timestamp: timestamp
            )
        }

        let liveFix = makeLocation(timestamp: launchStartedAt.addingTimeInterval(2))
        let acceptablePrelaunchFix = makeLocation(
            timestamp: launchStartedAt.addingTimeInterval(-LocationManager.liveInitialMapCenterTimestampSlack + 1)
        )
        let staleCachedFix = makeLocation(timestamp: launchStartedAt.addingTimeInterval(-60))
        let inaccurateFix = makeLocation(timestamp: launchStartedAt.addingTimeInterval(2), accuracy: 30_000)
        let recentWithoutLaunchWindow = makeLocation(timestamp: now.addingTimeInterval(-5))
        let staleWithoutLaunchWindow = makeLocation(timestamp: now.addingTimeInterval(-60))

        #expect(LocationManager.isLiveForLaunchInitialMapCenter(liveFix, launchStartedAt: launchStartedAt, now: now))
        #expect(LocationManager.isLiveForLaunchInitialMapCenter(acceptablePrelaunchFix, launchStartedAt: launchStartedAt, now: now))
        #expect(!LocationManager.isLiveForLaunchInitialMapCenter(staleCachedFix, launchStartedAt: launchStartedAt, now: now))
        #expect(!LocationManager.isLiveForLaunchInitialMapCenter(inaccurateFix, launchStartedAt: launchStartedAt, now: now))
        #expect(LocationManager.isLiveForLaunchInitialMapCenter(recentWithoutLaunchWindow, launchStartedAt: nil, now: now))
        #expect(!LocationManager.isLiveForLaunchInitialMapCenter(staleWithoutLaunchWindow, launchStartedAt: nil, now: now))
    }

    @Test func launchMapFollowPolicyRequiresVisibleLocationLaunchIntentAndNoGesture() async throws {
        #expect(
            AdvancedMapView.shouldFollowUserLocationOnLaunch(
                showsUserLocation: true,
                shouldUseUserLocation: true,
                userHasInteracted: false
            )
        )
        #expect(
            !AdvancedMapView.shouldFollowUserLocationOnLaunch(
                showsUserLocation: false,
                shouldUseUserLocation: true,
                userHasInteracted: false
            )
        )
        #expect(
            !AdvancedMapView.shouldFollowUserLocationOnLaunch(
                showsUserLocation: true,
                shouldUseUserLocation: false,
                userHasInteracted: false
            )
        )
        #expect(
            !AdvancedMapView.shouldFollowUserLocationOnLaunch(
                showsUserLocation: true,
                shouldUseUserLocation: true,
                userHasInteracted: true
            )
        )
    }

    @Test func launchMapInteractionLockResetsOnlyWhenOpenTokenChanges() async throws {
        #expect(
            AdvancedMapView.shouldResetLaunchInteractionLock(
                previousToken: nil,
                currentToken: 0
            )
        )
        #expect(
            !AdvancedMapView.shouldResetLaunchInteractionLock(
                previousToken: 2,
                currentToken: 2
            )
        )
        #expect(
            AdvancedMapView.shouldResetLaunchInteractionLock(
                previousToken: 2,
                currentToken: 3
            )
        )
    }

    @Test func launchMapForcesStartupRegionWhenAcceptedLocationRevisionChanges() async throws {
        #expect(
            AdvancedMapView.shouldForceStartupRegionUpdate(
                previousRevision: nil,
                currentRevision: 1,
                showsUserLocation: true,
                shouldUseUserLocation: true,
                userHasInteracted: false
            )
        )
        #expect(
            AdvancedMapView.shouldForceStartupRegionUpdate(
                previousRevision: 1,
                currentRevision: 2,
                showsUserLocation: true,
                shouldUseUserLocation: true,
                userHasInteracted: false
            )
        )
        #expect(
            !AdvancedMapView.shouldForceStartupRegionUpdate(
                previousRevision: 2,
                currentRevision: 2,
                showsUserLocation: true,
                shouldUseUserLocation: true,
                userHasInteracted: false
            )
        )
        #expect(
            !AdvancedMapView.shouldForceStartupRegionUpdate(
                previousRevision: nil,
                currentRevision: 0,
                showsUserLocation: true,
                shouldUseUserLocation: true,
                userHasInteracted: false
            )
        )
        #expect(
            AdvancedMapView.shouldForceStartupRegionUpdate(
                previousRevision: 1,
                currentRevision: 2,
                showsUserLocation: true,
                shouldUseUserLocation: false,
                userHasInteracted: false
            )
        )
        #expect(
            AdvancedMapView.shouldForceStartupRegionUpdate(
                previousRevision: 1,
                currentRevision: 2,
                showsUserLocation: false,
                shouldUseUserLocation: true,
                userHasInteracted: false
            )
        )
        #expect(
            !AdvancedMapView.shouldForceStartupRegionUpdate(
                previousRevision: 1,
                currentRevision: 2,
                showsUserLocation: true,
                shouldUseUserLocation: true,
                userHasInteracted: true
            )
        )
    }

    @MainActor
    @Test func launchMapUserGestureInterruptsPendingProgrammaticStartupCentering() async throws {
        let coordinator = AdvancedMapView.Coordinator(makeAdvancedMapViewForTests())
        coordinator.isProgrammaticChange = true
        coordinator.userHasInteracted = false
        coordinator.isUserInteracting = false

        coordinator.handleRegionWillChange(userGesture: true)

        #expect(coordinator.userHasInteracted)
        #expect(coordinator.isUserInteracting)
        #expect(!coordinator.isProgrammaticChange)
    }

    @MainActor
    @Test func launchMapProgrammaticRegionChangeDoesNotSetUserInteractionLock() async throws {
        let coordinator = AdvancedMapView.Coordinator(makeAdvancedMapViewForTests())
        coordinator.isProgrammaticChange = true
        coordinator.userHasInteracted = false
        coordinator.isUserInteracting = false

        coordinator.handleRegionWillChange(userGesture: false)

        #expect(!coordinator.userHasInteracted)
        #expect(!coordinator.isUserInteracting)
        #expect(coordinator.isProgrammaticChange)
    }

    @Test func launchMapAppliesFirstStartupFollowEvenWhenMapIsAlreadyNearTarget() async throws {
        let targetRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let visuallyCloseButNotAppliedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559705, longitude: -79.707205),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        #expect(
            AdvancedMapView.shouldApplyStartupRegionUpdate(
                currentRegion: visuallyCloseButNotAppliedRegion,
                targetRegion: targetRegion,
                userHasInteracted: false,
                shouldFollowUserLocationOnLaunch: true,
                lastAppliedStartupTargetRegion: nil
            )
        )
        #expect(
            !AdvancedMapView.shouldApplyStartupRegionUpdate(
                currentRegion: targetRegion,
                targetRegion: targetRegion,
                userHasInteracted: false,
                shouldFollowUserLocationOnLaunch: true,
                lastAppliedStartupTargetRegion: targetRegion
            )
        )
        #expect(
            !AdvancedMapView.shouldApplyStartupRegionUpdate(
                currentRegion: visuallyCloseButNotAppliedRegion,
                targetRegion: targetRegion,
                userHasInteracted: true,
                shouldFollowUserLocationOnLaunch: true,
                lastAppliedStartupTargetRegion: nil
            )
        )
        #expect(
            !AdvancedMapView.shouldApplyStartupRegionUpdate(
                currentRegion: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 43.610000, longitude: -79.740000),
                    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                ),
                targetRegion: targetRegion,
                userHasInteracted: false,
                shouldFollowUserLocationOnLaunch: false,
                lastAppliedStartupTargetRegion: targetRegion
            )
        )
    }

    @Test func launchMapFallsBackToVisibleUserLocationWhenBindingMissesBlueDot() async throws {
        let now = Date()
        let oldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        let visibleUserLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now
        )
        let provisionalVisibleUserLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-600)
        )
        let staleVisibleUserLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-30 * 60)
        )

        #expect(
            AdvancedMapView.shouldApplyVisibleUserLocationFallback(
                currentRegion: oldRegion,
                userLocation: visibleUserLocation,
                userHasInteracted: false,
                shouldFollowUserLocationOnLaunch: true
            )
        )
        #expect(
            !AdvancedMapView.shouldApplyVisibleUserLocationFallback(
                currentRegion: oldRegion,
                userLocation: visibleUserLocation,
                userHasInteracted: true,
                shouldFollowUserLocationOnLaunch: true
            )
        )
        #expect(
            AdvancedMapView.shouldApplyVisibleUserLocationFallback(
                currentRegion: oldRegion,
                userLocation: provisionalVisibleUserLocation,
                userHasInteracted: false,
                shouldFollowUserLocationOnLaunch: true
            )
        )
        #expect(
            !AdvancedMapView.shouldApplyVisibleUserLocationFallback(
                currentRegion: oldRegion,
                userLocation: staleVisibleUserLocation,
                userHasInteracted: false,
                shouldFollowUserLocationOnLaunch: true
            )
        )
    }

    @Test func launchMapAppliesFirstVisibleUserLocationEvenAfterPrematureConfirmation() async throws {
        let now = Date()
        let oldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        let visibleUserLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now
        )
        let staleVisibleUserLocation = CLLocation(
            coordinate: visibleUserLocation.coordinate,
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-30 * 60)
        )

        #expect(
            AdvancedMapView.shouldApplyFirstVisibleUserLocationCenter(
                currentRegion: oldRegion,
                userLocation: visibleUserLocation,
                userHasInteracted: false,
                hasAppliedFirstVisibleUserLocationCenter: false,
                showsUserLocation: true
            )
        )
        #expect(
            !AdvancedMapView.shouldApplyFirstVisibleUserLocationCenter(
                currentRegion: oldRegion,
                userLocation: visibleUserLocation,
                userHasInteracted: true,
                hasAppliedFirstVisibleUserLocationCenter: false,
                showsUserLocation: true
            )
        )
        #expect(
            !AdvancedMapView.shouldApplyFirstVisibleUserLocationCenter(
                currentRegion: oldRegion,
                userLocation: visibleUserLocation,
                userHasInteracted: false,
                hasAppliedFirstVisibleUserLocationCenter: true,
                showsUserLocation: true
            )
        )
        #expect(
            !AdvancedMapView.shouldApplyFirstVisibleUserLocationCenter(
                currentRegion: oldRegion,
                userLocation: staleVisibleUserLocation,
                userHasInteracted: false,
                hasAppliedFirstVisibleUserLocationCenter: false,
                showsUserLocation: true
            )
        )
    }

    @Test func launchMapDoesNotReenableMapKitFollowAfterStartupRegionUpdate() async throws {
        #expect(
            !AdvancedMapView.shouldReapplyUserFollowModeAfterStartupRegionUpdate(
                shouldFollowUserLocationOnLaunch: true,
                didApplyStartupRegionUpdate: true
            )
        )
        #expect(
            !AdvancedMapView.shouldReapplyUserFollowModeAfterStartupRegionUpdate(
                shouldFollowUserLocationOnLaunch: true,
                didApplyStartupRegionUpdate: false
            )
        )
        #expect(
            !AdvancedMapView.shouldReapplyUserFollowModeAfterStartupRegionUpdate(
                shouldFollowUserLocationOnLaunch: false,
                didApplyStartupRegionUpdate: true
            )
        )
    }

    @Test func launchMapKeepsCenteringUntilVisibleMapIsConfirmed() async throws {
        #expect(
            AdvancedMapView.shouldCenterUserLocationOnLaunch(
                showsUserLocation: true,
                shouldUseUserLocation: false,
                needsLaunchLocationCenteringConfirmation: true,
                userHasInteracted: false
            )
        )
        #expect(
            !AdvancedMapView.shouldCenterUserLocationOnLaunch(
                showsUserLocation: true,
                shouldUseUserLocation: false,
                needsLaunchLocationCenteringConfirmation: true,
                userHasInteracted: true
            )
        )
        #expect(
            !AdvancedMapView.shouldCenterUserLocationOnLaunch(
                showsUserLocation: true,
                shouldUseUserLocation: false,
                needsLaunchLocationCenteringConfirmation: false,
                userHasInteracted: false
            )
        )
        #expect(
            !AdvancedMapView.shouldCenterUserLocationOnLaunch(
                showsUserLocation: false,
                shouldUseUserLocation: true,
                needsLaunchLocationCenteringConfirmation: true,
                userHasInteracted: false
            )
        )
    }

    @Test func launchMapRetriesStartupCenterWhenVisibleCameraMissesTarget() async throws {
        let targetRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let stillShowingOldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.610000, longitude: -79.740000),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )

        #expect(
            AdvancedMapView.shouldRetryStartupMapCenter(
                currentRegion: stillShowingOldRegion,
                targetRegion: targetRegion,
                userHasInteracted: false,
                attempt: 0,
                maxAttempts: 4
            )
        )
        #expect(
            !AdvancedMapView.shouldRetryStartupMapCenter(
                currentRegion: stillShowingOldRegion,
                targetRegion: targetRegion,
                userHasInteracted: true,
                attempt: 0,
                maxAttempts: 4
            )
        )
        #expect(
            !AdvancedMapView.shouldRetryStartupMapCenter(
                currentRegion: stillShowingOldRegion,
                targetRegion: targetRegion,
                userHasInteracted: false,
                attempt: 4,
                maxAttempts: 4
            )
        )
        #expect(
            !AdvancedMapView.shouldRetryStartupMapCenter(
                currentRegion: targetRegion,
                targetRegion: targetRegion,
                userHasInteracted: false,
                attempt: 0,
                maxAttempts: 4
            )
        )
    }

    @Test func launchMapConfirmsOnlyWhenVisibleCameraMatchesStartupTarget() async throws {
        let targetRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let centeredRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559701, longitude: -79.707201),
            span: MKCoordinateSpan(latitudeDelta: 0.01005, longitudeDelta: 0.01005)
        )
        let oldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.620000, longitude: -79.720000),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )

        #expect(
            AdvancedMapView.isStartupMapCentered(
                currentRegion: centeredRegion,
                targetRegion: targetRegion
            )
        )
        #expect(
            !AdvancedMapView.isStartupMapCentered(
                currentRegion: oldRegion,
                targetRegion: targetRegion
            )
        )
    }

    @Test func launchMapConfirmationUsesLastAppliedStartupTargetWhenBindingChanges() async throws {
        let userTargetRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let staleBindingRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.774900, longitude: -122.419400),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )

        let confirmationTarget = AdvancedMapView.startupConfirmationTarget(
            lastAppliedStartupTargetRegion: userTargetRegion,
            parentRegion: staleBindingRegion
        )

        #expect(confirmationTarget.center.latitude == userTargetRegion.center.latitude)
        #expect(confirmationTarget.center.longitude == userTargetRegion.center.longitude)
        #expect(confirmationTarget.span.latitudeDelta == userTargetRegion.span.latitudeDelta)
        #expect(confirmationTarget.span.longitudeDelta == userTargetRegion.span.longitudeDelta)
    }

    @Test func launchMapDoesNotSyncStaleVisibleRegionBeforeStartupCenterIsConfirmed() async throws {
        let targetRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let staleVisibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.774900, longitude: -122.419400),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )

        #expect(
            !AdvancedMapView.shouldSyncVisibleRegionBackToBinding(
                changeWasProgrammatic: false,
                needsLaunchLocationCenteringConfirmation: true,
                userHasInteracted: false,
                currentRegion: staleVisibleRegion,
                targetRegion: targetRegion
            )
        )
        #expect(
            AdvancedMapView.shouldSyncVisibleRegionBackToBinding(
                changeWasProgrammatic: false,
                needsLaunchLocationCenteringConfirmation: true,
                userHasInteracted: false,
                currentRegion: targetRegion,
                targetRegion: targetRegion
            )
        )
        #expect(
            AdvancedMapView.shouldSyncVisibleRegionBackToBinding(
                changeWasProgrammatic: false,
                needsLaunchLocationCenteringConfirmation: true,
                userHasInteracted: true,
                currentRegion: staleVisibleRegion,
                targetRegion: targetRegion
            )
        )
        #expect(
            !AdvancedMapView.shouldSyncVisibleRegionBackToBinding(
                changeWasProgrammatic: true,
                needsLaunchLocationCenteringConfirmation: false,
                userHasInteracted: true,
                currentRegion: staleVisibleRegion,
                targetRegion: targetRegion
            )
        )
    }

    @Test func advancedMapViewPublishesVisibleRegionOnlyWhenRegionChanges() async throws {
        let previousRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let sameRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559701, longitude: -79.707201),
            span: MKCoordinateSpan(latitudeDelta: 0.01005, longitudeDelta: 0.01005)
        )
        let movedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.570000, longitude: -79.710000),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let zoomedRegion = MKCoordinateRegion(
            center: previousRegion.center,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )

        #expect(!AdvancedMapView.shouldPublishVisibleRegion(sameRegion, previousRegion: previousRegion))
        #expect(AdvancedMapView.shouldPublishVisibleRegion(movedRegion, previousRegion: previousRegion))
        #expect(AdvancedMapView.shouldPublishVisibleRegion(zoomedRegion, previousRegion: previousRegion))
    }

    @Test func launchMapCenteringUsesCenteredUserLocationMargins() async throws {
        let launchMargins = AdvancedMapView.userLocationViewportPadding(
            forHeight: 852,
            isLaunchCenteringActive: true
        )
        let controlAvoidanceMargins = AdvancedMapView.userLocationViewportPadding(
            forHeight: 852,
            isLaunchCenteringActive: false
        )
        let mapKitMargins = AdvancedMapView.mapKitLayoutMargins(
            forHeight: 852,
            isLaunchCenteringActive: false
        )

        #expect(launchMargins.top == launchMargins.bottom)
        #expect(launchMargins.left == launchMargins.right)
        #expect(launchMargins.top <= 24)
        #expect(controlAvoidanceMargins.bottom > launchMargins.bottom)
        #expect(controlAvoidanceMargins.right > launchMargins.right)
        #expect(mapKitMargins.top == mapKitMargins.bottom)
        #expect(mapKitMargins.left == mapKitMargins.right)
        #expect(mapKitMargins.right <= launchMargins.right)
    }

    @Test func launchMapUsesUsableViewportForStartupCentering() async throws {
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let padding = AdvancedMapView.userLocationViewportPadding(
            forHeight: bounds.height,
            isLaunchCenteringActive: false
        )
        let usableCenter = AdvancedMapView.usableViewportCenter(
            bounds: bounds,
            padding: padding
        )

        #expect(usableCenter.x == bounds.midX)
        #expect(usableCenter.y < bounds.midY)
        #expect(
            AdvancedMapView.isScreenPointCenteredInUsableViewport(
                usableCenter,
                bounds: bounds,
                padding: padding,
                tolerance: 8
            )
        )
        #expect(
            !AdvancedMapView.isScreenPointCenteredInUsableViewport(
                CGPoint(x: bounds.midX, y: bounds.midY),
                bounds: bounds,
                padding: padding,
                tolerance: 8
            )
        )
        #expect(
            AdvancedMapView.shouldRespectVisibleControlsForStartupCentering(
                showsUserLocation: true,
                shouldFollowUserLocationOnLaunch: true,
                needsLaunchLocationCenteringConfirmation: true
            )
        )
        #expect(
            !AdvancedMapView.shouldRespectVisibleControlsForStartupCentering(
                showsUserLocation: false,
                shouldFollowUserLocationOnLaunch: false,
                needsLaunchLocationCenteringConfirmation: true
            )
        )
    }

    @Test func visibleControlAdjustedRegionPreservesZoomWhileMovingTargetIntoUsableViewport() async throws {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559673, longitude: -79.707246),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let padding = AdvancedMapView.userLocationViewportPadding(
            forHeight: bounds.height,
            isLaunchCenteringActive: false
        )
        let adjusted = AdvancedMapView.visibleControlAdjustedRegion(
            for: region,
            in: bounds,
            padding: padding
        )

        #expect(adjusted.span.latitudeDelta == region.span.latitudeDelta)
        #expect(adjusted.span.longitudeDelta == region.span.longitudeDelta)
        #expect(adjusted.center.latitude < region.center.latitude)
        #expect(abs(adjusted.center.latitude - region.center.latitude) < region.span.latitudeDelta * 0.04)
        #expect(abs(adjusted.center.longitude - region.center.longitude) < 0.0000001)
    }

    @Test func mapForegroundOnlyReopensLaunchCenteringWhenStartupStillNeedsIt() async throws {
        #expect(
            MapLaunchCenteringPolicy.shouldPrepareOnForeground(
                isAuthorized: true,
                didCenterMapOnLaunch: false,
                isLaunchCenteringActive: false,
                hasUsableLocation: true,
                mapIsCenteredOnUser: true
            )
        )
        #expect(
            !MapLaunchCenteringPolicy.shouldPrepareOnForeground(
                isAuthorized: true,
                didCenterMapOnLaunch: true,
                isLaunchCenteringActive: true,
                hasUsableLocation: true,
                mapIsCenteredOnUser: true
            )
        )
        #expect(
            MapLaunchCenteringPolicy.shouldPrepareOnForeground(
                isAuthorized: true,
                didCenterMapOnLaunch: true,
                isLaunchCenteringActive: false,
                hasUsableLocation: false,
                mapIsCenteredOnUser: false
            )
        )
        #expect(
            MapLaunchCenteringPolicy.shouldPrepareOnForeground(
                isAuthorized: true,
                didCenterMapOnLaunch: true,
                isLaunchCenteringActive: false,
                hasUsableLocation: true,
                mapIsCenteredOnUser: false
            )
        )
        #expect(
            !MapLaunchCenteringPolicy.shouldPrepareOnForeground(
                isAuthorized: true,
                didCenterMapOnLaunch: true,
                isLaunchCenteringActive: false,
                hasUsableLocation: true,
                mapIsCenteredOnUser: true
            )
        )
        #expect(
            !MapLaunchCenteringPolicy.shouldPrepareOnForeground(
                isAuthorized: false,
                didCenterMapOnLaunch: false,
                isLaunchCenteringActive: true,
                hasUsableLocation: false,
                mapIsCenteredOnUser: false
            )
        )
    }

    @Test func mapForegroundDetectsWhenVisibleRegionIsAwayFromUser() async throws {
        let now = Date()
        let userLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200),
            altitude: 0,
            horizontalAccuracy: 20,
            verticalAccuracy: 20,
            timestamp: now
        )
        let centeredRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559701, longitude: -79.707201),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let awayRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.610000, longitude: -79.740000),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        #expect(
            MapLaunchCenteringPolicy.isMapCenteredOnUser(
                region: centeredRegion,
                location: userLocation
            )
        )
        #expect(
            !MapLaunchCenteringPolicy.isMapCenteredOnUser(
                region: awayRegion,
                location: userLocation
            )
        )
    }

    @Test func launchMapStopsApplyingCenterAfterVisibleMapConfirms() async throws {
        #expect(
            MapLaunchCenteringPolicy.shouldApplyLaunchCenteringRequest(
                visibleMapCenteredConfirmed: false,
                isLaunchCenteringActive: false
            )
        )
        #expect(
            !MapLaunchCenteringPolicy.shouldApplyLaunchCenteringRequest(
                visibleMapCenteredConfirmed: true,
                isLaunchCenteringActive: true
            )
        )
        #expect(
            !MapLaunchCenteringPolicy.shouldApplyLaunchCenteringRequest(
                visibleMapCenteredConfirmed: true,
                isLaunchCenteringActive: false
            )
        )
    }

    @Test func launchMapConfirmationRequiresRegionTargetingUsableUserLocation() async throws {
        let now = Date()
        let userLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200),
            altitude: 0,
            horizontalAccuracy: 20,
            verticalAccuracy: 20,
            timestamp: now
        )
        let staleUserLocation = CLLocation(
            coordinate: userLocation.coordinate,
            altitude: 0,
            horizontalAccuracy: 20,
            verticalAccuracy: 20,
            timestamp: now.addingTimeInterval(-30 * 60)
        )
        let defaultRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.774900, longitude: -122.419400),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let userRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.559701, longitude: -79.707201),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        #expect(
            !MapLaunchCenteringPolicy.hasUsableLaunchLocationTarget(
                region: defaultRegion,
                location: userLocation
            )
        )
        #expect(
            !MapLaunchCenteringPolicy.hasUsableLaunchLocationTarget(
                region: userRegion,
                location: staleUserLocation
            )
        )
        #expect(
            MapLaunchCenteringPolicy.hasUsableLaunchLocationTarget(
                region: userRegion,
                location: userLocation
            )
        )
    }

    @Test func addLeadDraftAddressOnlyRestoresForSameCoordinate() async throws {
        let currentCoordinate = CLLocationCoordinate2D(latitude: 43.55970000, longitude: -79.70720000)

        #expect(
            AddLeadDraftAddressPolicy.canRestoreAddress(
                draftLatitude: "43.55970001",
                draftLongitude: "-79.70719999",
                currentCoordinate: currentCoordinate
            )
        )

        #expect(
            !AddLeadDraftAddressPolicy.canRestoreAddress(
                draftLatitude: "43.56428045",
                draftLongitude: "-79.70397107",
                currentCoordinate: currentCoordinate
            )
        )
    }

    @Test func addLeadDraftAddressRejectsLegacyDraftWithoutCoordinate() async throws {
        #expect(
            !AddLeadDraftAddressPolicy.canRestoreAddress(
                draftLatitude: nil,
                draftLongitude: nil,
                currentCoordinate: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072)
            )
        )
    }

    @Test func searchPresetSaveTrimsPersistsAndDeletes() async throws {
        let suiteName = "SearchPresetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "search_presets_test"
        let manager = SearchFilterManager(userDefaults: defaults, presetsKey: key)
        manager.currentFilter.text = "windows"
        manager.currentFilter.selectedStatuses = [.interested]

        #expect(manager.savePreset(name: "  Interested Windows  "))
        #expect(manager.savedPresets.count == 1)
        #expect(manager.savedPresets.first?.name == "Interested Windows")

        let reloadedManager = SearchFilterManager(userDefaults: defaults, presetsKey: key)
        #expect(reloadedManager.savedPresets.count == 1)
        #expect(reloadedManager.savedPresets.first?.filter.text == "windows")
        #expect(reloadedManager.savedPresets.first?.filter.selectedStatuses == [.interested])

        let preset = try #require(reloadedManager.savedPresets.first)
        #expect(reloadedManager.deletePreset(preset))
        #expect(reloadedManager.savedPresets.isEmpty)
        #expect(SearchFilterManager(userDefaults: defaults, presetsKey: key).savedPresets.isEmpty)
    }

    @Test func searchPresetRejectsBlankNamesAndSurfacesCorruptStorage() async throws {
        let suiteName = "SearchPresetCorruptTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "search_presets_corrupt_test"
        let manager = SearchFilterManager(userDefaults: defaults, presetsKey: key)
        #expect(!manager.savePreset(name: "   "))
        #expect(manager.savedPresets.isEmpty)
        #expect(manager.lastErrorMessage == "Preset name cannot be empty.")

        defaults.set(Data("not-json".utf8), forKey: key)
        let corruptManager = SearchFilterManager(userDefaults: defaults, presetsKey: key)
        #expect(corruptManager.savedPresets.isEmpty)
        #expect(corruptManager.lastErrorMessage?.contains("Could not load saved search presets") == true)
        corruptManager.currentFilter.text = "windows"
        #expect(!corruptManager.savePreset(name: "Interested Windows"))
        #expect(defaults.data(forKey: key) == Data("not-json".utf8))

        let invertedRangePresetJSON = """
        [{
          "id": "11111111-2222-3333-4444-555555555555",
          "name": "Bad Range",
          "filter": {
            "visitCountRange": [10, 1]
          },
          "dateCreated": 0
        }]
        """
        let invertedRangePresetData = try #require(invertedRangePresetJSON.data(using: .utf8))
        defaults.set(invertedRangePresetData, forKey: key)
        let invertedRangeManager = SearchFilterManager(userDefaults: defaults, presetsKey: key)
        #expect(invertedRangeManager.savedPresets.isEmpty)
        #expect(invertedRangeManager.lastErrorMessage?.contains("Could not load saved search presets") == true)
        invertedRangeManager.currentFilter.text = "windows"
        #expect(!invertedRangeManager.savePreset(name: "Interested Windows"))
        #expect(defaults.data(forKey: key) == invertedRangePresetData)
    }

    @Test func customAppointmentTypesDoNotOverwriteCorruptStorage() throws {
        let suiteName = "CustomAppointmentTypeCorruptTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "custom_appointment_types_corrupt_test"
        let corruptData = Data("not-json".utf8)
        defaults.set(corruptData, forKey: key)

        let manager = CustomAppointmentTypeManager(userDefaults: defaults, customTypesKey: key)
        #expect(manager.customTypes.isEmpty)
        #expect(manager.lastErrorMessage?.contains("Could not load saved appointment types") == true)

        let type = CustomAppointmentType(name: "Quote Review", icon: "doc.text", color: "blue")
        #expect(!manager.addCustomType(type))
        #expect(defaults.data(forKey: key) == corruptData)
        #expect(manager.lastErrorMessage?.contains("left untouched") == true)
    }

    @Test func customServiceCategoriesDoNotOverwriteCorruptStorage() throws {
        let suiteName = "ServiceCategoryCorruptTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "custom_service_categories_corrupt_test"
        let corruptData = Data("not-json".utf8)
        defaults.set(corruptData, forKey: key)

        let manager = ServiceCategoryManager(userDefaults: defaults, customCategoriesKey: key)
        #expect(manager.customCategories.isEmpty)
        #expect(manager.lastErrorMessage?.contains("Could not load saved service categories") == true)

        let category = ServiceCategory(name: "Exterior Detail", icon: "sparkles", color: "green")
        #expect(!manager.addCustomCategory(category))
        #expect(defaults.data(forKey: key) == corruptData)
        #expect(manager.lastErrorMessage?.contains("left untouched") == true)
    }

    @Test func customMessageTemplatesDoNotOverwriteCorruptStorage() throws {
        let suiteName = "MessageTemplateCorruptTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "custom_message_templates_corrupt_test"
        let corruptData = Data("not-json".utf8)
        defaults.set(corruptData, forKey: key)

        let manager = FollowUpMessageTemplates(userDefaults: defaults, customTemplatesKey: key)
        #expect(manager.customTemplates.isEmpty)
        #expect(manager.lastErrorMessage?.contains("Could not load saved message templates") == true)

        let template = MessageTemplate(
            title: "Quick ETA",
            message: "Hi {name}, I am on the way.",
            category: .scheduling,
            isForSMS: true,
            isForEmail: false
        )
        #expect(!manager.addCustomTemplate(template))
        #expect(defaults.data(forKey: key) == corruptData)
        #expect(manager.lastErrorMessage?.contains("left untouched") == true)
    }

    @MainActor
    @Test func csvImportSkipsNewRowsWithoutUsableCoordinates() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lead-import-coordinate-test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        let csv = """
        Name,Latitude,Longitude
        No Location,,
        Zero Island,0,0
        Out Of Bounds,91,-79
        Good Lead,43.5597,-79.7072
        """
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let result = try LeadCSVService.importLeads(from: url, into: context)
        #expect(result.created == 1)
        #expect(result.skipped == 3)
        #expect(result.errors.filter { $0.contains("missing valid Latitude/Longitude") }.count == 3)

        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        let leads = try context.fetch(request)
        #expect(leads.count == 1)
        #expect(leads.first?.name == "Good Lead")
        #expect(leads.first?.latitude == 43.5597)
        #expect(leads.first?.longitude == -79.7072)
    }

    @MainActor
    @Test func csvImportUpdatesExistingLeadWithoutReplacingMissingCoordinates() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let existing = Lead.create(in: context)
        let id = try #require(existing.id)
        existing.name = "Original"
        existing.phone = "555-0000"
        existing.latitude = 43.5597
        existing.longitude = -79.7072
        try context.save()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lead-import-existing-coordinate-test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        let csv = """
        ID,Name,Phone
        \(id.uuidString),Updated,555-1234
        """
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let result = try LeadCSVService.importLeads(from: url, into: context)
        #expect(result.created == 0)
        #expect(result.updated == 1)
        #expect(result.skipped == 0)

        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        let leads = try context.fetch(request)
        #expect(leads.count == 1)
        #expect(leads.first?.name == "Updated")
        #expect(leads.first?.phone == "555-1234")
        #expect(leads.first?.latitude == 43.5597)
        #expect(leads.first?.longitude == -79.7072)
    }

    @MainActor
    @Test func csvImportClearsExistingFollowUpWhenStatusBecomesTerminal() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let existing = Lead.create(in: context)
        let id = try #require(existing.id)
        let oldFollowUpDate = Date(timeIntervalSince1970: 1_800_000_000)
        existing.name = "Original"
        existing.leadStatus = .interested
        existing.followUpDate = oldFollowUpDate
        existing.latitude = 43.5597
        existing.longitude = -79.7072
        try context.save()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lead-import-terminal-status-test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        let csv = """
        ID,Name,Status
        \(id.uuidString),Original,Sold
        """
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let result = try LeadCSVService.importLeads(from: url, into: context)
        #expect(result.created == 0)
        #expect(result.updated == 1)
        #expect(result.skipped == 0)

        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        let lead = try #require(try context.fetch(request).first)
        #expect(lead.leadStatus == .converted)
        #expect(lead.followUpDate == nil)
    }

    @MainActor
    @Test func csvImportNormalizesStatusAliases() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lead-import-status-test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        let csv = """
        Name,Status,Latitude,Longitude
        Sold Lead,Sold,43.5597,-79.7072
        Closed Lead,Closed,43.5598,-79.7073
        No Interest Lead,No Interest,43.5599,-79.7074
        Not Home Lead,Not Home,43.5600,-79.7075
        Booked Lead,Booked,43.5601,-79.7076
        Unknown Lead,Mystery,43.5602,-79.7077
        """
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let result = try LeadCSVService.importLeads(from: url, into: context)
        #expect(result.created == 6)
        #expect(result.skipped == 0)

        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Lead.name, ascending: true)]
        let statusesByName = Dictionary(uniqueKeysWithValues: try context.fetch(request).map { ($0.name ?? "", $0.status ?? "") })

        #expect(statusesByName["Sold Lead"] == Lead.Status.converted.rawValue)
        #expect(statusesByName["Closed Lead"] == Lead.Status.converted.rawValue)
        #expect(statusesByName["No Interest Lead"] == Lead.Status.notInterested.rawValue)
        #expect(statusesByName["Not Home Lead"] == Lead.Status.notHome.rawValue)
        #expect(statusesByName["Booked Lead"] == Lead.Status.interested.rawValue)
        #expect(statusesByName["Unknown Lead"] == Lead.Status.notContacted.rawValue)
    }

    @MainActor
    @Test func csvImportAcceptsISO8601DatesWithoutFractionalSeconds() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lead-import-date-test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        let createdDate = "2026-06-26T10:30:00Z"
        let followUpDate = "2026-06-27T14:45:00Z"
        let lastContactDate = "2026-06-25T18:15:00Z"
        let csv = """
        Name,Latitude,Longitude,CreatedDate,FollowUpDate,LastContactDate
        Date Lead,43.5597,-79.7072,\(createdDate),\(followUpDate),\(lastContactDate)
        """
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let result = try LeadCSVService.importLeads(from: url, into: context)
        #expect(result.created == 1)
        #expect(result.skipped == 0)

        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        let lead = try #require(try context.fetch(request).first)
        #expect(lead.createdDate == ISO8601DateFormatter().date(from: createdDate))
        #expect(lead.followUpDate == ISO8601DateFormatter().date(from: followUpDate))
        #expect(lead.lastContactDate == ISO8601DateFormatter().date(from: lastContactDate))
    }

    @Test func appointmentLocalStoreDistinguishesMissingValidAndCorruptData() async throws {
        let suiteName = "AppointmentLocalStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "appointments_test"
        #expect(try AppointmentLocalStore.loadAppointments(from: defaults, key: key) == nil)

        let appointment = Appointment(
            title: "Window Cleaning - Test",
            notes: "Test appointment",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            location: "123 Test St",
            leadId: UUID(),
            calendarEventId: nil,
            appointmentType: .consultation,
            customAppointmentTypeId: nil,
            status: .scheduled
        )
        defaults.set(try JSONEncoder().encode([appointment]), forKey: key)

        let loaded = try #require(try AppointmentLocalStore.loadAppointments(from: defaults, key: key))
        #expect(loaded.count == 1)
        #expect(loaded.first?.title == "Window Cleaning - Test")
        #expect(loaded.first?.location == "123 Test St")

        defaults.set(Data("not-json".utf8), forKey: key)
        #expect(throws: Error.self) {
            try AppointmentLocalStore.loadAppointments(from: defaults, key: key)
        }
    }

    @Test func appointmentDeletionTombstonesPersistDeletedIds() throws {
        let suiteName = "AppointmentDeletionTombstoneTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "deleted_appointments_test"
        let firstId = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let secondId = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))

        AppointmentDeletionTombstoneStore.markDeleted([firstId], in: defaults, key: key)
        AppointmentDeletionTombstoneStore.markDeleted([firstId, secondId], in: defaults, key: key)

        let loaded = AppointmentDeletionTombstoneStore.loadDeletedIds(from: defaults, key: key)
        #expect(loaded == [firstId, secondId])
    }

    @Test func appointmentCloudMergePolicySkipsLocallyDeletedAppointments() throws {
        let deletedId = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let activeId = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))

        var deletedAppointment = Appointment(
            title: "Deleted",
            notes: "",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            location: "123 Deleted St",
            leadId: nil,
            calendarEventId: nil,
            appointmentType: .consultation,
            customAppointmentTypeId: nil,
            status: .scheduled
        )
        deletedAppointment.id = deletedId

        var activeAppointment = deletedAppointment
        activeAppointment.id = activeId
        activeAppointment.title = "Active"

        let filtered = AppointmentCloudMergePolicy.excludingDeletedAppointments(
            [deletedAppointment, activeAppointment],
            deletedIds: [deletedId]
        )

        #expect(filtered.map(\.id) == [activeId])
    }

    @MainActor
    @Test func launchMaintenanceDoesNotReactivateCancelledAppointments() throws {
        let manager = AppointmentManager.shared
        let originalAppointments = manager.appointments
        defer {
            manager.appointments = originalAppointments
        }

        let cancelledId = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let scheduledId = try #require(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))

        var cancelledAppointment = Appointment(
            title: "Cancelled appointment",
            notes: "",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            location: "123 Cancelled St",
            leadId: nil,
            calendarEventId: nil,
            appointmentType: .consultation,
            customAppointmentTypeId: nil,
            status: .cancelled
        )
        cancelledAppointment.id = cancelledId

        var scheduledAppointment = cancelledAppointment
        scheduledAppointment.id = scheduledId
        scheduledAppointment.title = "Scheduled appointment"
        scheduledAppointment.status = .scheduled

        manager.appointments = [cancelledAppointment, scheduledAppointment]
        manager.fixCancelledAppointments()

        #expect(manager.appointments.first(where: { $0.id == cancelledId })?.status == .cancelled)
        #expect(manager.appointments.first(where: { $0.id == scheduledId })?.status == .scheduled)
    }

    @Test func appointmentCloudSyncPolicyRoutesICloudWithoutFirebase() {
        #expect(
            AppointmentCloudSyncPolicy.firestoreUserId(
                provider: .icloud,
                isAuthenticated: true,
                currentUserId: "firebase-user"
            ) == nil
        )
        #expect(
            AppointmentCloudSyncPolicy.cloudKitBackupUserId(
                provider: .icloud,
                firebaseUserId: nil
            ) == AppointmentCloudSyncPolicy.privateCloudKitUserId
        )
        #expect(
            AppointmentCloudSyncPolicy.firestoreUserId(
                provider: .firebase,
                isAuthenticated: true,
                currentUserId: "firebase-user"
            ) == "firebase-user"
        )
        #expect(
            AppointmentCloudSyncPolicy.cloudKitBackupUserId(
                provider: .firebase,
                firebaseUserId: "firebase-user"
            ) == "firebase-user"
        )
        #expect(
            AppointmentCloudSyncPolicy.firestoreUserId(
                provider: .firebase,
                isAuthenticated: false,
                currentUserId: "firebase-user"
            ) == nil
        )
        #expect(
            AppointmentCloudSyncPolicy.cloudKitBackupUserId(
                provider: .off,
                firebaseUserId: "firebase-user"
            ) == nil
        )
    }

    @Test func notificationSettingsLocalStoreDistinguishesMissingValidAndCorruptData() async throws {
        let suiteName = "NotificationSettingsLocalStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "notification_settings_test"
        #expect(try NotificationSettingsLocalStore.loadSettings(from: defaults, key: key) == nil)

        var settings = NotificationSettings()
        settings.playSound = false
        settings.followUpReminders.isEnabled = false
        settings.appointmentReminders.reminderTimes = [.fiveMinutesBefore, .oneDayBefore]

        try NotificationSettingsLocalStore.save(settings, to: defaults, key: key)
        let loaded = try #require(try NotificationSettingsLocalStore.loadSettings(from: defaults, key: key))
        #expect(loaded.playSound == false)
        #expect(loaded.followUpReminders.isEnabled == false)
        #expect(loaded.appointmentReminders.reminderTimes == [.fiveMinutesBefore, .oneDayBefore])

        defaults.set(Data("not-json".utf8), forKey: key)
        #expect(throws: Error.self) {
            try NotificationSettingsLocalStore.loadSettings(from: defaults, key: key)
        }
    }

    @Test func appointmentReminderPolicyOnlySchedulesActionableAppointments() {
        #expect(NotificationService.shouldScheduleAppointmentNotifications(for: .scheduled))
        #expect(NotificationService.shouldScheduleAppointmentNotifications(for: .confirmed))
        #expect(!NotificationService.shouldScheduleAppointmentNotifications(for: .completed))
        #expect(!NotificationService.shouldScheduleAppointmentNotifications(for: .cancelled))
        #expect(!NotificationService.shouldScheduleAppointmentNotifications(for: .rescheduled))
    }

    @Test func notificationMarkCompleteActionOnlyChangesAppointmentStatus() {
        let appointment = Appointment(
            title: "Window Cleaning - Test",
            notes: "Test appointment",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            location: "123 Test St",
            leadId: UUID(),
            calendarEventId: "calendar-event-1",
            appointmentType: .consultation,
            customAppointmentTypeId: nil,
            status: .scheduled
        )

        let completed = NotificationService.appointmentMarkedComplete(appointment)

        #expect(completed.status == .completed)
        #expect(completed.id == appointment.id)
        #expect(completed.title == appointment.title)
        #expect(completed.startDate == appointment.startDate)
        #expect(completed.endDate == appointment.endDate)
        #expect(completed.location == appointment.location)
        #expect(completed.calendarEventId == "calendar-event-1")
    }

    @Test func appointmentCalendarEventPolicyClearsInactiveAppointmentLinks() {
        let appointment = Appointment(
            title: "Window Cleaning - Test",
            notes: "Test appointment",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            location: "123 Test St",
            leadId: UUID(),
            calendarEventId: "calendar-event-1",
            appointmentType: .consultation,
            customAppointmentTypeId: nil,
            status: .scheduled
        )

        let scheduledPolicy = appointment.applyingCalendarEventStatusPolicy()
        #expect(scheduledPolicy.appointment.calendarEventId == "calendar-event-1")
        #expect(scheduledPolicy.calendarEventIdToDelete == nil)

        var cancelled = appointment
        cancelled.status = .cancelled
        let cancelledPolicy = cancelled.applyingCalendarEventStatusPolicy()
        #expect(cancelledPolicy.appointment.calendarEventId == nil)
        #expect(cancelledPolicy.calendarEventIdToDelete == "calendar-event-1")

        var rescheduled = appointment
        rescheduled.status = .rescheduled
        let rescheduledPolicy = rescheduled.applyingCalendarEventStatusPolicy()
        #expect(rescheduledPolicy.appointment.calendarEventId == nil)
        #expect(rescheduledPolicy.calendarEventIdToDelete == "calendar-event-1")
    }

    @Test func followUpReminderPolicySkipsTerminalLeadStatuses() {
        let followUpDate = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(NotificationService.shouldScheduleFollowUpNotification(status: .notContacted, followUpDate: followUpDate))
        #expect(NotificationService.shouldScheduleFollowUpNotification(status: .notHome, followUpDate: followUpDate))
        #expect(NotificationService.shouldScheduleFollowUpNotification(status: .interested, followUpDate: followUpDate))
        #expect(!NotificationService.shouldScheduleFollowUpNotification(status: .converted, followUpDate: followUpDate))
        #expect(!NotificationService.shouldScheduleFollowUpNotification(status: .notInterested, followUpDate: followUpDate))
        #expect(!NotificationService.shouldScheduleFollowUpNotification(status: .notHome, followUpDate: nil))
    }

    @Test func leadStatusFollowUpPolicyClearsTerminalProposedDates() {
        let followUpDate = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(Lead.Status.notContacted.resolvedFollowUpDate(followUpDate) == followUpDate)
        #expect(Lead.Status.notHome.resolvedFollowUpDate(followUpDate) == followUpDate)
        #expect(Lead.Status.interested.resolvedFollowUpDate(followUpDate) == followUpDate)
        #expect(Lead.Status.converted.resolvedFollowUpDate(followUpDate) == nil)
        #expect(Lead.Status.notInterested.resolvedFollowUpDate(followUpDate) == nil)
    }

    @MainActor
    @Test func applyingTerminalLeadStatusClearsExistingFollowUpDate() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let followUpDate = Date(timeIntervalSince1970: 1_800_000_000)
        let lead = Lead.create(in: context)

        lead.followUpDate = followUpDate
        lead.applyLeadStatus(.interested, autoSave: false)
        #expect(lead.followUpDate == followUpDate)

        lead.applyLeadStatus(.converted, autoSave: false)
        #expect(lead.followUpDate == nil)

        lead.followUpDate = followUpDate
        lead.applyLeadStatus(
            .notInterested,
            followUpDate: followUpDate,
            shouldReplaceFollowUpDate: true,
            autoSave: false
        )
        #expect(lead.followUpDate == nil)
    }

    @Test func followUpReminderCancelListIncludesLegacyDuplicateIdentifier() throws {
        let leadId = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))

        #expect(
            NotificationService.followUpNotificationIdentifiersToCancel(for: leadId) == [
                "followup_AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            ]
        )
    }

    @Test func leadDataMutationRefreshesNotificationsOnlyWhenLeadsChanged() {
        #expect(
            NotificationService.shouldRefreshNotificationsAfterLeadDataMutation(
                inserted: 1,
                updated: 0
            )
        )
        #expect(
            NotificationService.shouldRefreshNotificationsAfterLeadDataMutation(
                inserted: 0,
                updated: 2
            )
        )
        #expect(
            !NotificationService.shouldRefreshNotificationsAfterLeadDataMutation(
                inserted: 0,
                updated: 0
            )
        )
    }

    @Test func followUpRestoreRefreshesNotificationsOnlyWhenAnyReminderWasRecovered() {
        #expect(NotificationService.shouldRefreshNotificationsAfterFollowUpRestore(restoredCount: 1))
        #expect(NotificationService.shouldRefreshNotificationsAfterFollowUpRestore(restoredCount: 3))
        #expect(!NotificationService.shouldRefreshNotificationsAfterFollowUpRestore(restoredCount: 0))
    }

    @Test func checkInOutcomePolicyClearsNextFollowUpForTerminalResults() {
        let nextFollowUp = Date(timeIntervalSince1970: 1_800_086_400)

        #expect(
            FollowUpCheckIn.resolvedLeadStatus(
                after: .converted,
                currentStatus: .interested
            ) == .converted
        )
        #expect(
            FollowUpCheckIn.effectiveScheduledNextFollowUp(
                nextFollowUp,
                resultingStatus: .converted
            ) == nil
        )
        #expect(
            FollowUpCheckIn.resolvedLeadStatus(
                after: .notInterested,
                currentStatus: .converted
            ) == .notInterested
        )
        #expect(
            FollowUpCheckIn.effectiveScheduledNextFollowUp(
                nextFollowUp,
                resultingStatus: .notInterested
            ) == nil
        )
        #expect(
            FollowUpCheckIn.resolvedLeadStatus(
                after: .interested,
                currentStatus: .converted
            ) == .converted
        )
        #expect(
            FollowUpCheckIn.resolvedLeadStatus(
                after: .interested,
                currentStatus: .notContacted
            ) == .interested
        )
        #expect(
            FollowUpCheckIn.effectiveScheduledNextFollowUp(
                nextFollowUp,
                resultingStatus: .interested
            ) == nextFollowUp
        )
    }

    @MainActor
    @Test func activeFollowUpPredicateExcludesTerminalLeadsAndIncludesOpenStatuses() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let followUpDate = Date(timeIntervalSince1970: 1_800_000_000)

        func makeLead(_ name: String, status: Lead.Status?, followUpDate: Date?) {
            let lead = Lead.create(in: context)
            lead.name = name
            lead.status = status?.rawValue
            lead.followUpDate = followUpDate
        }

        makeLead("Not Contacted", status: .notContacted, followUpDate: followUpDate)
        makeLead("Not Home", status: .notHome, followUpDate: followUpDate)
        makeLead("Sold", status: .converted, followUpDate: followUpDate)
        makeLead("No Interest", status: .notInterested, followUpDate: followUpDate)
        makeLead("No Date", status: .interested, followUpDate: nil)

        try context.save()

        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        request.predicate = Lead.Status.activeFollowUpPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Lead.name, ascending: true)]

        let names = try context.fetch(request).compactMap(\.name)
        #expect(names == ["Not Contacted", "Not Home"])
    }

    @MainActor
    @Test func mapWorkflowFollowUpDueIgnoresTerminalLeadStatuses() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        func makeLead(status: Lead.Status, followUpOffset: TimeInterval?) -> Lead {
            let lead = Lead.create(in: context)
            lead.name = status.displayName
            lead.status = status.rawValue
            lead.followUpDate = followUpOffset.map { now.addingTimeInterval($0) }
            return lead
        }

        let notHomeSoon = makeLead(status: .notHome, followUpOffset: 60 * 60)
        let interestedPastDue = makeLead(status: .interested, followUpOffset: -60)
        let soldPastDue = makeLead(status: .converted, followUpOffset: -60)
        let noInterestPastDue = makeLead(status: .notInterested, followUpOffset: -60)
        let tooFarOut = makeLead(status: .notContacted, followUpOffset: 13 * 60 * 60)
        let noFollowUpDate = makeLead(status: .notContacted, followUpOffset: nil)

        #expect(LeadMapWorkflowPolicy.isFollowUpDue(notHomeSoon, now: now))
        #expect(LeadMapWorkflowPolicy.isFollowUpDue(interestedPastDue, now: now))
        #expect(!LeadMapWorkflowPolicy.isFollowUpDue(soldPastDue, now: now))
        #expect(!LeadMapWorkflowPolicy.isFollowUpDue(noInterestPastDue, now: now))
        #expect(!LeadMapWorkflowPolicy.isFollowUpDue(tooFarOut, now: now))
        #expect(!LeadMapWorkflowPolicy.isFollowUpDue(noFollowUpDate, now: now))
    }

    @MainActor
    @Test func mapWorkflowFiltersNormalizeLegacyStatusValues() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        func makeLead(rawStatus: String, priority: Int16 = 0, value: Double = 0, followUpOffset: TimeInterval? = nil) -> Lead {
            let lead = Lead.create(in: context)
            lead.name = rawStatus
            lead.status = rawStatus
            lead.priority = priority
            lead.estimatedValue = value
            lead.followUpDate = followUpOffset.map { now.addingTimeInterval($0) }
            return lead
        }

        let legacySold = makeLead(rawStatus: "sold", priority: 1, value: 1_400, followUpOffset: -60)
        let legacyClosed = makeLead(rawStatus: "Closed", priority: 1, value: 1_200, followUpOffset: -60)
        let legacyWon = makeLead(rawStatus: "won")
        let dueLead = makeLead(rawStatus: Lead.Status.notHome.rawValue, followUpOffset: -60)
        let hotLead = makeLead(rawStatus: Lead.Status.interested.rawValue)

        #expect(MapWorkflowMode.sold.includes(legacySold, now: now))
        #expect(MapWorkflowMode.sold.includes(legacyClosed, now: now))
        #expect(MapWorkflowMode.sold.includes(legacyWon, now: now))
        #expect(!MapWorkflowMode.hot.includes(legacySold, now: now))
        #expect(!MapWorkflowMode.due.includes(legacySold, now: now))
        #expect(MapWorkflowMode.due.includes(dueLead, now: now))
        #expect(MapWorkflowMode.hot.includes(hotLead, now: now))
    }

    @MainActor
    @Test func mapLeadVisibilityPolicyKeepsUnboundedFilteringAvailable() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        var leads: [Lead] = []
        for index in 0..<1_750 {
            let lead = Lead.create(in: context)
            lead.name = "Open \(index)"
            lead.status = Lead.Status.notContacted.rawValue
            lead.latitude = 43.55 + (Double(index % 40) * 0.0001)
            lead.longitude = -79.70 - (Double(index % 40) * 0.0001)
            lead.updatedDate = now.addingTimeInterval(TimeInterval(-index))
            leads.append(lead)
        }

        let soldLead = Lead.create(in: context)
        soldLead.name = "Sold"
        soldLead.status = Lead.Status.converted.rawValue
        leads.append(soldLead)

        let rejectedLead = Lead.create(in: context)
        rejectedLead.name = "Rejected"
        rejectedLead.status = Lead.Status.notInterested.rawValue
        leads.append(rejectedLead)

        #expect(MapLeadVisibilityPolicy.visibleLeads(from: leads, mode: .all, now: now).count == leads.count)
        #expect(MapLeadVisibilityPolicy.visibleLeads(from: leads, mode: .next, now: now).count == 1_750)
    }

    @MainActor
    @Test func mapLeadVisibilityPolicyBoundsRenderedViewportAndKeepsPriorityOrder() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.55, longitude: -79.70),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )

        var leads: [Lead] = []
        for index in 0..<120 {
            let lead = Lead.create(in: context)
            lead.name = "Open \(index)"
            lead.status = Lead.Status.notContacted.rawValue
            lead.latitude = 43.55 + (Double(index % 20) * 0.0002)
            lead.longitude = -79.70 - (Double(index % 20) * 0.0002)
            lead.updatedDate = now.addingTimeInterval(TimeInterval(-index))
            leads.append(lead)
        }

        let soldLead = Lead.create(in: context)
        soldLead.name = "Sold"
        soldLead.status = Lead.Status.converted.rawValue
        soldLead.latitude = 43.5501
        soldLead.longitude = -79.7001
        soldLead.updatedDate = now.addingTimeInterval(-500)
        leads.append(soldLead)

        let interestedLead = Lead.create(in: context)
        interestedLead.name = "Interested"
        interestedLead.status = Lead.Status.interested.rawValue
        interestedLead.latitude = 43.5502
        interestedLead.longitude = -79.7002
        interestedLead.updatedDate = now.addingTimeInterval(-400)
        leads.append(interestedLead)

        let rendered = MapLeadVisibilityPolicy.visibleLeads(
            from: leads,
            mode: .all,
            region: region,
            fallbackCenter: region.center,
            maxRenderedLeads: 40,
            now: now
        )

        #expect(rendered.count == 40)
        #expect(rendered.prefix(2).map { $0.name ?? "" } == ["Sold", "Interested"])
    }

    @MainActor
    @Test func mapLeadVisibilityPolicyOpeningBudgetKeepsFirstPaintSmallAndPrioritized() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.55, longitude: -79.70),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )

        var leads: [Lead] = []
        for index in 0..<420 {
            let lead = Lead.create(in: context)
            lead.name = "Open \(index)"
            lead.status = Lead.Status.notContacted.rawValue
            lead.latitude = 43.55 + (Double(index % 30) * 0.0002)
            lead.longitude = -79.70 - (Double(index % 30) * 0.0002)
            lead.updatedDate = now.addingTimeInterval(TimeInterval(-index))
            leads.append(lead)
        }

        let soldLead = Lead.create(in: context)
        soldLead.name = "Sold"
        soldLead.status = Lead.Status.converted.rawValue
        soldLead.latitude = 43.5501
        soldLead.longitude = -79.7001
        soldLead.updatedDate = now.addingTimeInterval(-500)
        leads.append(soldLead)

        let interestedLead = Lead.create(in: context)
        interestedLead.name = "Interested"
        interestedLead.status = Lead.Status.interested.rawValue
        interestedLead.latitude = 43.5502
        interestedLead.longitude = -79.7002
        interestedLead.updatedDate = now.addingTimeInterval(-400)
        leads.append(interestedLead)

        let rendered = MapLeadVisibilityPolicy.visibleLeads(
            from: leads,
            mode: .all,
            region: region,
            fallbackCenter: region.center,
            maxRenderedLeads: MapLeadVisibilityPolicy.openingRenderedLeadBudget,
            now: now
        )

        #expect(rendered.count == MapLeadVisibilityPolicy.openingRenderedLeadBudget)
        #expect(rendered.prefix(2).map { $0.name ?? "" } == ["Sold", "Interested"])
    }

    @MainActor
    @Test func mapLeadRenderSelectionKeepsSmallSetsCompleteAndCountsAllMatches() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.55, longitude: -79.70),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        func makeLead(_ name: String, status: Lead.Status, latitude: Double, longitude: Double) -> Lead {
            let lead = Lead.create(in: context)
            lead.name = name
            lead.status = status.rawValue
            lead.latitude = latitude
            lead.longitude = longitude
            lead.updatedDate = now
            return lead
        }

        let viewportLead = makeLead("Viewport", status: .notContacted, latitude: 43.55, longitude: -79.70)
        let outsideLead = makeLead("Outside", status: .notContacted, latitude: 43.62, longitude: -79.78)
        let soldOutsideLead = makeLead("Sold Outside", status: .converted, latitude: 43.63, longitude: -79.79)
        let interestedOutsideLead = makeLead("Interested Outside", status: .interested, latitude: 43.64, longitude: -79.80)
        let invalidCoordinateLead = makeLead("Invalid", status: .notContacted, latitude: 0, longitude: 0)

        let selection = MapLeadVisibilityPolicy.renderedLeadSelection(
            from: [viewportLead, outsideLead, soldOutsideLead, interestedOutsideLead, invalidCoordinateLead],
            mode: .all,
            region: region,
            fallbackCenter: region.center,
            maxRenderedLeads: 10,
            now: now
        )

        #expect(selection.matchingLeadCount == 5)
        #expect(Set(selection.renderedLeads.compactMap(\.name)) == ["Viewport", "Outside", "Sold Outside", "Interested Outside"])
    }

    @MainActor
    @Test func mapLeadVisibilityPolicySortsSoldThenInterestedBeforeOtherLeads() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        func makeLead(_ name: String, status: Lead.Status, updatedOffset: TimeInterval, priority: Int16 = 0) -> Lead {
            let lead = Lead.create(in: context)
            lead.name = name
            lead.status = status.rawValue
            lead.priority = priority
            lead.updatedDate = now.addingTimeInterval(updatedOffset)
            return lead
        }

        let priorityLead = makeLead("Priority", status: .notContacted, updatedOffset: 120, priority: 3)
        let coldLead = makeLead("Cold", status: .notContacted, updatedOffset: 300)
        let interestedLead = makeLead("Interested", status: .interested, updatedOffset: 60)
        let soldLead = makeLead("Sold", status: .converted, updatedOffset: -300)

        let visible = MapLeadVisibilityPolicy.visibleLeads(
            from: [priorityLead, coldLead, interestedLead, soldLead],
            mode: .all,
            now: now
        )

        #expect(visible.map(\.name) == ["Sold", "Interested", "Priority", "Cold"])
    }

    @Test func quickLeadAddressPolicyRejectsCoordinateFallbackAddresses() {
        #expect(MapQuickLeadAddressPolicy.acceptedAddress("Dropped pin at 43.55970, -79.70720", source: .coordinateFallback) == nil)
        #expect(MapQuickLeadAddressPolicy.acceptedAddress("  ", source: .streetAddress) == nil)
        #expect(MapQuickLeadAddressPolicy.acceptedAddress("Dropped pin at 43.55970, -79.70720", source: .streetAddress) == nil)
        #expect(MapQuickLeadAddressPolicy.acceptedAddress("Near International Location (Lat: 43.5597, Lon: -79.7072)", source: .streetAddress) == nil)
        #expect(MapQuickLeadAddressPolicy.acceptedAddress(" 4908 Forest Hill Dr, Mississauga, ON ", source: .streetAddress) == "4908 Forest Hill Dr, Mississauga, ON")
        #expect(MapQuickLeadAddressPolicy.acceptedAddress("4908 Forest Hill Dr, Mississauga, ON", source: .mapSearchAddress) == "4908 Forest Hill Dr, Mississauga, ON")
    }

    @Test func mapAddressResolutionUsesCandidateCoordinateForResolvedStreetAddress() {
        let pressedCoordinate = CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200)
        let houseCoordinate = CLLocationCoordinate2D(latitude: 43.559812, longitude: -79.707046)

        let resolvedStreetCoordinate = MapAddressResolutionPolicy.resolvedCoordinate(
            pressedCoordinate: pressedCoordinate,
            candidateCoordinate: houseCoordinate,
            source: .streetAddress
        )
        #expect(resolvedStreetCoordinate.latitude == houseCoordinate.latitude)
        #expect(resolvedStreetCoordinate.longitude == houseCoordinate.longitude)

        let fallbackCoordinate = MapAddressResolutionPolicy.resolvedCoordinate(
            pressedCoordinate: pressedCoordinate,
            candidateCoordinate: houseCoordinate,
            source: .coordinateFallback
        )
        #expect(fallbackCoordinate.latitude == pressedCoordinate.latitude)
        #expect(fallbackCoordinate.longitude == pressedCoordinate.longitude)
    }

    @Test func longPressLeadSeedPreservesPressedCoordinateAndConfirmedAddress() {
        let pressedCoordinate = CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200)

        let seed = MapLongPressLeadSeedPolicy.seed(
            pressedCoordinate: pressedCoordinate,
            confirmedAddress: " 4908 Forest Hill Dr, Mississauga, ON "
        )

        #expect(seed.coordinate.latitude == pressedCoordinate.latitude)
        #expect(seed.coordinate.longitude == pressedCoordinate.longitude)
        #expect(seed.address == "4908 Forest Hill Dr, Mississauga, ON")
    }

    @Test func addLeadAddressPolicyRejectsCoordinateFallbackAddresses() {
        #expect(AddLeadAddressPolicy.cleanedAddress("Dropped pin at 43.55970, -79.70720") == nil)
        #expect(AddLeadAddressPolicy.cleanedAddress("Near International Location (Lat: 43.5597, Lon: -79.7072)") == nil)
        #expect(AddLeadAddressPolicy.cleanedAddress("Near United States (Lat: 37.7858, Lon: -122.4064)") == nil)
        #expect(AddLeadAddressPolicy.cleanedAddress("Lat: 43.5597, Lon: -79.7072") == nil)
        #expect(AddLeadAddressPolicy.cleanedAddress("  ") == nil)
        #expect(AddLeadAddressPolicy.cleanedAddress(nil) == nil)
        #expect(AddLeadAddressPolicy.cleanedAddress(" 4908 Forest Hill Dr, Mississauga, ON ") == "4908 Forest Hill Dr, Mississauga, ON")

        let seed = AddLeadLocationSeed(
            coordinate: CLLocationCoordinate2D(latitude: 43.55970, longitude: -79.70720),
            address: "Dropped pin at 43.55970, -79.70720"
        )
        #expect(seed.address == nil)
    }

    @Test func addLeadSystemAddressPolicyDoesNotOverwriteConfirmedOrDraftAddress() {
        #expect(AddLeadAddressPolicy.shouldApplySystemAddress(
            "4908 Forest Hill Dr, Mississauga, ON",
            currentAddress: "",
            hasManuallyEditedAddress: false
        ))
        #expect(!AddLeadAddressPolicy.shouldApplySystemAddress(
            "4908 Forest Hill Dr, Mississauga, ON",
            currentAddress: "4910 Forest Hill Dr, Mississauga, ON",
            hasManuallyEditedAddress: false
        ))
        #expect(!AddLeadAddressPolicy.shouldApplySystemAddress(
            "4908 Forest Hill Dr, Mississauga, ON",
            currentAddress: "",
            hasManuallyEditedAddress: true
        ))
        #expect(!AddLeadAddressPolicy.shouldApplySystemAddress(
            "Dropped pin at 43.55970, -79.70720",
            currentAddress: "",
            hasManuallyEditedAddress: false
        ))
        #expect(AddLeadAddressPolicy.shouldApplySystemAddress(
            "4908 Forest Hill Dr, Mississauga, ON",
            currentAddress: "4910 Forest Hill Dr, Mississauga, ON",
            hasManuallyEditedAddress: false,
            force: true
        ))
    }

    @Test func mapQuickActionLeadPolicyRequiresResolvedAddress() {
        #expect(!MapQuickActionLeadPolicy.canCreateLead(address: ""))
        #expect(!MapQuickActionLeadPolicy.canCreateLead(address: "Dropped pin at 43.55970, -79.70720"))
        #expect(MapQuickActionLeadPolicy.canCreateLead(address: "4908 Forest Hill Dr, Mississauga, ON"))
        #expect(MapQuickActionLeadPolicy.usableAddress(" 4908 Forest Hill Dr, Mississauga, ON ") == "4908 Forest Hill Dr, Mississauga, ON")
    }

    @Test func quickActionLeadSeedUsesResolvedCoordinateAndRejectsFallbackAddresses() {
        let pressedCoordinate = CLLocationCoordinate2D(latitude: 43.559700, longitude: -79.707200)
        let resolvedHouseCoordinate = CLLocationCoordinate2D(latitude: 43.559812, longitude: -79.707046)

        let resolvedSeed = MapQuickActionLeadSeedPolicy.seed(
            resolvedCoordinate: resolvedHouseCoordinate,
            resolvedAddress: "4908 Forest Hill Dr, Mississauga, ON",
            source: .streetAddress
        )
        #expect(resolvedSeed.coordinate.latitude == resolvedHouseCoordinate.latitude)
        #expect(resolvedSeed.coordinate.longitude == resolvedHouseCoordinate.longitude)
        #expect(resolvedSeed.address == "4908 Forest Hill Dr, Mississauga, ON")

        let fallbackSeed = MapQuickActionLeadSeedPolicy.seed(
            resolvedCoordinate: pressedCoordinate,
            resolvedAddress: "Dropped pin at 43.55970, -79.70720",
            source: .coordinateFallback
        )
        #expect(fallbackSeed.coordinate.latitude == pressedCoordinate.latitude)
        #expect(fallbackSeed.coordinate.longitude == pressedCoordinate.longitude)
        #expect(fallbackSeed.address == nil)
    }

    @Test func quickLeadUndoDeletionPlanPreventsCloudResurrectionWhenUndoingSyncedLead() throws {
        let leadId = try #require(UUID(uuidString: "99999999-9999-9999-9999-999999999999"))

        let firebasePlan = MapQuickLeadUndoPolicy.deletionPlan(
            leadId: leadId,
            provider: .firebase,
            isAuthenticated: true
        )
        #expect(firebasePlan.localDeletedId == leadId)
        #expect(firebasePlan.cloudLeadId == leadId.uuidString)

        let unauthenticatedFirebasePlan = MapQuickLeadUndoPolicy.deletionPlan(
            leadId: leadId,
            provider: .firebase,
            isAuthenticated: false
        )
        #expect(unauthenticatedFirebasePlan.localDeletedId == leadId)
        #expect(unauthenticatedFirebasePlan.cloudLeadId == nil)

        let iCloudPlan = MapQuickLeadUndoPolicy.deletionPlan(
            leadId: leadId,
            provider: .icloud,
            isAuthenticated: false
        )
        #expect(iCloudPlan.localDeletedId == leadId)
        #expect(iCloudPlan.cloudLeadId == leadId.uuidString)

        let missingIdPlan = MapQuickLeadUndoPolicy.deletionPlan(
            leadId: nil,
            provider: .icloud,
            isAuthenticated: true
        )
        #expect(missingIdPlan.localDeletedId == nil)
        #expect(missingIdPlan.cloudLeadId == nil)
    }

    @MainActor
    @Test func mapWorkflowHotLeadsExcludeTerminalStatuses() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        func makeLead(status: Lead.Status, priority: Int16 = 0, value: Double = 0, followUpOffset: TimeInterval? = nil) -> Lead {
            let lead = Lead.create(in: context)
            lead.name = status.displayName
            lead.status = status.rawValue
            lead.priority = priority
            lead.estimatedValue = value
            lead.followUpDate = followUpOffset.map { now.addingTimeInterval($0) }
            return lead
        }

        let priorityLead = makeLead(status: .notContacted, priority: 1)
        let interestedLead = makeLead(status: .interested)
        let dueLead = makeLead(status: .notHome, followUpOffset: -60)
        let valuableLead = makeLead(status: .notContacted, value: 900)
        let soldPriorityLead = makeLead(status: .converted, priority: 1, value: 1_500, followUpOffset: -60)
        let rejectedValuableLead = makeLead(status: .notInterested, priority: 1, value: 2_000, followUpOffset: -60)

        #expect(LeadMapWorkflowPolicy.isHotLead(priorityLead, now: now))
        #expect(LeadMapWorkflowPolicy.isHotLead(interestedLead, now: now))
        #expect(LeadMapWorkflowPolicy.isHotLead(dueLead, now: now))
        #expect(LeadMapWorkflowPolicy.isHotLead(valuableLead, now: now))
        #expect(!LeadMapWorkflowPolicy.isHotLead(soldPriorityLead, now: now))
        #expect(!LeadMapWorkflowPolicy.isHotLead(rejectedValuableLead, now: now))
    }

    @MainActor
    @Test func leadClusterSummaryDoesNotMarkTerminalLeadsHotOrUrgent() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        func makeLead(status: Lead.Status) -> Lead {
            let lead = Lead.create(in: context)
            lead.name = status.displayName
            lead.status = status.rawValue
            lead.priority = 1
            lead.estimatedValue = 2_000
            lead.followUpDate = now.addingTimeInterval(-60)
            return lead
        }

        let soldLead = makeLead(status: .converted)
        let rejectedLead = makeLead(status: .notInterested)
        let summary = LeadClusterSummary(leads: [soldLead, rejectedLead], now: now)

        #expect(summary.hotLeadCount == 0)
        #expect(summary.dueFollowUpCount == 0)
        #expect(!summary.isUrgent)
        #expect(!LeadClusterSummary.isUrgent(soldLead))
        #expect(!LeadClusterSummary.isUrgent(rejectedLead))
    }

    @MainActor
    @Test func leadClusterSummarySortsSoldLeadsBeforeActiveWork() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        func makeLead(_ name: String, status: Lead.Status, updatedOffset: TimeInterval, priority: Int16 = 0) -> Lead {
            let lead = Lead.create(in: context)
            lead.name = name
            lead.status = status.rawValue
            lead.priority = priority
            lead.updatedDate = now.addingTimeInterval(updatedOffset)
            return lead
        }

        let priorityLead = makeLead("Priority", status: .notContacted, updatedOffset: 20, priority: 3)
        let interestedLead = makeLead("Interested", status: .interested, updatedOffset: 30)
        let soldLead = makeLead("Sold", status: .converted, updatedOffset: -200)

        let sorted = LeadClusterSummary.sortedLeads([priorityLead, interestedLead, soldLead], now: now)

        #expect(sorted.first?.leadStatus == .converted)
        #expect(sorted.first?.name == "Sold")
        #expect(sorted.dropFirst().first?.leadStatus == .interested)
        #expect(sorted.dropFirst().first?.name == "Interested")
    }

    @MainActor
    @Test func leadClusterSummaryLabelsAndColorsSoldBeforeInterestedOrDue() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        func makeLead(_ name: String, status: Lead.Status, followUpOffset: TimeInterval? = nil) -> Lead {
            let lead = Lead.create(in: context)
            lead.name = name
            lead.status = status.rawValue
            lead.followUpDate = followUpOffset.map { now.addingTimeInterval($0) }
            return lead
        }

        let soldLead = makeLead("Sold", status: .converted)
        let interestedLead = makeLead("Interested", status: .interested, followUpOffset: -60)
        let dueLead = makeLead("Due", status: .notHome, followUpOffset: -60)

        let soldSummary = LeadClusterSummary(leads: [dueLead, interestedLead, soldLead], now: now)
        #expect(soldSummary.headline == "1 sold")
        #expect(soldSummary.uiColor.isEqual(UIColor.systemGreen))

        let interestedSummary = LeadClusterSummary(leads: [dueLead, interestedLead], now: now)
        #expect(interestedSummary.headline == "1 interested")
        #expect(interestedSummary.uiColor.isEqual(UIColor.systemOrange))
    }

    @MainActor
    @Test func soldLeadMarkersHaveHighestMapDisplayPriority() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext

        let soldLead = Lead.create(in: context)
        soldLead.status = Lead.Status.converted.rawValue

        let interestedLead = Lead.create(in: context)
        interestedLead.status = Lead.Status.interested.rawValue

        #expect(LeadMapAnnotationPriorityPolicy.displayPriority(for: soldLead) == .required)
        #expect(
            LeadMapAnnotationPriorityPolicy.displayPriority(for: soldLead).rawValue
            > LeadMapAnnotationPriorityPolicy.displayPriority(for: interestedLead).rawValue
        )
    }

    @MainActor
    @Test func interestedLeadMarkersHaveSecondMapDisplayPriority() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext

        let interestedLead = Lead.create(in: context)
        interestedLead.status = Lead.Status.interested.rawValue

        let priorityLead = Lead.create(in: context)
        priorityLead.status = Lead.Status.notContacted.rawValue
        priorityLead.priority = 3

        let interestedCluster = LeadClusterSummary(leads: [interestedLead])
        let priorityCluster = LeadClusterSummary(leads: [priorityLead])

        #expect(
            LeadMapAnnotationPriorityPolicy.displayPriority(for: interestedLead).rawValue
            > LeadMapAnnotationPriorityPolicy.displayPriority(for: priorityLead).rawValue
        )
        #expect(
            LeadMapAnnotationPriorityPolicy.clusterDisplayPriority(for: interestedCluster).rawValue
            > LeadMapAnnotationPriorityPolicy.clusterDisplayPriority(for: priorityCluster).rawValue
        )
    }

    @Test func leadClusterInteractionOpensAreaSheetBeforeExtremeZoom() {
        let route = LeadClusterInteractionPolicy.route(
            mapSpan: 0.035,
            coordinateSpread: 0.009,
            memberCount: 24,
            containsUrgentLead: false
        )

        #expect(route == .openSheet)
    }

    @Test func leadClusterDisplayPolicyExpandsPinsAtNeighborhoodZoom() {
        #expect(LeadClusterDisplayPolicy.mode(mapSpan: 0.04) == .expanded)
        #expect(LeadClusterDisplayPolicy.mode(mapSpan: 0.05) == .clustered)
        #expect(LeadClusterDisplayPolicy.clusteringIdentifier(for: .expanded) == nil)
    }

    @Test func calendarSettingsLocalStoreDistinguishesMissingValidAndCorruptData() async throws {
        let suiteName = "CalendarSettingsLocalStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "calendar_settings_test"
        #expect(try CalendarSettingsLocalStore.loadSettings(from: defaults, key: key) == nil)

        let settings = CalendarIntegrationSettings(
            isEnabled: false,
            selectedCalendarIdentifier: "work-calendar",
            alertOffsets: [.fiveMinutesBefore, .oneDayBefore]
        )

        try CalendarSettingsLocalStore.save(settings, to: defaults, key: key)
        let loaded = try #require(try CalendarSettingsLocalStore.loadSettings(from: defaults, key: key))
        #expect(loaded.isEnabled == false)
        #expect(loaded.selectedCalendarIdentifier == "work-calendar")
        #expect(loaded.alertOffsets == [.fiveMinutesBefore, .oneDayBefore])

        defaults.set(Data("not-json".utf8), forKey: key)
        #expect(throws: Error.self) {
            try CalendarSettingsLocalStore.loadSettings(from: defaults, key: key)
        }
    }

    @Test func themeColorLocalStoreHandlesGrayscaleRGBAndCorruptData() throws {
        let grayscale = try #require(ThemeColorLocalStore.snapshot(fromCGColorComponents: [0.35, 0.8]))
        #expect(grayscale == ThemeColorSnapshot(red: 0.35, green: 0.35, blue: 0.35, alpha: 0.8))

        let rgb = try #require(ThemeColorLocalStore.snapshot(fromCGColorComponents: [0.1, 0.2, 0.3]))
        #expect(rgb == ThemeColorSnapshot(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))

        let rgba = try #require(ThemeColorLocalStore.snapshot(fromCGColorComponents: [0.1, 0.2, 0.3, 0.4]))
        #expect(rgba == ThemeColorSnapshot(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4))

        #expect(ThemeColorLocalStore.snapshot(fromCGColorComponents: nil) == nil)
        #expect(ThemeColorLocalStore.snapshot(fromCGColorComponents: []) == nil)

        let encoded = try ThemeColorLocalStore.encode(rgba)
        #expect(try ThemeColorLocalStore.decode(from: encoded) == rgba)

        #expect(throws: Error.self) {
            try ThemeColorLocalStore.decode(from: Data("not-json".utf8))
        }
    }

    @Test func obsidianNavigationChromeFollowsCurrentColorScheme() {
        #expect(ObsidianNavigationChromePolicy.toolbarColorScheme(for: .light) == .light)
        #expect(ObsidianNavigationChromePolicy.toolbarColorScheme(for: .dark) == .dark)
    }

    @Test func leadCountDisplayDoesNotShowFakeZeroWhenCountIsUnknown() {
        #expect(LeadCountDisplay.leadPhrase(for: nil) == "your local leads")
        #expect(LeadCountDisplay.leadPhrase(for: 1) == "1 lead")
        #expect(LeadCountDisplay.leadPhrase(for: 2) == "2 leads")
        #expect(LeadCountDisplay.iCloudSyncMessage(for: nil) == "Your local leads will sync automatically via iCloud using your Apple ID.")
        #expect(!LeadCountDisplay.iCloudUploadMessage(for: nil).contains("0 leads"))
        #expect(!LeadCountDisplay.firebaseToICloudMessage(for: nil).contains("0 leads"))
    }

    @Test func leadCheckInJSONCodecKeepsCorruptJSONDistinctFromAuthoritativeEmpty() throws {
        #expect(try LeadCheckInJSONCodec.decode(nil) == nil)
        #expect(try LeadCheckInJSONCodec.decode("") == nil)

        let emptyDecoded = try #require(try LeadCheckInJSONCodec.decode("[]"))
        #expect(emptyDecoded.isEmpty)

        let checkInId = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let checkIn = LeadCheckInSyncPayload(
            id: checkInId,
            checkInDate: Date(timeIntervalSince1970: 1_800_000_000),
            checkInType: "door_knock",
            outcome: "Customer not home",
            notes: "Try again tomorrow",
            scheduledNextFollowUp: Date(timeIntervalSince1970: 1_800_086_400)
        )

        let encoded = try LeadCheckInJSONCodec.encode([checkIn])
        let decoded = try #require(try LeadCheckInJSONCodec.decode(encoded))
        #expect(decoded.count == 1)
        #expect(decoded.first?.id == checkIn.id)
        #expect(decoded.first?.checkInType == "door_knock")
        #expect(decoded.first?.outcome == "Customer not home")
        #expect(decoded.first?.notes == "Try again tomorrow")

        #expect(throws: Error.self) {
            try LeadCheckInJSONCodec.decode("not-json")
        }
    }

    @Test func userDataSyncCheckInParserRejectsPartialAuthoritativePayloads() throws {
        let checkInId = try #require(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"))
        let checkIn = LeadCheckInSyncPayload(
            id: checkInId,
            checkInDate: Date(timeIntervalSince1970: 1_800_000_000),
            checkInType: "phone_call",
            outcome: "Needs owner follow-up",
            notes: "Asked for a quote",
            scheduledNextFollowUp: nil
        )
        let validMap = checkIn.syncDictionary

        let directParsed = try #require(UserDataSyncManager.parseCheckInArray([validMap]))
        #expect(directParsed.count == 1)
        #expect(directParsed.first?.id == checkInId)
        #expect(directParsed.first?.checkInType == "phone_call")

        #expect(UserDataSyncManager.parseCheckInArray([validMap, ["id": "not-a-uuid"]]) == nil)
        #expect(UserDataSyncManager.parseCheckInArray([validMap, "bad-item"]) == nil)

        let jsonPayload = """
        [{
          "id": "\(checkInId.uuidString)",
          "checkInDate": "2027-01-15T08:00:00Z",
          "checkInType": "door_knock",
          "outcome": "Customer not home"
        }]
        """
        let jsonParsed = try #require(UserDataSyncManager.parseCheckInArray(jsonPayload))
        #expect(jsonParsed.count == 1)
        #expect(jsonParsed.first?.id == checkInId)
        #expect(jsonParsed.first?.checkInType == "door_knock")

        #expect(UserDataSyncManager.parseCheckInArray("[{\"id\":\"not-a-uuid\"}]") == nil)
    }

    @Test func leadSyncPayloadPublishesClearedOptionalDatesForMergeUpload() throws {
        let payload = LeadSyncPayload(
            id: try #require(UUID(uuidString: "CCCCCCCC-DDDD-EEEE-FFFF-000000000000")),
            name: "Test Lead",
            address: "123 Test St",
            phone: "",
            email: "",
            latitude: 43.5597,
            longitude: -79.7072,
            status: "not_contacted",
            notes: "",
            createdDate: Date(timeIntervalSince1970: 1_800_000_000),
            updatedDate: Date(timeIntervalSince1970: 1_800_000_100),
            priority: 0,
            source: "",
            estimatedValue: 0,
            price: 0,
            tags: "",
            visitCount: 0,
            serviceCategory: nil,
            neighborhoodId: nil,
            lastContactDate: nil,
            followUpDate: nil,
            checkIns: []
        )

        let data = payload.firestoreData
        #expect(data.keys.contains("lastContactDate"))
        #expect(data["lastContactDate"] is NSNull)
        #expect(data.keys.contains("followUpDate"))
        #expect(data["followUpDate"] is NSNull)

        let checkIns = try #require(data["checkIns"] as? [[String: Any]])
        #expect(checkIns.isEmpty)
    }

    @Test func userDataSyncFollowUpMergeDistinguishesLegacyMissingFromExplicitClear() {
        let existingDate = Date(timeIntervalSince1970: 1_800_000_000)
        let remoteDate = Date(timeIntervalSince1970: 1_800_086_400)

        #expect(
            UserDataSyncManager.resolvedFollowUpDateForMerge([:], existingDate: existingDate) == existingDate
        )
        #expect(
            UserDataSyncManager.resolvedFollowUpDateForMerge(["followUpDate": NSNull()], existingDate: existingDate) == nil
        )
        #expect(
            UserDataSyncManager.resolvedFollowUpDateForMerge(["followUpDate": remoteDate], existingDate: existingDate) == remoteDate
        )
    }

    @Test func corruptedLeadCleanupPreservesCoordinateOnlyLeads() {
        #expect(
            UserDataSyncManager.shouldDeleteCorruptedLead(
                hasId: false,
                name: "Customer",
                address: "123 Test St",
                latitude: 43.5597,
                longitude: -79.7072
            )
        )

        #expect(
            UserDataSyncManager.shouldDeleteCorruptedLead(
                hasId: true,
                name: "   ",
                address: nil,
                latitude: 0,
                longitude: 0
            )
        )

        #expect(
            !UserDataSyncManager.shouldDeleteCorruptedLead(
                hasId: true,
                name: nil,
                address: nil,
                latitude: 43.5597,
                longitude: -79.7072
            )
        )

        #expect(
            !UserDataSyncManager.shouldDeleteCorruptedLead(
                hasId: true,
                name: "Customer",
                address: nil,
                latitude: 0,
                longitude: 0
            )
        )
    }

    @Test func firebasePersonalSyncOnlyRunsForFirebaseSyncProvider() {
        #expect(
            UserDataSyncManager.shouldUseFirebasePersonalSync(
                provider: .firebase,
                isAuthenticated: true
            )
        )

        #expect(
            !UserDataSyncManager.shouldUseFirebasePersonalSync(
                provider: .firebase,
                isAuthenticated: false
            )
        )

        #expect(
            !UserDataSyncManager.shouldUseFirebasePersonalSync(
                provider: .icloud,
                isAuthenticated: true
            )
        )

        #expect(
            !UserDataSyncManager.shouldUseFirebasePersonalSync(
                provider: .off,
                isAuthenticated: true
            )
        )

        #expect(
            UserDataSyncManager.shouldDeleteLeadFromFirebase(
                provider: .firebase,
                isAuthenticated: true
            )
        )

        #expect(
            !UserDataSyncManager.shouldDeleteLeadFromFirebase(
                provider: .firebase,
                isAuthenticated: false
            )
        )

        #expect(
            !UserDataSyncManager.shouldDeleteLeadFromFirebase(
                provider: .icloud,
                isAuthenticated: true
            )
        )

        #expect(
            !UserDataSyncManager.shouldDeleteLeadFromFirebase(
                provider: .off,
                isAuthenticated: true
            )
        )

        #expect(
            UserDataSyncManager.cloudKitLeadBackupUserId(
                provider: .icloud,
                isAuthenticated: false,
                currentUserId: nil
            ) == UserDataSyncManager.privateCloudKitUserId
        )

        #expect(
            UserDataSyncManager.cloudKitLeadBackupUserId(
                provider: .firebase,
                isAuthenticated: true,
                currentUserId: "firebase-user"
            ) == "firebase-user"
        )

        #expect(
            UserDataSyncManager.cloudKitLeadBackupUserId(
                provider: .firebase,
                isAuthenticated: false,
                currentUserId: "firebase-user"
            ) == nil
        )

        #expect(
            UserDataSyncManager.cloudKitLeadBackupUserId(
                provider: .off,
                isAuthenticated: true,
                currentUserId: "firebase-user"
            ) == nil
        )

        #expect(
            UserDataSyncManager.shouldDeleteLeadFromCloud(
                provider: .icloud,
                isAuthenticated: false
            )
        )

        #expect(
            UserDataSyncManager.shouldDeleteLeadFromCloud(
                provider: .firebase,
                isAuthenticated: true
            )
        )

        #expect(
            !UserDataSyncManager.shouldDeleteLeadFromCloud(
                provider: .firebase,
                isAuthenticated: false
            )
        )

        #expect(
            !UserDataSyncManager.shouldDeleteLeadFromCloud(
                provider: .off,
                isAuthenticated: true
            )
        )
    }

    @Test func signOutWorkspaceCleanupPreservesICloudAndLocalOnlyData() {
        #expect(SignOutWorkspaceCleanupPolicy.shouldClearLocalWorkspaceData(provider: .firebase))
        #expect(!SignOutWorkspaceCleanupPolicy.shouldClearLocalWorkspaceData(provider: .icloud))
        #expect(!SignOutWorkspaceCleanupPolicy.shouldClearLocalWorkspaceData(provider: .off))
    }

    @Test func leadDeletionTombstonesPersistDeletedIds() throws {
        let suiteName = "LeadDeletionTombstoneTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "deleted_leads_test"
        let firstId = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let secondId = try #require(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))

        LeadDeletionTombstoneStore.markDeleted([firstId], in: defaults, key: key)
        LeadDeletionTombstoneStore.markDeleted([firstId, secondId], in: defaults, key: key)

        let loaded = LeadDeletionTombstoneStore.loadDeletedIds(from: defaults, key: key)
        #expect(loaded == [firstId, secondId])
    }

    @Test func leadCloudMergePolicySkipsLocallyDeletedLeads() throws {
        let deletedId = try #require(UUID(uuidString: "77777777-7777-7777-7777-777777777777"))
        let activeId = try #require(UUID(uuidString: "88888888-8888-8888-8888-888888888888"))

        #expect(LeadCloudMergePolicy.shouldSkipRemoteLead(
            documentId: deletedId.uuidString,
            deletedIds: [deletedId]
        ))
        #expect(!LeadCloudMergePolicy.shouldSkipRemoteLead(
            documentId: activeId.uuidString,
            deletedIds: [deletedId]
        ))
        #expect(!LeadCloudMergePolicy.shouldSkipRemoteLead(
            documentId: "not-a-uuid",
            deletedIds: [deletedId]
        ))
    }

    @Test func appleSearchAdsMarksCheckedOnlyAfterCompletedAttributionResponse() {
        #expect(
            AppleSearchAdsAttribution.shouldMarkAttributionRequestChecked(
                statusCode: 200,
                didDecodeResponse: true,
                attribution: false,
                didStoreAttributionData: false
            )
        )

        #expect(
            AppleSearchAdsAttribution.shouldMarkAttributionRequestChecked(
                statusCode: 200,
                didDecodeResponse: true,
                attribution: true,
                didStoreAttributionData: true
            )
        )

        #expect(
            !AppleSearchAdsAttribution.shouldMarkAttributionRequestChecked(
                statusCode: 500,
                didDecodeResponse: true,
                attribution: false,
                didStoreAttributionData: false
            )
        )

        #expect(
            !AppleSearchAdsAttribution.shouldMarkAttributionRequestChecked(
                statusCode: 200,
                didDecodeResponse: false,
                attribution: false,
                didStoreAttributionData: false
            )
        )

        #expect(
            !AppleSearchAdsAttribution.shouldMarkAttributionRequestChecked(
                statusCode: 200,
                didDecodeResponse: true,
                attribution: true,
                didStoreAttributionData: false
            )
        )
    }

    @Test func appleSearchAdsAttributionStoreSurfacesCorruptLocalData() throws {
        let suiteName = "AppleSearchAdsAttributionStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "asa_attribution_test"
        #expect(try AppleSearchAdsAttributionStore.load(from: defaults, key: key) == nil)

        let attribution = AttributionResponse(
            attribution: true,
            orgId: 111,
            campaignId: 222,
            conversionType: "Download",
            adGroupId: 333,
            countryOrRegion: "CA",
            keywordId: 444,
            creativeSetId: 555
        )

        try AppleSearchAdsAttributionStore.save(attribution, to: defaults, key: key)
        #expect(try AppleSearchAdsAttributionStore.load(from: defaults, key: key) == attribution)

        defaults.set(Data("not-json".utf8), forKey: key)
        #expect(throws: Error.self) {
            try AppleSearchAdsAttributionStore.load(from: defaults, key: key)
        }
    }

    private func makeAdvancedMapViewForTests() -> AdvancedMapView {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.5597, longitude: -79.7072),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        return AdvancedMapView(
            region: .constant(region),
            mapType: .constant(.standard),
            rotation: .constant(0),
            pitch: .constant(0),
            animateNextUpdate: .constant(false),
            is3DModeEnabled: .constant(false),
            visibleRegion: .constant(region),
            launchCenteringResetToken: 0,
            launchLocationCenterRevision: 0,
            leads: [],
            searchPin: .constant(nil),
            showsUserLocation: true,
            shouldFollowUserLocationOnLaunch: true,
            needsLaunchLocationCenteringConfirmation: true,
            hasLaunchLocationCandidate: true,
            onLaunchCenteringConfirmed: {},
            onLeadTap: { _ in },
            onLeadClusterTap: { _, _ in },
            onSearchPinTap: { _ in },
            onLongPress: { _, _ in }
        )
    }

}
