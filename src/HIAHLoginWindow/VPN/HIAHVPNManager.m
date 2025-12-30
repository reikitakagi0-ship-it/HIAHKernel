/**
 * HIAHVPNManager.m
 * HIAH LoginWindow - VPN Management
 *
 * Manages VPN connectivity using WireGuard (App Store) for JIT enablement.
 * This approach works without a paid Apple Developer account.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHVPNManager.h"
#import "WireGuard/HIAHWireGuardManager.h"
#import "../../HIAHDesktop/HIAHLogging.h"
#import <Foundation/Foundation.h>

@interface HIAHVPNManager ()

@property (nonatomic, assign, readwrite) BOOL isVPNActive;
@property (nonatomic, strong) HIAHWireGuardManager *wireGuardManager;

@end

@implementation HIAHVPNManager

+ (instancetype)sharedManager {
    static HIAHVPNManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isVPNActive = NO;
        _wireGuardManager = [HIAHWireGuardManager sharedManager];
        [self setupVPNManager];
    }
    return self;
}

- (void)setupVPNManager {
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Setting up VPN manager (WireGuard mode)...");
    
    // Start monitoring WireGuard VPN status
    [self.wireGuardManager startMonitoringVPNStatus];
    
    // Check if WireGuard is installed
    if ([self.wireGuardManager isWireGuardInstalled]) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"WireGuard is installed");
    } else {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"WireGuard not installed - VPN/JIT will not work");
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Install WireGuard from App Store for JIT support");
    }
    
    // Observe WireGuard status changes
    [NSTimer scheduledTimerWithTimeInterval:2.0
                                     target:self
                                   selector:@selector(updateVPNStatus)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)updateVPNStatus {
    BOOL wasActive = self.isVPNActive;
    self.isVPNActive = self.wireGuardManager.isVPNActive;
    
    if (wasActive != self.isVPNActive) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Status changed: %@",
                 self.isVPNActive ? @"CONNECTED" : @"DISCONNECTED");
        
        // NOTE: Do NOT update bypass coordinator here!
        // HIAHVPNStateMachine is the single source of truth and handles
        // bypass coordinator updates. Updating here causes race conditions.
    }
}

- (void)startVPNWithCompletion:(void (^)(NSError * _Nullable error))completion {
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Starting VPN (WireGuard mode)...");
    
    // Check if WireGuard is installed
    if (![self.wireGuardManager isWireGuardInstalled]) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"WireGuard not installed - user should use setup wizard");
        
        // Don't automatically open App Store - let the setup wizard handle user interaction
        // The WireGuard setup flow will guide the user through installation
        
        if (completion) {
            completion([NSError errorWithDomain:@"VPNManager"
                                           code:-1
                                       userInfo:@{
                NSLocalizedDescriptionKey: @"WireGuard not installed. Use the WireGuard setup wizard to install and configure."
            }]);
        }
        return;
    }
    
    // Check if VPN is already active
    if (self.wireGuardManager.isVPNActive) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"WireGuard VPN is already active");
        self.isVPNActive = YES;
        if (completion) {
            completion(nil);
        }
        return;
    }
    
    // Open WireGuard with configuration
    // User will need to manually activate the tunnel
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Opening WireGuard for tunnel activation...");
    [self.wireGuardManager openWireGuardWithConfiguration];
    
    // Copy configuration to pasteboard as backup
    [self.wireGuardManager copyConfigurationToPasteboard];
    
    // Return success - user needs to manually enable the tunnel in WireGuard
    if (completion) {
        completion([NSError errorWithDomain:@"VPNManager"
                                       code:0
                                   userInfo:@{
            NSLocalizedDescriptionKey: @"Please enable the HIAH tunnel in WireGuard app. Configuration has been copied to clipboard."
        }]);
    }
}

- (void)stopVPN {
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"To stop VPN, disable the tunnel in WireGuard app");
    // Cannot programmatically stop WireGuard - user must do it manually
}

#pragma mark - WireGuard Status

- (BOOL)isWireGuardInstalled {
    return [self.wireGuardManager isWireGuardInstalled];
}

- (HIAHWireGuardStatus)wireGuardStatus {
    return self.wireGuardManager.status;
}

- (void)openWireGuardApp {
    [self.wireGuardManager openWireGuardWithConfiguration];
}

- (void)installWireGuard {
    [self.wireGuardManager openWireGuardInAppStore];
}

@end
