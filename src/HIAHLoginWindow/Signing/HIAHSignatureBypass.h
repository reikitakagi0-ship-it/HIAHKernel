/**
 * HIAHSignatureBypass.h
 * HIAH LoginWindow - Signature Verification Bypass Service
 *
 * Coordinates VPN, JIT, and dylib signing to bypass iOS signature verification.
 * Similar to SideStore's LiveProcess/LiveContainer approach.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Service that coordinates VPN + JIT + signing to bypass dylib signature verification
@interface HIAHSignatureBypass : NSObject

+ (instancetype)sharedBypass;

/// Whether the bypass system is ready (VPN active + JIT enabled)
@property (nonatomic, readonly) BOOL isReady;

/// Ensure VPN and JIT are active before loading dylibs
/// This must be called before any dlopen() of unsigned dylibs
- (void)ensureBypassReadyWithCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Sign a dylib with the user's certificate (fallback if JIT unavailable)
- (BOOL)signDylibAtPath:(NSString *)dylibPath error:(NSError **)error;

/// Prepare a binary for dlopen by ensuring it can be loaded
/// This handles patching, signing, and ensuring bypass is ready
- (void)prepareBinaryForDlopen:(NSString *)binaryPath
                     completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

