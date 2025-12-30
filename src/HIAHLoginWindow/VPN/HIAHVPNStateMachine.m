/**
 * HIAHVPNStateMachine.m
 * Declarative state machine implementation
 *
 * Copyright (c) 2025 Alex Spaulding - AGPLv3
 */

#import "HIAHVPNStateMachine.h"
#import "EMProxyBridge.h"
#import "../../HIAHDesktop/HIAHLogging.h"
#import <UIKit/UIKit.h>
#import <ifaddrs.h>
#import <net/if.h>

NSNotificationName const HIAHVPNStateDidChangeNotification = @"HIAHVPNStateDidChange";
NSString * const HIAHVPNPreviousStateKey = @"previousState";

// UserDefaults key for setup completion
static NSString * const kSetupCompleteKey = @"HIAHVPNSetupComplete.v2";

// WireGuard config constants
static NSString * const kPrivateKey = @"WAmgVYXkbT2bCtdcDwolI8Nqqb1OkMJ8XhkwqPGZJQg=";
static NSString * const kPublicKey = @"LH+SKYOmYVYm1QRXHZ/xwTdtKuNfmGK5CxcJC5N7B3c=";

#pragma mark - Transition Table

/// A transition entry: (fromState, event) -> toState
typedef struct {
    HIAHVPNState fromState;
    HIAHVPNEvent event;
    HIAHVPNState toState;
} HIAHVPNTransition;

/// The complete transition table - defines ALL valid state transitions
/// If a (state, event) pair is not in this table, the event is ignored
static const HIAHVPNTransition kTransitionTable[] = {
    // From Idle
    { HIAHVPNStateIdle,          HIAHVPNEventStart,           HIAHVPNStateStartingProxy },
    
    // From StartingProxy
    { HIAHVPNStateStartingProxy, HIAHVPNEventProxyStarted,    HIAHVPNStateProxyReady },
    { HIAHVPNStateStartingProxy, HIAHVPNEventProxyFailed,     HIAHVPNStateError },
    { HIAHVPNStateStartingProxy, HIAHVPNEventStop,            HIAHVPNStateIdle },
    
    // From ProxyReady
    { HIAHVPNStateProxyReady,    HIAHVPNEventVPNConnected,    HIAHVPNStateConnected },
    { HIAHVPNStateProxyReady,    HIAHVPNEventStop,            HIAHVPNStateIdle },
    
    // From Connected
    { HIAHVPNStateConnected,     HIAHVPNEventVPNDisconnected, HIAHVPNStateProxyReady },
    { HIAHVPNStateConnected,     HIAHVPNEventProxyFailed,     HIAHVPNStateError },
    { HIAHVPNStateConnected,     HIAHVPNEventStop,            HIAHVPNStateIdle },
    
    // From Error
    { HIAHVPNStateError,         HIAHVPNEventRetry,           HIAHVPNStateStartingProxy },
    { HIAHVPNStateError,         HIAHVPNEventStop,            HIAHVPNStateIdle },
};

static const size_t kTransitionCount = sizeof(kTransitionTable) / sizeof(kTransitionTable[0]);

#pragma mark - Implementation

@interface HIAHVPNStateMachine ()
@property (nonatomic, assign) HIAHVPNState state;
@property (nonatomic, strong, nullable) NSError *lastError;
@property (nonatomic, strong) NSTimer *monitorTimer;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@end

@implementation HIAHVPNStateMachine

#pragma mark - Singleton

