/**
 * HIAHWireGuardManager.h
 * HIAH LoginWindow - WireGuard VPN Integration
 *
 * Integrates with WireGuard (App Store) to provide VPN loopback
 * for JIT enablement without requiring a paid developer account.
 *
 * Based on SideStore's StoreAppsVPN approach (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Status of WireGuard VPN connection
typedef NS_ENUM(NSInteger, HIAHWireGuardStatus) {
    HIAHWireGuardStatusNotInstalled,    // WireGuard app not installed
    HIAHWireGuardStatusDisconnected,    // WireGuard installed but VPN not active
    HIAHWireGuardStatusConnecting,      // VPN is connecting
    HIAHWireGuardStatusConnected,       // VPN is active
    HIAHWireGuardStatusError            // Error state
};

/// Manages WireGuard VPN integration for JIT enablement
@interface HIAHWireGuardManager : NSObject

+ (instancetype)sharedManager;

/// Current WireGuard/VPN status
@property (nonatomic, readonly) HIAHWireGuardStatus status;

/// Whether WireGuard VPN is currently active
@property (nonatomic, readonly) BOOL isVPNActive;

/// Check if WireGuard app is installed
- (BOOL)isWireGuardInstalled;

/// Open App Store to WireGuard download page
- (void)openWireGuardInAppStore;

/// Generate WireGuard configuration for loopback VPN
- (NSString *)generateLoopbackConfiguration;

/// Open WireGuard with the loopback configuration
/// This will prompt user to import the tunnel configuration
- (void)openWireGuardWithConfiguration;

/// Copy configuration to pasteboard for manual import
- (void)copyConfigurationToPasteboard;

/// Save configuration file to Documents folder (accessible via Files app)
/// Returns the file path, or nil on failure
- (nullable NSString *)saveConfigurationToDocuments;

/// Get the URL of the saved configuration file
- (NSURL *)configurationFileURL;

/// Check if HIAH VPN setup has been completed by user
- (BOOL)isHIAHVPNConfigured;

/// Mark setup as completed (called when user finishes setup wizard)
- (void)markSetupCompleted;

/// Reset setup state (for re-running setup wizard)
- (void)resetSetup;

#pragma mark - EM Proxy Control

/// Start the em_proxy loopback server (required for JIT)
/// Returns YES on success, NO on failure
- (BOOL)startEMProxy;

/// Stop the em_proxy server
- (void)stopEMProxy;

/// Check if em_proxy is currently running
- (BOOL)isEMProxyRunning;

/// Verify full VPN connection (em_proxy + WireGuard)
/// Returns YES if both em_proxy is running and WireGuard is connected through it
- (BOOL)verifyFullVPNConnection;

#pragma mark - VPN Status Monitoring

/// Start monitoring VPN status
- (void)startMonitoringVPNStatus;

/// Stop monitoring VPN status
- (void)stopMonitoringVPNStatus;

/// Refresh VPN status manually
- (void)refreshVPNStatus;

@end

NS_ASSUME_NONNULL_END

