/**
 * HIAHBypassCoordinator.h
 * HIAH LoginWindow - Shared Bypass Status Coordinator
 *
 * Coordinates VPN/JIT status between main app and ProcessRunner extension
 * using App Group shared storage. This allows the extension to know when
 * bypass is ready without direct class access.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared coordinator for bypass status between main app and extension
@interface HIAHBypassCoordinator : NSObject

+ (instancetype)sharedCoordinator;

/// Whether VPN is currently active
@property (nonatomic, readonly) BOOL isVPNActive;

/// Whether JIT is currently enabled (CS_DEBUGGED flag set)
@property (nonatomic, readonly) BOOL isJITEnabled;

/// Whether bypass system is fully ready
@property (nonatomic, readonly) BOOL isBypassReady;

/// Update VPN status (called by main app)
- (void)updateVPNStatus:(BOOL)active;

/// Update JIT status (called by main app)
- (void)updateJITStatus:(BOOL)enabled;

/// Request bypass activation (called by extension)
/// Returns YES if bypass is ready, NO if needs activation
- (BOOL)requestBypassActivation;

/// Check if bypass is ready (non-blocking, reads from shared storage)
- (BOOL)checkBypassReady;

@end

NS_ASSUME_NONNULL_END

