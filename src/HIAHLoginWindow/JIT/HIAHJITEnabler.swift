/**
 * HIAHJITEnabler.swift
 * HIAH LoginWindow - JIT Enablement via Minimuxer
 *
 * Enables JIT for processes using Minimuxer through VPN tunnel.
 * This allows unsigned dylibs to be loaded via dyld bypass.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation

/// Enables JIT for processes using Minimuxer
@objc public class HIAHJITEnabler: NSObject {
    @objc public static let shared = HIAHJITEnabler()
    
    private override init() {
        super.init()
    }
    
    /// Enable JIT for the current process via Minimuxer
    /// - Parameter completion: Called with success status
    @objc public func enableJITForCurrentProcess(completion: @escaping (Bool, Error?) -> Void) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.aspauldingcode.HIAHDesktop"
        enableJIT(forBundleID: bundleID, completion: completion)
    }
    
    /// Enable JIT for an app by bundle ID
    @objc public func enableJIT(forBundleID bundleID: String,
                                completion: @escaping (Bool, Error?) -> Void) {
        // Check if JIT is already enabled
        if isJITEnabled() {
            print("[JITEnabler] JIT already enabled")
            completion(true, nil)
            return
        }
        
        print("[JITEnabler] Enabling JIT for: \(bundleID)")
        
        // Get minimuxer instance
        let minimuxer = HIAHMinimuxer.shared
        
        // Check if minimuxer is ready
        if !minimuxer.isReady {
            // Try to start minimuxer with default pairing file
            guard let pairingPath = HIAHMinimuxer.defaultPairingFilePath() else {
                print("[JITEnabler] No pairing file found - JIT via Minimuxer not available")
                // Fall back to VPN-only mode (some devices may enable JIT with VPN alone)
                enableJITVPNFallback(completion: completion)
                return
            }
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
            let logPath = (documentsPath as NSString).appendingPathComponent("minimuxer.log")
            
            if !minimuxer.initialize(pairingFile: pairingPath, logPath: logPath, consoleLogging: true) {
                print("[JITEnabler] Failed to start Minimuxer: \(minimuxer.lastErrorMessage ?? "Unknown error")")
                // Fall back to VPN-only mode
                enableJITVPNFallback(completion: completion)
                return
            }
        }
        
        // Verify device connection through VPN tunnel
        guard minimuxer.testDeviceConnection() else {
            print("[JITEnabler] No device connection through VPN - trying fallback")
            enableJITVPNFallback(completion: completion)
            return
        }
        
        // Enable JIT via debug server
        print("[JITEnabler] Enabling JIT via Minimuxer debug server...")
        do {
            try minimuxer.enableJIT(forBundleID: bundleID)
            
            // Verify JIT is actually enabled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let enabled = self.isJITEnabled()
                if enabled {
                    print("[JITEnabler] ✅ JIT enabled successfully via Minimuxer")
                    completion(true, nil)
                } else {
                    print("[JITEnabler] ⚠️ JIT command succeeded but CS_DEBUGGED not set - may need VPN activation")
                    completion(true, nil) // Still return success - signing fallback
                }
            }
        } catch {
            print("[JITEnabler] Minimuxer JIT enablement failed: \(error.localizedDescription)")
            // Try VPN fallback
            enableJITVPNFallback(completion: completion)
        }
    }
    
    /// Fallback: Try to enable JIT with VPN alone (without Minimuxer)
    /// Some iOS versions may enable JIT automatically when VPN is active
    private func enableJITVPNFallback(completion: @escaping (Bool, Error?) -> Void) {
        print("[JITEnabler] Trying VPN-only fallback...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Wait for VPN to fully establish
            Thread.sleep(forTimeInterval: 1.5)
            
            // Check if JIT is now enabled
            if self.isJITEnabled() {
                print("[JITEnabler] ✅ JIT enabled via VPN fallback")
                DispatchQueue.main.async {
                    completion(true, nil)
                }
            } else {
                print("[JITEnabler] ⚠️ JIT not enabled - signing fallback will be used")
                // Return success anyway - the app will work with signed dylibs
                DispatchQueue.main.async {
                    completion(true, nil)
                }
            }
        }
    }
    
    /// Check if JIT is currently enabled (CS_DEBUGGED flag)
    @objc public func isJITEnabled() -> Bool {
        return HIAHJITEnablerHelper_isJITEnabled()
    }
}

// Helper C function for JIT checking (defined in HIAHJITEnablerHelper.m)
@_silgen_name("HIAHJITEnablerHelper_isJITEnabled")
func HIAHJITEnablerHelper_isJITEnabled() -> Bool
