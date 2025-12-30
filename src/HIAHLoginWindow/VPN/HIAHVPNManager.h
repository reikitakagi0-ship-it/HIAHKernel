/**
 * HIAHVPNManager.h
 * HIAH LoginWindow - VPN Management
 *
 * Manages VPN connectivity using WireGuard (App Store) for JIT enablement.
 * This approach works without a paid Apple Developer account.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>
#import "WireGuard/HIAHWireGuardManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface HIAHVPNManager : NSObject

+ (instancetype)sharedManager;

/// Whether VPN is currently active
@property (nonatomic, readonly) BOOL isVPNActive;

/// Set up VPN manager
- (void)setupVPNManager;

/// Start VPN (opens WireGuard for manual activation)
- (void)startVPNWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completion;

/// Stop VPN (user must do this manually in WireGuard)
- (void)stopVPN;

#pragma mark - WireGuard Integration

/// Check if WireGuard is installed
- (BOOL)isWireGuardInstalled;

/// Current WireGuard status
- (HIAHWireGuardStatus)wireGuardStatus;

/// Open WireGuard app with configuration
- (void)openWireGuardApp;

/// Open App Store to install WireGuard
- (void)installWireGuard;

@end

NS_ASSUME_NONNULL_END