+ (instancetype)shared {
    static HIAHVPNStateMachine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _state = HIAHVPNStateIdle;
        _lastError = nil;
        _stateQueue = dispatch_queue_create("com.aspauldingcode.HIAHVPN.state", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Public Properties

- (NSString *)stateName {
    switch (self.state) {
        case HIAHVPNStateIdle:          return @"Idle";
        case HIAHVPNStateStartingProxy: return @"StartingProxy";
        case HIAHVPNStateProxyReady:    return @"ProxyReady";
        case HIAHVPNStateConnected:     return @"Connected";
        case HIAHVPNStateError:         return @"Error";
    }
    return @"Unknown";
}

- (BOOL)isConnected {
    return self.state == HIAHVPNStateConnected;
}

- (BOOL)isSetupComplete {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSetupCompleteKey];
}

#pragma mark - State Transitions

- (BOOL)sendEvent:(HIAHVPNEvent)event {
    return [self sendEvent:event error:nil];
}

- (BOOL)sendEvent:(HIAHVPNEvent)event error:(NSError *)error {
    __block BOOL transitioned = NO;
    __block HIAHVPNState oldState;
    __block HIAHVPNState newState;
    
    dispatch_sync(self.stateQueue, ^{
        oldState = self.state;
        
        // Look up transition in table
        for (size_t i = 0; i < kTransitionCount; i++) {
            if (kTransitionTable[i].fromState == oldState && 
                kTransitionTable[i].event == event) {
                newState = kTransitionTable[i].toState;
                transitioned = YES;
                break;
            }
        }
        
        if (transitioned) {
            self.state = newState;
            if (error) {
                self.lastError = error;
            } else if (newState != HIAHVPNStateError) {
                self.lastError = nil;
            }
        }
    });
    
    if (transitioned) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"[%@] → %@ → [%@]",
                  [self nameForState:oldState],
                  [self nameForEvent:event],
                  [self nameForState:newState]);
        
        // Execute actions for this transition (on main thread)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self executeActionsForTransitionFrom:oldState to:newState];
            
            // Post notification
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:HIAHVPNStateDidChangeNotification
                              object:self
                            userInfo:@{HIAHVPNPreviousStateKey: @(oldState)}];
        });
    } else {
        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"Event %@ ignored in state %@",
                  [self nameForEvent:event], [self nameForState:oldState]);
    }
    
    return transitioned;
}

#pragma mark - Actions

/// Execute side effects for a state transition
/// This is the ONLY place where actions happen
- (void)executeActionsForTransitionFrom:(HIAHVPNState)from to:(HIAHVPNState)to {
    switch (to) {
        case HIAHVPNStateIdle:
            [self actionStopEverything];
            break;
            
        case HIAHVPNStateStartingProxy:
            [self actionStartProxy];
            break;
            
        case HIAHVPNStateProxyReady:
            [self actionStartMonitoring];
            [self actionUpdateBypassCoordinator:NO];
            break;
            
        case HIAHVPNStateConnected:
            [self actionUpdateBypassCoordinator:YES];
            break;
            
        case HIAHVPNStateError:
            [self actionStopMonitoring];
            break;
    }
}

- (void)actionStartProxy {
    // Start em_proxy asynchronously, send event when done
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int result = [EMProxyBridge startVPNWithBindAddress:@"127.0.0.1:65399"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (result == 0) {
                [self sendEvent:HIAHVPNEventProxyStarted];
            } else {
                NSError *error = [NSError errorWithDomain:@"HIAHVPNStateMachine"
                                                     code:result
                                                 userInfo:@{NSLocalizedDescriptionKey: @"em_proxy failed to start"}];
                [self sendEvent:HIAHVPNEventProxyFailed error:error];
            }
        });
    });
}

- (void)actionStopEverything {
    [self actionStopMonitoring];
    [EMProxyBridge stopVPN];
    [self actionUpdateBypassCoordinator:NO];
}

- (void)actionStartMonitoring {
    [self actionStopMonitoring];
    
    // Check VPN status every 5 seconds (reduced frequency since test_emotional_damage
    // can take up to 1 second to complete)
    self.monitorTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                         target:self
                                                       selector:@selector(checkVPNStatus)
                                                       userInfo:nil
                                                        repeats:YES];
    // Check immediately
    [self checkVPNStatus];
}

- (void)actionStopMonitoring {
    [self.monitorTimer invalidate];
    self.monitorTimer = nil;
}

- (void)checkVPNStatus {
    BOOL hiahVPNConnected = [self detectHIAHVPNConnected];
    
    // Send appropriate event based on current state and VPN status
    if (self.state == HIAHVPNStateProxyReady && hiahVPNConnected) {
        [self sendEvent:HIAHVPNEventVPNConnected];
    } else if (self.state == HIAHVPNStateConnected && !hiahVPNConnected) {
        [self sendEvent:HIAHVPNEventVPNDisconnected];
    }
    // In other states, VPN status changes are not relevant
    
    // Always update the bypass coordinator so extension gets fresh status
    [self actionUpdateBypassCoordinator:hiahVPNConnected];
}

