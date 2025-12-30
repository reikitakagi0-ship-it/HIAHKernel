/**
 * HIAHWireGuardSetupViewController.h
 * HIAH LoginWindow - WireGuard Setup Guide
 *
 * Guides users through WireGuard installation and configuration
 * for enabling JIT and signature bypass features.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol HIAHWireGuardSetupDelegate <NSObject>
@optional
- (void)wireGuardSetupDidComplete;
- (void)wireGuardSetupDidSkip;
@end

typedef NS_ENUM(NSInteger, HIAHWireGuardSetupStep) {
    HIAHWireGuardSetupStepInstall = 0,
    HIAHWireGuardSetupStepConfigure,
    HIAHWireGuardSetupStepActivate,
    HIAHWireGuardSetupStepComplete
};

@interface HIAHWireGuardSetupViewController : UIViewController

@property (nonatomic, weak, nullable) id<HIAHWireGuardSetupDelegate> delegate;
@property (nonatomic, assign, readonly) HIAHWireGuardSetupStep currentStep;

/// Check if setup is needed (WireGuard not installed or VPN not active)
+ (BOOL)isSetupNeeded;

/// Present the setup flow modally from a view controller
+ (void)presentSetupFromViewController:(UIViewController *)presenter
                              delegate:(nullable id<HIAHWireGuardSetupDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END

