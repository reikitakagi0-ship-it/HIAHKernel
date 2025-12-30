/**
 * HIAHJITManager.h
 * HIAH LoginWindow - JIT Enablement Manager
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HIAHJITManager : NSObject

+ (instancetype)sharedManager;

- (void)enableJITForPID:(pid_t)pid
             completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

- (void)mountDeveloperDiskImageWithCompletion:
    (void (^)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
