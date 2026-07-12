//
//  AppleSearchAdsAttribution.swift
//  D2D Advancer
//
//  Apple Search Ads Attribution tracking
//

import Foundation
import AdServices

/// Service to track Apple Search Ads attribution
class AppleSearchAdsAttribution {
    static let shared = AppleSearchAdsAttribution()

    private let attributionKey = "apple_search_ads_attribution"
    private let hasCheckedAttributionKey = "has_checked_asa_attribution"

    private init() {}

    /// Check for Apple Search Ads attribution on app launch
    /// Should be called once per install
    func checkAttribution() {
        // Only check once per install
        guard !UserDefaults.standard.bool(forKey: hasCheckedAttributionKey) else {
            print("🔍 ASA: Already checked attribution for this install")
            return
        }

        // Use AdServices framework (iOS 14.3+)
        if #available(iOS 14.3, *) {
            fetchAttributionToken()
        } else {
            print("🔍 ASA: AdServices not available on this iOS version")
            UserDefaults.standard.set(true, forKey: hasCheckedAttributionKey)
        }
    }

    @available(iOS 14.3, *)
    private func fetchAttributionToken() {
        Task {
            do {
                // Get attribution token
                let token = try AAAttribution.attributionToken()
                print("🔍 ASA: Attribution token received")

                // Send to Apple's attribution API
                await requestAttribution(token: token)

                // Mark as checked
                UserDefaults.standard.set(true, forKey: hasCheckedAttributionKey)
            } catch {
                print("🔍 ASA: Error getting attribution token: \(error.localizedDescription)")
                // Still mark as checked to avoid repeated failures
                UserDefaults.standard.set(true, forKey: hasCheckedAttributionKey)
            }
        }
    }

    @available(iOS 14.3, *)
    private func requestAttribution(token: String) async {
        // Apple's attribution endpoint
        let urlString = "https://api-adservices.apple.com/api/v1/"

        guard let url = URL(string: urlString) else {
            print("🔍 ASA: Invalid attribution URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = token.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("🔍 ASA: Invalid response type")
                return
            }

            if httpResponse.statusCode == 200 {
                // Parse attribution data
                if let attributionData = try? JSONDecoder().decode(AttributionResponse.self, from: data) {
                    handleAttributionData(attributionData)
                } else {
                    print("🔍 ASA: Failed to decode attribution data")
                }
            } else {
                print("🔍 ASA: Attribution request failed with status: \(httpResponse.statusCode)")
            }
        } catch {
            print("🔍 ASA: Attribution request error: \(error.localizedDescription)")
        }
    }

    private func handleAttributionData(_ data: AttributionResponse) {
        // Check if attribution is true (user came from Apple Search Ads)
        guard data.attribution else {
            print("🔍 ASA: User did not come from Apple Search Ads")
            return
        }

        print("🔍 ASA: User came from Apple Search Ads!")
        print("🔍 ASA: Campaign ID: \(data.campaignId.map(String.init) ?? "unknown")")
        print("🔍 ASA: Ad Group ID: \(data.adGroupId.map(String.init) ?? "unknown")")
        print("🔍 ASA: Keyword ID: \(data.keywordId.map(String.init) ?? "unknown")")

        // Save attribution data
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: attributionKey)
        }
    }

    /// Get stored attribution data if available
    func getAttributionData() -> AttributionResponse? {
        guard let data = UserDefaults.standard.data(forKey: attributionKey),
              let attribution = try? JSONDecoder().decode(AttributionResponse.self, from: data) else {
            return nil
        }
        return attribution
    }
}

// MARK: - Attribution Response Model

struct AttributionResponse: Codable {
    let attribution: Bool
    let orgId: Int?
    let campaignId: Int?
    let conversionType: String?
    let adGroupId: Int?
    let countryOrRegion: String?
    let keywordId: Int?
    let creativeSetId: Int?

    enum CodingKeys: String, CodingKey {
        case attribution
        case orgId = "orgId"
        case campaignId = "campaignId"
        case conversionType = "conversionType"
        case adGroupId = "adGroupId"
        case countryOrRegion = "countryOrRegion"
        case keywordId = "keywordId"
        case creativeSetId = "creativeSetId"
    }
}
