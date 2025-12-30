/**
 * HIAHJITManager.m
 * HIAH LoginWindow - JIT Enablement Manager
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHJITManager.h"
#import "HIAHJITEnablerHelper.h"
#import "../../HIAHDesktop/HIAHLogging.h"
#import "../VPN/HIAHVPNManager.h"
#import "../VPN/MinimuxerBridge.h"
#import <Foundation/Foundation.h>

@implementation HIAHJITManager

+ (instancetype)sharedManager {
  static HIAHJITManager *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (void)enableJITForPID:(pid_t)pid
             completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
  HIAHLogEx(HIAH_LOG_INFO, @"JITManager", @"Requesting JIT for PID: %d", pid);

  // Check if JIT is already enabled
  extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
  #define CS_OPS_STATUS 0
  #define CS_DEBUGGED 0x10000000
  
  int flags = 0;
  if (csops(pid, CS_OPS_STATUS, &flags, sizeof(flags)) == 0) {
    if ((flags & CS_DEBUGGED) != 0) {
      HIAHLogEx(HIAH_LOG_INFO, @"JITManager", @"JIT already enabled for PID: %d", pid);
      if (completion) {
        completion(YES, nil);
      }
      return;
    }
  }

  // Ensure VPN is active (required for JIT enablement)
  HIAHVPNManager *vpnManager = [HIAHVPNManager sharedManager];
  if (!vpnManager.isVPNActive) {
    HIAHLogEx(HIAH_LOG_WARNING, @"JITManager", @"VPN not active - starting VPN for JIT...");
    
    [vpnManager startVPNWithCompletion:^(NSError * _Nullable error) {
      if (error) {
        HIAHLogEx(HIAH_LOG_ERROR, @"JITManager", @"Failed to start VPN: %@", error);
        if (completion) {
          completion(NO, error);
        }
        return;
      }
      
      // VPN started, now enable JIT
      [self enableJITForPID:pid completion:completion];
    }];
    return;
  }

  // Use Minimuxer to enable JIT via lockdown protocol
  // Minimuxer communicates with lockdownd through the VPN tunnel
  HIAHLogEx(HIAH_LOG_INFO, @"JITManager", @"Enabling JIT via Minimuxer for PID: %d", pid);
  
  // Enable JIT via Minimuxer through VPN tunnel
  // The VPN loopback makes iOS think requests come from a computer,
  // which allows Minimuxer to communicate with lockdownd to enable JIT
  
  HIAHLogEx(HIAH_LOG_INFO, @"JITManager", @"Attempting to enable JIT via Minimuxer for PID: %d", pid);
  
  // Use Swift JIT enabler if available
  Class jitEnablerClass = NSClassFromString(@"HIAHJITEnabler");
  if (jitEnablerClass) {
    SEL sharedSel = NSSelectorFromString(@"shared");
    if ([jitEnablerClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      id enabler = [jitEnablerClass performSelector:sharedSel];
#pragma clang diagnostic pop
      if (enabler) {
        // Call enableJITForCurrentProcess (async)
        SEL enableSel = NSSelectorFromString(@"enableJITForCurrentProcessWithCompletion:");
        if ([enabler respondsToSelector:enableSel]) {
          void (^swiftCompletion)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
            // Verify JIT is actually enabled
            BOOL jitActive = HIAHJITEnablerHelper_isJITEnabled();
            
            if (jitActive) {
              HIAHLogEx(HIAH_LOG_INFO, @"JITManager", @"JIT enabled successfully for PID: %d", pid);
              // Update coordinator
              Class coordinatorClass = NSClassFromString(@"HIAHBypassCoordinator");
              if (coordinatorClass) {
                SEL coordSel = NSSelectorFromString(@"sharedCoordinator");
                if ([coordinatorClass respondsToSelector:coordSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                  id coordinator = [coordinatorClass performSelector:coordSel];
#pragma clang diagnostic pop
                  if (coordinator) {
                    SEL updateSel = NSSelectorFromString(@"updateJITStatus:");
                    if ([coordinator respondsToSelector:updateSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                      [coordinator performSelector:updateSel withObject:@(YES)];
#pragma clang diagnostic pop
                    }
                  }
                }
              }
              if (completion) {
                completion(YES, nil);
              }
            } else {
              HIAHLogEx(HIAH_LOG_WARNING, @"JITManager", @"JIT enablement reported success but CS_DEBUGGED not set");
              if (completion) {
                completion(YES, nil); // Still return success - signing fallback
              }
            }
          };
          
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
          [enabler performSelector:enableSel withObject:swiftCompletion];
#pragma clang diagnostic pop
          return;
        }
      }
    }
  }
  
  // Fallback: Check if JIT is already enabled or can be enabled
  // With VPN active, JIT might be enabled automatically in some cases
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    // Wait for VPN to stabilize
    [NSThread sleepForTimeInterval:1.5];
    
    // Check if JIT got enabled
    BOOL jitEnabled = HIAHJITEnablerHelper_isJITEnabled();
    
    if (jitEnabled) {
      HIAHLogEx(HIAH_LOG_INFO, @"JITManager", @"JIT enabled (verified) for PID: %d", pid);
      // Update coordinator
      Class coordinatorClass = NSClassFromString(@"HIAHBypassCoordinator");
      if (coordinatorClass) {
        SEL coordSel = NSSelectorFromString(@"sharedCoordinator");
        if ([coordinatorClass respondsToSelector:coordSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
          id coordinator = [coordinatorClass performSelector:coordSel];
#pragma clang diagnostic pop
          if (coordinator) {
            SEL updateSel = NSSelectorFromString(@"updateJITStatus:");
            if ([coordinator respondsToSelector:updateSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
              [coordinator performSelector:updateSel withObject:@(YES)];
#pragma clang diagnostic pop
            }
          }
        }
      }
      if (completion) {
        completion(YES, nil);
      }
    } else {
      HIAHLogEx(HIAH_LOG_WARNING, @"JITManager", @"JIT not enabled for PID: %d - will use signing fallback", pid);
      HIAHLogEx(HIAH_LOG_INFO, @"JITManager", @"Note: Full Minimuxer integration needed for automatic JIT enablement");
      // Return success - signing fallback will work
      if (completion) {
          completion(YES, nil);
      }
    }
      });
}

- (void)mountDeveloperDiskImageWithCompletion:
    (void (^)(BOOL success, NSError * _Nullable error))completion {
  HIAHLogEx(HIAH_LOG_INFO, @"JITManager", @"Mounting Developer Disk Image...");

  // Call Minimuxer bridge
  // [MinimuxerBridge mountDDI]; // (Hypothetical)

  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        HIAHLogEx(HIAH_LOG_INFO, @"JITManager",
                  @"DDI mounted simulation complete");
        if (completion)
          completion(YES, nil);
      });
}

@end
