/**
 * MinimuxerBridge.h
 * HIAH LoginWindow - Minimuxer Objective-C Bridge
 *
 * Provides Objective-C interface to the Minimuxer Rust library
 * for device communication and JIT enablement via lockdownd.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MinimuxerStatus) {
    MinimuxerStatusNotStarted,      // Minimuxer not initialized
    MinimuxerStatusStarting,        // Starting up
    MinimuxerStatusReady,           // Ready for device communication
    MinimuxerStatusNoDevice,        // No device connected
    MinimuxerStatusNoPairingFile,   // Missing pairing file
    MinimuxerStatusError            // Error state
};

@interface MinimuxerBridge : NSObject

/// Current status of minimuxer
@property (class, readonly) MinimuxerStatus status;

/// Whether minimuxer is ready for operations
@property (class, readonly) BOOL isReady;

/// Last error message if status is error
@property (class, readonly, nullable) NSString *lastError;

#pragma mark - Lifecycle

/// Initialize minimuxer with the device pairing file.
/// @param pairingFilePath Path to the pairing file (typically from iTunes/Finder sync)
/// @param logPath Path where minimuxer should write logs (can be nil for no logging)
/// @return YES on success, NO on failure (check lastError)
+ (BOOL)startWithPairingFile:(NSString *)pairingFilePath
                     logPath:(nullable NSString *)logPath;

/// Start minimuxer with console logging enabled (for debugging)
+ (BOOL)startWithPairingFile:(NSString *)pairingFilePath
                     logPath:(nullable NSString *)logPath
                consoleLogging:(BOOL)enableConsoleLogging;

/// Stop minimuxer and release resources
+ (void)stop;

#pragma mark - Device Info

/// Fetch the connected device's UDID
/// @return UDID string or nil if no device connected
+ (nullable NSString *)fetchDeviceUDID;

/// Test if a device is connected and reachable
+ (BOOL)testDeviceConnection;

#pragma mark - JIT Enablement

/// Enable JIT (debugger) for an app by bundle ID.
/// This uses the debug server to attach/detach from the process,
/// which sets the CS_DEBUGGED flag enabling JIT compilation.
/// @param bundleID The bundle identifier of the app (e.g., "com.example.app")
/// @param error Out parameter for error details
/// @return YES if JIT was enabled successfully
+ (BOOL)enableJITForApp:(NSString *)bundleID
                  error:(NSError * _Nullable * _Nullable)error;

/// Attach debugger to a specific process ID.
/// This enables JIT for an already-running process.
/// @param pid Process ID to attach to
/// @param error Out parameter for error details
/// @return YES if attachment successful
+ (BOOL)attachDebuggerToPID:(pid_t)pid
                      error:(NSError * _Nullable * _Nullable)error;

#pragma mark - App Installation

/// Install an IPA file to the device.
/// @param bundleID The bundle ID for the app
/// @param ipaData Raw bytes of the IPA file
/// @param error Out parameter for error details
/// @return YES if installation successful
+ (BOOL)installIPAWithBundleID:(NSString *)bundleID
                       ipaData:(NSData *)ipaData
                         error:(NSError * _Nullable * _Nullable)error;

/// Remove an app from the device.
/// @param bundleID The bundle ID of the app to remove
/// @param error Out parameter for error details
/// @return YES if removal successful
+ (BOOL)removeApp:(NSString *)bundleID
            error:(NSError * _Nullable * _Nullable)error;

#pragma mark - Provisioning Profiles

/// Install a provisioning profile to the device.
/// @param profileData Raw bytes of the .mobileprovision file
/// @param error Out parameter for error details
/// @return YES if installation successful
+ (BOOL)installProvisioningProfile:(NSData *)profileData
                             error:(NSError * _Nullable * _Nullable)error;

/// Remove a provisioning profile from the device.
/// @param profileID UUID of the profile to remove
/// @param error Out parameter for error details
/// @return YES if removal successful
+ (BOOL)removeProvisioningProfile:(NSString *)profileID
                            error:(NSError * _Nullable * _Nullable)error;

#pragma mark - Pairing File

/// Get the default location for the pairing file
/// @return Path to the pairing file, or nil if not found
+ (nullable NSString *)defaultPairingFilePath;

/// Check if a pairing file exists at the default location
+ (BOOL)hasPairingFile;

@end

NS_ASSUME_NONNULL_END