/// Detects if HIAH VPN is specifically connected by testing em_proxy.
/// We can't just check for utun interfaces because the user might have
/// other VPNs running. The only way to verify HIAH VPN is to test if
/// em_proxy can successfully communicate with WireGuard.
- (BOOL)detectHIAHVPNConnected {
    // First check: em_proxy must be running
    if (![EMProxyBridge isRunning]) {
        return NO;
    }
    
    // Second check: em_proxy test - this verifies WireGuard is connected
    // to our em_proxy loopback. This is the ONLY reliable way to verify
    // the HIAH VPN specifically vs any other VPN the user might have.
    int testResult = [EMProxyBridge testVPNWithTimeout:1000]; // 1 second timeout
    BOOL connected = (testResult == 0);
    
    if (connected) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"HIAH VPN connection verified via em_proxy");
    }
    
    return connected;
}

- (void)actionUpdateBypassCoordinator:(BOOL)connected {
    Class coordClass = NSClassFromString(@"HIAHBypassCoordinator");
    if (!coordClass) return;
    
    SEL sharedSel = NSSelectorFromString(@"sharedCoordinator");
    if (![coordClass respondsToSelector:sharedSel]) return;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id coordinator = [coordClass performSelector:sharedSel];
#pragma clang diagnostic pop
    if (!coordinator) return;
    
    SEL updateSel = NSSelectorFromString(@"updateVPNStatus:");
    if (![coordinator respondsToSelector:updateSel]) return;
    
    NSMethodSignature *sig = [coordinator methodSignatureForSelector:updateSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:coordinator];
    [inv setSelector:updateSel];
    [inv setArgument:&connected atIndex:2];
    [inv invoke];
}

#pragma mark - Setup

- (void)markSetupComplete {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kSetupCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Setup marked complete");
}

- (void)resetSetup {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kSetupCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Setup reset");
}

#pragma mark - Config Generation

- (NSString *)generateConfig {
    return [NSString stringWithFormat:
        @"[Interface]\n"
        @"PrivateKey = %@\n"
        @"Address = 10.7.0.2/32\n"
        @"DNS = 8.8.8.8\n"
        @"\n"
        @"[Peer]\n"
        @"PublicKey = %@\n"
        @"AllowedIPs = 0.0.0.0/0, ::/0\n"
        @"Endpoint = 127.0.0.1:65399\n"
        @"PersistentKeepalive = 25\n",
        kPrivateKey, kPublicKey];
}

- (NSString *)saveConfigToDocuments {
    NSString *config = [self generateConfig];
    NSString *path = [[self configFileURL] path];
    
    NSError *error;
    if ([config writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Config saved: %@", path);
        return path;
    }
    HIAHLogEx(HIAH_LOG_ERROR, @"VPN", @"Failed to save config: %@", error);
    return nil;
}

- (void)copyConfigToClipboard {
    [[UIPasteboard generalPasteboard] setString:[self generateConfig]];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Config copied to clipboard");
}

- (NSURL *)configFileURL {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [paths.firstObject stringByAppendingPathComponent:@"HIAH-VPN.conf"];
    return [NSURL fileURLWithPath:path];
}

#pragma mark - Debug Helpers

- (NSString *)nameForState:(HIAHVPNState)state {
    switch (state) {
        case HIAHVPNStateIdle:          return @"Idle";
        case HIAHVPNStateStartingProxy: return @"StartingProxy";
        case HIAHVPNStateProxyReady:    return @"ProxyReady";
        case HIAHVPNStateConnected:     return @"Connected";
        case HIAHVPNStateError:         return @"Error";
    }
    return @"?";
}

- (NSString *)nameForEvent:(HIAHVPNEvent)event {
    switch (event) {
        case HIAHVPNEventStart:           return @"Start";
        case HIAHVPNEventProxyStarted:    return @"ProxyStarted";
        case HIAHVPNEventProxyFailed:     return @"ProxyFailed";
        case HIAHVPNEventVPNConnected:    return @"VPNConnected";
        case HIAHVPNEventVPNDisconnected: return @"VPNDisconnected";
        case HIAHVPNEventStop:            return @"Stop";
        case HIAHVPNEventRetry:           return @"Retry";
    }
    return @"?";
}

- (NSString *)validTransitionsDescription {
    NSMutableArray *transitions = [NSMutableArray array];
    HIAHVPNState current = self.state;
    
    for (size_t i = 0; i < kTransitionCount; i++) {
        if (kTransitionTable[i].fromState == current) {
            [transitions addObject:[NSString stringWithFormat:@"%@ → %@",
                [self nameForEvent:kTransitionTable[i].event],
                [self nameForState:kTransitionTable[i].toState]]];
        }
    }
    
    return [NSString stringWithFormat:@"[%@] can: %@", 
            [self nameForState:current],
            [transitions componentsJoinedByString:@", "]];
}

@end

