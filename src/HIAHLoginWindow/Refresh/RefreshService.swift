/**
 * RefreshService.swift
 * HIAH LoginWindow - Auto-Refresh Service
 *
 * Handles automatic 7-day refresh of HIAH Desktop and installed apps.
 * Also schedules expiration warning notifications to remind users
 * to open the app before certificates expire.
 *
 * IMPORTANT: Self-refresh requires:
 * 1. VPN (em_proxy) connected - creates loopback tunnel
 * 2. Minimuxer - communicates with lockdownd to install provisioning profiles
 * 3. AltSign - fetches new provisioning profiles from Apple
 *
 * Without minimuxer, self-refresh is NOT possible and the user must
 * reinstall the app using a computer.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation
import BackgroundTasks
import UserNotifications

// MARK: - Notification Identifiers

extension RefreshService {
    /// Notification identifier for expiration warnings
    static let expirationWarningNotificationID = "com.aspauldingcode.HIAHDesktop.expirationWarning"
    
    /// Notification identifier for refresh success
    static let refreshSuccessNotificationID = "com.aspauldingcode.HIAHDesktop.refreshSuccess"
    
    /// Notification identifier for refresh failure
    static let refreshFailureNotificationID = "com.aspauldingcode.HIAHDesktop.refreshFailure"
}

// MARK: - Refresh Errors

enum RefreshError: Error, LocalizedError {
    case notAuthenticated
    case vpnNotConnected
    case minimuxerNotAvailable
    case minimuxerNotReady
    case profileFetchFailed(Error)
    case profileInstallFailed(Error)
    case noPairingFile
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in with your Apple Account."
        case .vpnNotConnected:
            return "VPN not connected. The loopback VPN must be active to refresh."
        case .minimuxerNotAvailable:
            return "Self-refresh not available. Minimuxer is disabled (requires libimobiledevice)."
        case .minimuxerNotReady:
            return "Device connection not ready. Please check that the VPN is active."
        case .profileFetchFailed(let error):
            return "Failed to fetch provisioning profile: \(error.localizedDescription)"
        case .profileInstallFailed(let error):
            return "Failed to install provisioning profile: \(error.localizedDescription)"
        case .noPairingFile:
            return "No pairing file found. Please pair your device using AltServer first."
        }
    }
}

// MARK: - RefreshService

class RefreshService: ObservableObject {
    static let shared = RefreshService()
    
    // MARK: - Published State
    
    @Published var lastRefreshDate: Date?
    @Published var nextRefreshDate: Date?
    @Published var expirationDate: Date?
    @Published var isRefreshing = false
    @Published var canSelfRefresh = false // Only true when minimuxer is available
    
    // MARK: - Private Properties
    
    private let refreshTaskIdentifier = "com.aspauldingcode.HIAHDesktop.refresh"
    private let userDefaults = UserDefaults.standard
    
    private let lastRefreshKey = "HIAHDesktop.lastRefreshDate"
    private let expirationKey = "HIAHDesktop.certificateExpirationDate"
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted state
        loadPersistedState()
        
        // Check if self-refresh is available
        checkSelfRefreshAvailability()
        
        // Register background tasks
        registerBackgroundTasks()
        
        // Request notification permissions
        requestNotificationPermissions()
        
        // Schedule next refresh and expiration warning
        scheduleNextRefresh()
        scheduleExpirationWarning()
        
        print("[Refresh] Service initialized (canSelfRefresh: \(canSelfRefresh))")
    }
    
    // MARK: - Self-Refresh Availability
    
    /// Check if minimuxer is available for self-refresh
    private func checkSelfRefreshAvailability() {
        // Check if minimuxer is available (not the stub version)
        canSelfRefresh = HIAHMinimuxer.isAvailable()
        
        if !canSelfRefresh {
            print("[Refresh] ⚠️ Self-refresh NOT available: \(HIAHMinimuxer.disabledReason())")
        }
    }
    
    // MARK: - Persistence
    
    private func loadPersistedState() {
        lastRefreshDate = userDefaults.object(forKey: lastRefreshKey) as? Date
        expirationDate = userDefaults.object(forKey: expirationKey) as? Date
        
        if let lastRefresh = lastRefreshDate {
            print("[Refresh] Last refresh: \(lastRefresh)")
        }
        if let expiration = expirationDate {
            print("[Refresh] Certificate expires: \(expiration)")
        }
    }
    
    private func persistState() {
        if let lastRefresh = lastRefreshDate {
            userDefaults.set(lastRefresh, forKey: lastRefreshKey)
        }
        if let expiration = expirationDate {
            userDefaults.set(expiration, forKey: expirationKey)
        }
        userDefaults.synchronize()
    }
    
    // MARK: - Notification Permissions
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("[Refresh] Notification permission granted")
            } else if let error = error {
                print("[Refresh] Notification permission error: \(error)")
            } else {
                print("[Refresh] Notification permission denied")
            }
        }
    }
    
    // MARK: - Background Tasks
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskIdentifier,
            using: nil
        ) { task in
            self.handleRefreshTask(task as! BGAppRefreshTask)
        }
        
        print("[Refresh] Background task registered")
    }
    
    /// Schedule the next background refresh
    /// - Note: Schedules for 5 days from now (2 days before expiration)
    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        
        // Schedule for 5 days from now (2 days before 7-day expiration)
        let refreshDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())
        request.earliestBeginDate = refreshDate
        
        do {
            try BGTaskScheduler.shared.submit(request)
            nextRefreshDate = request.earliestBeginDate
            print("[Refresh] Next refresh scheduled for: \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            print("[Refresh] Failed to schedule refresh: \(error)")
        }
    }
    
    private func handleRefreshTask(_ task: BGAppRefreshTask) {
        print("[Refresh] Background refresh task started")
        
        task.expirationHandler = {
            print("[Refresh] Background task expired")
            task.setTaskCompleted(success: false)
            self.sendRefreshFailureNotification(error: "Background task expired")
        }
        
        Task {
            do {
                try await performRefresh()
                task.setTaskCompleted(success: true)
                scheduleNextRefresh()
                scheduleExpirationWarning()
            } catch {
                print("[Refresh] Refresh failed: \(error)")
                task.setTaskCompleted(success: false)
                sendRefreshFailureNotification(error: error.localizedDescription)
            }
        }
    }
    
    // MARK: - Expiration Warning Notifications
    
    /// Schedule a notification 24 hours before certificate expires
    func scheduleExpirationWarning() {
        guard let expiration = expirationDate else {
            print("[Refresh] No expiration date, cannot schedule warning")
            return
        }
        
        // Cancel any existing warning notification
        cancelExpirationWarning()
        
        // Schedule notification 24 hours before expiration
        let warningDate = expiration.addingTimeInterval(-24 * 60 * 60)
        let timeIntervalUntilWarning = warningDate.timeIntervalSinceNow
        
        guard timeIntervalUntilWarning > 0 else {
            // Already past warning time - check if already expired
            if expiration.timeIntervalSinceNow < 0 {
                print("[Refresh] ⚠️ Certificate already expired!")
                sendExpirationNotificationImmediately(isExpired: true)
            } else {
                // Within 24 hours, send notification now
                print("[Refresh] ⚠️ Within 24 hours of expiration")
                sendExpirationNotificationImmediately(isExpired: false)
            }
            return
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeIntervalUntilWarning,
            repeats: false
        )
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("HIAH Desktop Expiring Soon", comment: "")
        
        if canSelfRefresh {
            content.body = NSLocalizedString("HIAH Desktop will expire in 24 hours. Open the app to refresh and prevent it from expiring.", comment: "")
        } else {
            content.body = NSLocalizedString("HIAH Desktop will expire in 24 hours. Self-refresh is not available - you may need to reinstall using a computer.", comment: "")
        }
        
        content.sound = .default
        content.badge = 1
        
        // Add action to open app
        content.categoryIdentifier = "EXPIRATION_WARNING"
        
        let request = UNNotificationRequest(
            identifier: RefreshService.expirationWarningNotificationID,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Refresh] Failed to schedule expiration warning: \(error)")
            } else {
                print("[Refresh] Expiration warning scheduled for: \(warningDate)")
            }
        }
    }
    
    /// Cancel the expiration warning notification
    func cancelExpirationWarning() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [RefreshService.expirationWarningNotificationID]
        )
    }
    
    /// Send an expiration notification immediately
    private func sendExpirationNotificationImmediately(isExpired: Bool) {
        let content = UNMutableNotificationContent()
        
        if isExpired {
            content.title = NSLocalizedString("HIAH Desktop Expired", comment: "")
            if canSelfRefresh {
                content.body = NSLocalizedString("HIAH Desktop has expired. Open the app and sign in to refresh it.", comment: "")
            } else {
                content.body = NSLocalizedString("HIAH Desktop has expired. Self-refresh is not available - you need to reinstall using a computer.", comment: "")
            }
        } else {
            content.title = NSLocalizedString("HIAH Desktop Expiring Soon", comment: "")
            if canSelfRefresh {
                content.body = NSLocalizedString("HIAH Desktop will expire within 24 hours. Open the app now to refresh.", comment: "")
            } else {
                content.body = NSLocalizedString("HIAH Desktop will expire within 24 hours. Self-refresh is not available.", comment: "")
            }
        }
        
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: RefreshService.expirationWarningNotificationID,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Refresh Notifications
    
    private func sendRefreshSuccessNotification() {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("HIAH Desktop Refreshed", comment: "")
        content.body = NSLocalizedString("Your certificate has been refreshed successfully.", comment: "")
        content.sound = .default
        content.badge = 0
        
        let request = UNNotificationRequest(
            identifier: RefreshService.refreshSuccessNotificationID,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func sendRefreshFailureNotification(error: String) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Failed to Refresh HIAH Desktop", comment: "")
        content.body = String(format: NSLocalizedString("Open the app to try again: %@", comment: ""), error)
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: RefreshService.refreshFailureNotificationID,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Refresh Logic
    
    /// Perform certificate refresh using minimuxer + AltSign
    /// This installs new provisioning profiles via lockdownd through the VPN tunnel
    func performRefresh() async throws {
        print("[Refresh] Starting refresh...")
        
        await MainActor.run {
            isRefreshing = true
        }
        
        defer {
            Task { @MainActor in
                isRefreshing = false
            }
        }
        
        // Step 1: Check if self-refresh is available
        guard canSelfRefresh else {
            throw RefreshError.minimuxerNotAvailable
        }
        
        // Step 2: Check if authenticated
        let isAuthenticated = await MainActor.run {
            AuthenticationManager.shared.isAuthenticated
        }
        
        guard isAuthenticated else {
            throw RefreshError.notAuthenticated
        }
        
        // Step 3: Check VPN is connected
        // Note: HIAHVPNStateMachine.shared() is a class method in Objective-C
        let vpnStateMachine = HIAHVPNStateMachine.shared()
        guard vpnStateMachine.isConnected else {
            throw RefreshError.vpnNotConnected
        }
        
        // Step 4: Check for pairing file
        guard HIAHMinimuxer.hasPairingFile() else {
            throw RefreshError.noPairingFile
        }
        
        // Step 5: Initialize minimuxer if needed
        let minimuxer = HIAHMinimuxer.shared
        if minimuxer.status != .ready {
            guard let pairingPath = HIAHMinimuxer.defaultPairingFilePath() else {
                throw RefreshError.noPairingFile
            }
            
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let logPath = documentsURL?.appendingPathComponent("minimuxer.log").path
            
            let started = minimuxer.initialize(pairingFile: pairingPath, logPath: logPath, consoleLogging: true)
            guard started else {
                throw RefreshError.minimuxerNotReady
            }
        }
        
        // Step 6: Wait for device connection
        var connectionAttempts = 0
        while !minimuxer.testDeviceConnection() && connectionAttempts < 10 {
            print("[Refresh] Waiting for device connection... (\(connectionAttempts + 1)/10)")
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            connectionAttempts += 1
        }
        
        guard minimuxer.testDeviceConnection() else {
            throw RefreshError.minimuxerNotReady
        }
        
        // Step 7: Get account session for API calls
        guard let team = HIAHAccountManager.shared.team,
              let session = HIAHAccountManager.shared.session else {
            throw RefreshError.notAuthenticated
        }
        
        // Step 8: Fetch App ID for HIAH Desktop (or create if needed)
        print("[Refresh] Fetching App ID for HIAH Desktop...")
        let bundleID = Bundle.main.bundleIdentifier ?? "com.aspauldingcode.HIAHDesktop"
        
        let appID: ALTAppID
        do {
            // First try to fetch existing App IDs
            let existingAppIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
            
            if let existingAppID = existingAppIDs.first(where: { $0.bundleIdentifier == bundleID }) {
                print("[Refresh] Found existing App ID: \(existingAppID.bundleIdentifier)")
                appID = existingAppID
            } else {
                // Create new App ID
                print("[Refresh] Creating new App ID for: \(bundleID)")
                appID = try await ALTAppleAPI.shared.addAppID(name: "HIAH Desktop", bundleIdentifier: bundleID, team: team, session: session)
            }
        } catch {
            throw RefreshError.profileFetchFailed(error)
        }
        
        // Step 9: Fetch fresh provisioning profile from Apple
        print("[Refresh] Fetching provisioning profile from Apple...")
        let provisioningProfile: ALTProvisioningProfile
        do {
            provisioningProfile = try await ALTAppleAPI.shared.fetchProvisioningProfile(
                for: appID,
                deviceType: .iphone,
                team: team,
                session: session
            )
            print("[Refresh] Got provisioning profile, expiration: \(provisioningProfile.expirationDate)")
        } catch {
            throw RefreshError.profileFetchFailed(error)
        }
        
        // Step 10: Install provisioning profile via minimuxer/lockdownd
        print("[Refresh] Installing provisioning profile via lockdownd...")
        do {
            // ALTProvisioningProfile has a 'data' property containing the raw profile bytes
            try minimuxer.installProvisioningProfile(provisioningProfile.data)
        } catch {
            throw RefreshError.profileInstallFailed(error)
        }
        
        // Step 11: Update state with actual expiration from profile
        let now = Date()
        // ALTProvisioningProfile.expirationDate is non-optional
        let newExpiration: Date = provisioningProfile.expirationDate
        
        await MainActor.run {
            lastRefreshDate = now
            expirationDate = newExpiration
            AuthenticationManager.shared.certificateExpirationDate = newExpiration
        }
        
        // Persist state
        persistState()
        
        // Schedule new expiration warning
        scheduleExpirationWarning()
        
        // Clear badge
        await MainActor.run {
            UNUserNotificationCenter.current().setBadgeCount(0)
        }
        
        print("[Refresh] ✅ Refresh complete - expires: \(newExpiration)")
    }
    
    /// Manual refresh triggered by user
    func manualRefresh() async throws {
        print("[Refresh] Manual refresh requested")
        
        // Check if self-refresh is available
        guard canSelfRefresh else {
            print("[Refresh] ⚠️ Self-refresh not available")
            throw RefreshError.minimuxerNotAvailable
        }
        
        try await performRefresh()
        sendRefreshSuccessNotification()
    }
    
    /// Refresh on app launch if needed
    func refreshOnLaunchIfNeeded() {
        Task {
            // Only auto-refresh if certificate is expiring within 2 days
            guard let days = await daysUntilExpiration(), days <= 2 else {
                print("[Refresh] Certificate valid, no auto-refresh needed")
                return
            }
            
            // Check if self-refresh is available
            guard canSelfRefresh else {
                print("[Refresh] ⚠️ Certificate expiring but self-refresh not available")
                sendExpirationNotificationImmediately(isExpired: days < 0)
                return
            }
            
            print("[Refresh] Certificate expiring soon (\(days) days), auto-refreshing...")
            
            do {
                try await performRefresh()
                print("[Refresh] ✅ Auto-refresh successful")
            } catch {
                print("[Refresh] ❌ Auto-refresh failed: \(error)")
                sendRefreshFailureNotification(error: error.localizedDescription)
            }
        }
    }
    
    // MARK: - Status
    
    /// Get days until certificate expiration
    func daysUntilExpiration() async -> Int? {
        // First check AuthenticationManager's expiration
        let authExpiration = await MainActor.run {
            AuthenticationManager.shared.certificateExpirationDate
        }
        
        let effectiveExpiration = authExpiration ?? expirationDate
        guard let expiration = effectiveExpiration else { return nil }
        
        let components = Calendar.current.dateComponents([.day], from: Date(), to: expiration)
        return components.day
    }
    
    /// Get hours until certificate expiration
    func hoursUntilExpiration() async -> Int? {
        let authExpiration = await MainActor.run {
            AuthenticationManager.shared.certificateExpirationDate
        }
        
        let effectiveExpiration = authExpiration ?? expirationDate
        guard let expiration = effectiveExpiration else { return nil }
        
        let components = Calendar.current.dateComponents([.hour], from: Date(), to: expiration)
        return components.hour
    }
    
    /// Check if certificate is expired
    func isExpired() async -> Bool {
        guard let days = await daysUntilExpiration() else {
            return true // No expiration date = assume expired
        }
        return days < 0
    }
    
    /// Get formatted time until expiration
    func formattedTimeUntilExpiration() async -> String {
        guard let hours = await hoursUntilExpiration() else {
            return NSLocalizedString("Unknown", comment: "")
        }
        
        if hours < 0 {
            return NSLocalizedString("Expired", comment: "")
        } else if hours < 24 {
            return String(format: NSLocalizedString("%d hours", comment: ""), hours)
        } else {
            let days = hours / 24
            return String(format: NSLocalizedString("%d days", comment: ""), days)
        }
    }
    
    /// Get refresh status description
    func refreshStatusDescription() -> String {
        if canSelfRefresh {
            return NSLocalizedString("Self-refresh available via minimuxer", comment: "")
        } else {
            return NSLocalizedString("Self-refresh unavailable - minimuxer disabled", comment: "")
        }
    }
}

// MARK: - App Lifecycle Integration

extension RefreshService {
    /// Call this when app becomes active
    func appDidBecomeActive() {
        print("[Refresh] App became active - checking refresh status")
        
        // Re-check self-refresh availability (in case something changed)
        checkSelfRefreshAvailability()
        
        // Schedule expiration warning (in case it was dismissed)
        scheduleExpirationWarning()
        
        // Check if we should auto-refresh
        refreshOnLaunchIfNeeded()
    }
    
    /// Call this when app enters background
    func appDidEnterBackground() {
        print("[Refresh] App entered background")
        
        // Ensure expiration warning is scheduled
        scheduleExpirationWarning()
        
        // Ensure next refresh is scheduled
        scheduleNextRefresh()
    }
}
