/**
 * HIAHMinimuxerJIT.swift
 * HIAH LoginWindow - JIT Enablement via Minimuxer (STUB)
 *
 * NOTE: Minimuxer is currently DISABLED because it requires
 * libimobiledevice to be built for iOS. This file provides stub
 * implementations that return appropriate errors.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation

/// Errors that can occur during JIT enablement
public enum HIAHJITError: Error, LocalizedError {
    case minimuxerNotStarted
    case minimuxerDisabled
    case noPairingFile
    case vpnNotConnected
    case debugFailed(String)
    case attachFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .minimuxerNotStarted:
            return "Minimuxer service not started. Call startMinimuxer() first."
        case .minimuxerDisabled:
            return "Minimuxer is disabled (requires libimobiledevice). Using alternative JIT methods."
        case .noPairingFile:
            return "No pairing file found. Device must be paired with a computer first."
        case .vpnNotConnected:
            return "VPN not connected. Enable WireGuard VPN first."
        case .debugFailed(let msg):
            return "Failed to enable JIT for app: \(msg)"
        case .attachFailed(let msg):
            return "Failed to attach debugger: \(msg)"
        }
    }
}

/// Manages JIT enablement via Minimuxer (STUB VERSION)
/// 
/// NOTE: Minimuxer is disabled. All methods return errors indicating
/// that minimuxer is not available.
@objc public class HIAHMinimuxerJIT: NSObject {
    
    /// Shared instance
    @objc public static let shared = HIAHMinimuxerJIT()
    
    /// Whether minimuxer has been started (always false - disabled)
    @objc public private(set) var isStarted = false
    
    /// Notification posted when JIT is successfully enabled
    @objc public static let JITEnabledNotification = Notification.Name("HIAHJITEnabled")
    
    private override init() {
        super.init()
        print("[MinimuxerJIT] ⚠️ STUB: Minimuxer JIT is disabled (requires libimobiledevice)")
    }
    
    // MARK: - Minimuxer Lifecycle (STUB)
    
    /// Starts the minimuxer service
    /// NOTE: This is a stub - minimuxer is disabled
    @objc public func startMinimuxer(pairingFile: String, logPath: String, consoleLogging: Bool = false) throws {
        print("[MinimuxerJIT] ⚠️ STUB: startMinimuxer() called but minimuxer is disabled")
        throw HIAHJITError.minimuxerDisabled
    }
    
    /// Checks if minimuxer is ready (always false - disabled)
    @objc public var isReady: Bool {
        return false
    }
    
    /// Checks if device is connected (always false - disabled)
    @objc public var isDeviceConnected: Bool {
        return false
    }
    
    /// Gets the device UDID (always nil - disabled)
    @objc public var deviceUDID: String? {
        return nil
    }
    
    // MARK: - JIT Enablement (STUB)
    
    /// Enables JIT for an app by bundle ID
    /// NOTE: This is a stub - minimuxer is disabled
    @objc public func enableJIT(forBundleID bundleID: String) throws {
        print("[MinimuxerJIT] ⚠️ STUB: enableJIT() called for \(bundleID) but minimuxer is disabled")
        throw HIAHJITError.minimuxerDisabled
    }
    
    /// Enables JIT for a process by PID
    /// NOTE: This is a stub - minimuxer is disabled
    @objc public func enableJIT(forPID pid: UInt32) throws {
        print("[MinimuxerJIT] ⚠️ STUB: enableJIT() called for PID \(pid) but minimuxer is disabled")
        throw HIAHJITError.minimuxerDisabled
    }
    
    // MARK: - Pairing File Management
    
    /// Gets the path to the pairing file in Documents
    @objc public var pairingFilePath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ALTPairingFile.mobiledevicepairing").path
    }
    
    /// Checks if a pairing file exists
    @objc public var hasPairingFile: Bool {
        return FileManager.default.fileExists(atPath: pairingFilePath)
    }
    
    /// Loads the pairing file contents
    @objc public func loadPairingFile() -> String? {
        guard hasPairingFile else { return nil }
        return try? String(contentsOfFile: pairingFilePath, encoding: .utf8)
    }
    
    /// Saves a pairing file
    @objc public func savePairingFile(_ contents: String) throws {
        try contents.write(toFile: pairingFilePath, atomically: true, encoding: .utf8)
        print("[MinimuxerJIT] Pairing file saved")
    }
    
    // MARK: - Stub Status
    
    /// Check if minimuxer-based JIT is available (always false for stub)
    @objc public class func isAvailable() -> Bool {
        return false
    }
    
    /// Get information about why minimuxer is disabled
    @objc public class func disabledReason() -> String {
        return "Minimuxer is disabled because it requires libimobiledevice to be built for iOS."
    }
}
