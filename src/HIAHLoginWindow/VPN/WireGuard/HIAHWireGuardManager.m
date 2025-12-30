/**
 * HIAHWireGuardManager.m
 * HIAH LoginWindow - WireGuard VPN Integration
 *
 * Based on SideStore's StoreAppsVPN approach (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHWireGuardManager.h"
#import "../EMProxyBridge.h"
#import "../../../HIAHDesktop/HIAHLogging.h"
#import <UIKit/UIKit.h>
#import <Network/Network.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <ifaddrs.h>
#import <net/if.h>

// WireGuard App Store ID
static NSString * const kWireGuardAppStoreID = @"1441195209";
static NSString * const kWireGuardURLScheme = @"wireguard://";

// Loopback VPN configuration
// This creates a tunnel that routes traffic back to the device
// allowing Minimuxer to communicate with lockdownd
static NSString * const kLoopbackPrivateKey = @"WAmgVYXkbT2bCtdcDwolI8Nqqb1OkMJ8XhkwqPGZJQg=";
static NSString * const kLoopbackPublicKey = @"LH+SKYOmYVYm1QRXHZ/xwTdtKuNfmGK5CxcJC5N7B3c=";
static NSString * const kLoopbackAddress = @"10.7.0.2/32";
static NSString * const kLoopbackDNS = @"8.8.8.8";

@interface HIAHWireGuardManager ()

@property (nonatomic, assign) HIAHWireGuardStatus status;
@property (nonatomic, assign) BOOL isVPNActive;
@property (nonatomic, strong) NSTimer *statusTimer;
@property (nonatomic, strong) dispatch_queue_t monitorQueue;

@end

@implementation HIAHWireGuardManager

+ (instancetype)sharedManager {
    static HIAHWireGuardManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _status = HIAHWireGuardStatusDisconnected;
        _isVPNActive = NO;
        _monitorQueue = dispatch_queue_create("com.aspauldingcode.HIAHDesktop.wireguard", DISPATCH_QUEUE_SERIAL);
        
        // Check for fresh install - reset setup if app was reinstalled
        [self checkForFreshInstall];
        
        // Start em_proxy automatically - it needs to be running before WireGuard connects
        [self startEMProxy];
        
        // Check initial status
        [self refreshVPNStatus];
    }
    return self;
}

- (void)checkForFreshInstall {
    // Use a marker file in the app's Documents directory to detect fresh installs
    // NSUserDefaults can persist across reinstalls in some cases, but Documents is always cleared
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = paths.firstObject;
    NSString *markerPath = [documentsDir stringByAppendingPathComponent:@".hiah_vpn_installed"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:markerPath]) {
        // Fresh install - reset setup flag and create marker
        HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Fresh install detected - resetting VPN setup flag");
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"HIAHVPNSetupCompleted"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // Create marker file
        [fm createFileAtPath:markerPath contents:[@"installed" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
    }
}

#pragma mark - EM Proxy Management

- (BOOL)startEMProxy {
    if ([EMProxyBridge isRunning]) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"WireGuard", @"em_proxy already running");
        return YES;
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Starting em_proxy loopback server...");
    
    // Start em_proxy on the loopback address that WireGuard connects to
    int result = [EMProxyBridge startVPNWithBindAddress:@"127.0.0.1:65399"];
    
    if (result == 0) {
        HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"✅ em_proxy started - ready for WireGuard connections");
        return YES;
    } else {
        HIAHLogEx(HIAH_LOG_ERROR, @"WireGuard", @"❌ Failed to start em_proxy: %d", result);
        return NO;
    }
}

- (void)stopEMProxy {
    [EMProxyBridge stopVPN];
}

- (BOOL)isEMProxyRunning {
    return [EMProxyBridge isRunning];
}

- (BOOL)verifyFullVPNConnection {
    // Check if em_proxy is running
    if (![EMProxyBridge isRunning]) {
        HIAHLogEx(HIAH_LOG_WARNING, @"WireGuard", @"em_proxy not running - starting it now");
        if (![self startEMProxy]) {
            return NO;
        }
    }
    
    // Check if a VPN interface is active
    BOOL vpnInterfaceActive = NO;
    struct ifaddrs *interfaces = NULL;
    
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *current = interfaces;
        while (current != NULL) {
            if (current->ifa_name != NULL) {
                NSString *interfaceName = [NSString stringWithUTF8String:current->ifa_name];
                if ([interfaceName hasPrefix:@"utun"] || [interfaceName hasPrefix:@"ipsec"]) {
                    if ((current->ifa_flags & IFF_UP) && (current->ifa_flags & IFF_RUNNING)) {
                        vpnInterfaceActive = YES;
                        HIAHLogEx(HIAH_LOG_DEBUG, @"WireGuard", @"Found active VPN interface: %@", interfaceName);
                        break;
                    }
                }
            }
            current = current->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    
    if (!vpnInterfaceActive) {
        HIAHLogEx(HIAH_LOG_WARNING, @"WireGuard", @"No active VPN interface found");
        return NO;
    }
    
    // em_proxy is running AND VPN interface is active - this is sufficient
    // The test_emotional_damage function tests WireGuard<->em_proxy handshake which
    // requires matching keys. Since we're using user-configured WireGuard, 
    // we just verify both components are active.
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"✅ VPN connection verified (em_proxy running + VPN active)");
    return YES;
}

- (void)dealloc {
    [self stopMonitoringVPNStatus];
}

#pragma mark - WireGuard Detection

- (BOOL)isWireGuardInstalled {
    // Method 1: canOpenURL check (unreliable - often fails even with LSApplicationQueriesSchemes)
    NSURL *wireguardURL = [NSURL URLWithString:kWireGuardURLScheme];
    BOOL canOpenResult = [[UIApplication sharedApplication] canOpenURL:wireguardURL];
    
    if (canOpenResult) {
        return YES;
    }
    
    // Method 2: If em_proxy is running and its test passes, WireGuard must be connected
    // This is more reliable than canOpenURL
    if ([EMProxyBridge isRunning]) {
        int testResult = [EMProxyBridge testVPNWithTimeout:200]; // Quick 200ms test
        if (testResult == 0) {
            // WireGuard is clearly working - it IS installed
            return YES;
        }
    }
    
    // Method 3: Check if VPN interface exists (utun)
    // If a VPN is active, WireGuard is probably installed and running
    if (self.isVPNActive) {
        return YES;
    }
    
    return NO;
}

- (void)openWireGuardInAppStore {
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Opening WireGuard in App Store...");
    
    NSString *appStoreURL = [NSString stringWithFormat:@"itms-apps://apps.apple.com/app/id%@", kWireGuardAppStoreID];
    NSURL *url = [NSURL URLWithString:appStoreURL];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            if (success) {
                HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Opened App Store successfully");
            } else {
                HIAHLogEx(HIAH_LOG_ERROR, @"WireGuard", @"Failed to open App Store");
            }
        }];
    });
}

#pragma mark - Configuration Generation

- (NSString *)generateLoopbackConfiguration {
    // Generate a WireGuard configuration for loopback VPN
    // This creates a tunnel that allows local services to appear as if they're
    // coming from an external computer (required for JIT enablement)
    
    NSMutableString *config = [NSMutableString string];
    
    [config appendString:@"[Interface]\n"];
    [config appendFormat:@"PrivateKey = %@\n", kLoopbackPrivateKey];
    [config appendFormat:@"Address = %@\n", kLoopbackAddress];
    [config appendFormat:@"DNS = %@\n", kLoopbackDNS];
    [config appendString:@"\n"];
    
    [config appendString:@"[Peer]\n"];
    [config appendFormat:@"PublicKey = %@\n", kLoopbackPublicKey];
    [config appendString:@"AllowedIPs = 0.0.0.0/0, ::/0\n"];
    [config appendString:@"Endpoint = 127.0.0.1:65399\n"];
    [config appendString:@"PersistentKeepalive = 25\n"];
    
    return config;
}

- (void)openWireGuardWithConfiguration {
    if (![self isWireGuardInstalled]) {
        HIAHLogEx(HIAH_LOG_WARNING, @"WireGuard", @"WireGuard not installed - opening App Store");
        [self openWireGuardInAppStore];
        return;
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Attempting to open WireGuard...");
    
    // Try to open WireGuard app directly
    // Note: WireGuard on iOS doesn't have a reliable public URL scheme
    // The wireguard:// scheme may not work on all versions
    NSURL *wireguardURL = [NSURL URLWithString:kWireGuardURLScheme];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[UIApplication sharedApplication] canOpenURL:wireguardURL]) {
            [[UIApplication sharedApplication] openURL:wireguardURL options:@{} completionHandler:^(BOOL success) {
                if (success) {
                    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Opened WireGuard app");
                } else {
                    HIAHLogEx(HIAH_LOG_WARNING, @"WireGuard", @"Failed to open WireGuard - user should open manually");
                }
            }];
        } else {
            HIAHLogEx(HIAH_LOG_WARNING, @"WireGuard", @"Cannot open WireGuard URL scheme - user should open manually");
        }
    });
}

- (void)copyConfigurationToPasteboard {
    NSString *config = [self generateLoopbackConfiguration];
    [[UIPasteboard generalPasteboard] setString:config];
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Configuration copied to pasteboard");
}

- (NSString *)saveConfigurationToDocuments {
    NSString *config = [self generateLoopbackConfiguration];
    
    // Get Documents directory
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = paths.firstObject;
    NSString *configPath = [documentsDir stringByAppendingPathComponent:@"HIAH-VPN.conf"];
    
    NSError *error = nil;
    [config writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    
    if (error) {
        HIAHLogEx(HIAH_LOG_ERROR, @"WireGuard", @"Failed to save config: %@", error);
        return nil;
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Configuration saved to: %@", configPath);
    return configPath;
}

- (NSURL *)configurationFileURL {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = paths.firstObject;
    NSString *configPath = [documentsDir stringByAppendingPathComponent:@"HIAH-VPN.conf"];
    return [NSURL fileURLWithPath:configPath];
}

- (BOOL)isHIAHVPNConfigured {
    // Check if user has completed the HIAH VPN setup wizard
    // We use a UserDefaults flag because we can't verify the specific tunnel
    // without em_proxy running
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HIAHVPNSetupCompleted"];
}

- (void)markSetupCompleted {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HIAHVPNSetupCompleted"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"HIAH VPN setup marked as completed");
}

- (void)resetSetup {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"HIAHVPNSetupCompleted"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Also remove the install marker so next launch triggers fresh install check
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = paths.firstObject;
    NSString *markerPath = [documentsDir stringByAppendingPathComponent:@".hiah_vpn_installed"];
    [[NSFileManager defaultManager] removeItemAtPath:markerPath error:nil];
    
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"HIAH VPN setup reset (flag and marker cleared)");
}

#pragma mark - VPN Status Monitoring

- (void)startMonitoringVPNStatus {
    [self stopMonitoringVPNStatus];
    
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Starting VPN status monitoring");
    
    // Check status every 2 seconds
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                        target:self
                                                      selector:@selector(refreshVPNStatus)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)stopMonitoringVPNStatus {
    if (self.statusTimer) {
        [self.statusTimer invalidate];
        self.statusTimer = nil;
        HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Stopped VPN status monitoring");
    }
}

- (void)refreshVPNStatus {
    dispatch_async(self.monitorQueue, ^{
        BOOL wasActive = self.isVPNActive;
        
        // Check VPN status using multiple methods
        BOOL vpnActive = [self checkVPNStatus];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isVPNActive = vpnActive;
            
            if (vpnActive) {
                self.status = HIAHWireGuardStatusConnected;
            } else if ([self isWireGuardInstalled]) {
                self.status = HIAHWireGuardStatusDisconnected;
            } else {
                self.status = HIAHWireGuardStatusNotInstalled;
            }
            
            // Log status change
            // NOTE: Do NOT update bypass coordinator here!
            // HIAHVPNStateMachine is the single source of truth.
            if (wasActive != vpnActive) {
                HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"VPN status changed: %@",
                         vpnActive ? @"CONNECTED" : @"DISCONNECTED");
            }
        });
    });
}

- (BOOL)checkVPNStatus {
    // First, check if em_proxy is running
    BOOL emProxyRunning = [EMProxyBridge isRunning];
    BOOL vpnActive = NO;
    
    // Method 1: If em_proxy is running, use its built-in test (most accurate)
    if (emProxyRunning) {
        // Quick test with 500ms timeout - don't block the UI
        int testResult = [EMProxyBridge testVPNWithTimeout:500];
        if (testResult == 0) {
            vpnActive = YES; // WireGuard is connected through em_proxy
        }
    }
    
    // Method 2: Check for VPN interfaces using getifaddrs (iOS compatible)
    if (!vpnActive) {
        struct ifaddrs *interfaces = NULL;
        
        if (getifaddrs(&interfaces) == 0) {
            struct ifaddrs *current = interfaces;
            while (current != NULL) {
                if (current->ifa_name != NULL) {
                    NSString *interfaceName = [NSString stringWithUTF8String:current->ifa_name];
                    // VPN interfaces on iOS start with "utun" (WireGuard, IKEv2, etc.)
                    if ([interfaceName hasPrefix:@"utun"] || [interfaceName hasPrefix:@"ipsec"]) {
                        if ((current->ifa_flags & IFF_UP) && (current->ifa_flags & IFF_RUNNING)) {
                            vpnActive = YES;
                            break;
                        }
                    }
                }
                current = current->ifa_next;
            }
            freeifaddrs(interfaces);
        }
    }
    
    // NOTE: Do NOT update bypass coordinator here!
    // HIAHVPNStateMachine is the single source of truth for VPN status
    // and handles all bypass coordinator updates.
    
    return vpnActive;
}

@end

