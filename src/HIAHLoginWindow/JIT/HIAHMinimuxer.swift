/**
 * HIAHMinimuxer.swift
 * HIAH LoginWindow - Minimuxer Swift Wrapper (STUB)
 *
 * NOTE: Minimuxer is currently DISABLED because it requires
 * libimobiledevice to be built for iOS. This file provides stub
 * implementations that return appropriate errors.
 *
 * To re-enable minimuxer:
 * 1. Build libimobiledevice for iOS (arm64/arm64e + simulator)
 * 2. Add libimobiledevice.a to the project
 * 3. Uncomment minimuxer linking in project.yml
 * 4. Uncomment minimuxer Swift files in project.yml
 * 5. Replace this stub file with the real implementation
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation

/// Status of the Minimuxer connection
@objc public enum HIAHMinimuxerStatus: Int {
    case notStarted = 0
    case starting = 1
    case ready = 2
    case noDevice = 3
    case noPairingFile = 4
    case error = 5
    case disabled = 6  // Added for stub
}

/// Swift wrapper for the Minimuxer Rust library (STUB VERSION)
/// This stub version returns errors indicating minimuxer is disabled
@objc public class HIAHMinimuxer: NSObject {
    
    // MARK: - Singleton
    
    @objc public static let shared = HIAHMinimuxer()
    
    // MARK: - Properties
    
    @objc public private(set) var status: HIAHMinimuxerStatus = .disabled
    @objc public private(set) var lastErrorMessage: String? = "Minimuxer is disabled (requires libimobiledevice)"
    
    @objc public var isReady: Bool {
        return false  // Always false - minimuxer is disabled
    }
    
    private override init() {
        super.init()
        print("[Minimuxer] ⚠️ STUB: Minimuxer is disabled (requires libimobiledevice for iOS)")
    }
    
    // MARK: - Lifecycle (STUB)
    
    @objc public func initialize(pairingFile pairingFilePath: String,
                                 logPath: String?,
                                 consoleLogging: Bool = false) -> Bool {
        print("[Minimuxer] ⚠️ STUB: initialize() called but minimuxer is disabled")
        status = .disabled
        lastErrorMessage = "Minimuxer is disabled (requires libimobiledevice)"
        return false
    }
    
    @objc public func start(pairingFile pairingFilePath: String) -> Bool {
        return initialize(pairingFile: pairingFilePath, logPath: nil, consoleLogging: false)
    }
    
    @objc public func stop() {
        status = .disabled
        print("[Minimuxer] STUB: Stopped")
    }
    
    // MARK: - Device Info (STUB)
    
    @objc public func fetchDeviceUDID() -> String? {
        print("[Minimuxer] ⚠️ STUB: fetchDeviceUDID() - minimuxer is disabled")
        return nil
    }
    
    @objc public func testDeviceConnection() -> Bool {
        return false
    }
    
    // MARK: - JIT Enablement (STUB)
    
    @objc public func enableJIT(forBundleID bundleID: String) throws {
        print("[Minimuxer] ⚠️ STUB: enableJIT() called for \(bundleID) but minimuxer is disabled")
        throw NSError(domain: "HIAHMinimuxer", code: 99,
                     userInfo: [NSLocalizedDescriptionKey: "Minimuxer is disabled (requires libimobiledevice)"])
    }
    
    @objc public func attachDebugger(toPID pid: UInt32) throws {
        print("[Minimuxer] ⚠️ STUB: attachDebugger() called for PID \(pid) but minimuxer is disabled")
        throw NSError(domain: "HIAHMinimuxer", code: 99,
                     userInfo: [NSLocalizedDescriptionKey: "Minimuxer is disabled (requires libimobiledevice)"])
    }
    
    // MARK: - App Installation (STUB)
    
    @objc public func installIPA(bundleID: String, ipaData: Data) throws {
        print("[Minimuxer] ⚠️ STUB: installIPA() called but minimuxer is disabled")
        throw NSError(domain: "HIAHMinimuxer", code: 99,
                     userInfo: [NSLocalizedDescriptionKey: "Minimuxer is disabled (requires libimobiledevice)"])
    }
    
    @objc public func removeApp(bundleID: String) throws {
        print("[Minimuxer] ⚠️ STUB: removeApp() called but minimuxer is disabled")
        throw NSError(domain: "HIAHMinimuxer", code: 99,
                     userInfo: [NSLocalizedDescriptionKey: "Minimuxer is disabled (requires libimobiledevice)"])
    }
    
    // MARK: - Provisioning Profiles (STUB)
    
    @objc public func installProvisioningProfile(_ profileData: Data) throws {
        print("[Minimuxer] ⚠️ STUB: installProvisioningProfile() called but minimuxer is disabled")
        throw NSError(domain: "HIAHMinimuxer", code: 99,
                     userInfo: [NSLocalizedDescriptionKey: "Minimuxer is disabled (requires libimobiledevice)"])
    }
    
    @objc public func removeProvisioningProfile(id profileID: String) throws {
        print("[Minimuxer] ⚠️ STUB: removeProvisioningProfile() called but minimuxer is disabled")
        throw NSError(domain: "HIAHMinimuxer", code: 99,
                     userInfo: [NSLocalizedDescriptionKey: "Minimuxer is disabled (requires libimobiledevice)"])
    }
    
    // MARK: - Pairing File
    
    /// Get the default location for the pairing file
    /// SideStore/AltStore store it in the app's Documents directory
    @objc public class func defaultPairingFilePath() -> String? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documentsDir = paths.first else { return nil }
        
        let pairingFile = documentsDir.appendingPathComponent("ALTPairingFile.mobiledevicepairing")
        if FileManager.default.fileExists(atPath: pairingFile.path) {
            return pairingFile.path
        }
        
        // Also check for SideStore's naming convention
        let sidestorePairingFile = documentsDir.appendingPathComponent("pairing_file.plist")
        if FileManager.default.fileExists(atPath: sidestorePairingFile.path) {
            return sidestorePairingFile.path
        }
        
        return nil
    }
    
    /// Check if a pairing file exists
    @objc public class func hasPairingFile() -> Bool {
        return defaultPairingFilePath() != nil
    }
    
    // MARK: - Stub Availability Check
    
    /// Check if minimuxer is available (always false for stub)
    @objc public class func isAvailable() -> Bool {
        return false
    }
    
    /// Get information about why minimuxer is disabled
    @objc public class func disabledReason() -> String {
        return """
            Minimuxer is disabled because it requires libimobiledevice to be built for iOS.
            
            To enable minimuxer-based JIT:
            1. Build libimobiledevice for iOS (arm64/arm64e + simulator)
            2. Add libimobiledevice.a to vendor/sidestore/lib/
            3. Uncomment minimuxer linking in project.yml
            4. Uncomment minimuxer Swift files in project.yml
            5. Replace the stub HIAHMinimuxer.swift with the real implementation
            
            In the meantime, JIT is enabled through alternative methods when available.
            """
    }
}
