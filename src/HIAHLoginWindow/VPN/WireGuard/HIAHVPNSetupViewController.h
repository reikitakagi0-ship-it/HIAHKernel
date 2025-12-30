/**
 * HIAHVPNSetupViewController.h
 * Clean VPN setup wizard using state machine
 *
 * Copyright (c) 2025 Alex Spaulding - AGPLv3
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol HIAHVPNSetupDelegate <NSObject>
- (void)vpnSetupDidComplete;
- (void)vpnSetupDidCancel;
@end

/// Setup wizard steps
typedef NS_ENUM(NSInteger, HIAHVPNSetupStep) {
    HIAHVPNSetupStepWelcome = 0,
    HIAHVPNSetupStepInstallWireGuard,
    HIAHVPNSetupStepImportConfig,
    HIAHVPNSetupStepActivateVPN,
    HIAHVPNSetupStepComplete
};

/**
 * HIAHVPNSetupViewController
 *
 * A clean, declarative setup wizard for VPN configuration.
 * Uses HIAHVPNStateMachine for all VPN state management.
 */
@interface HIAHVPNSetupViewController : UIViewController

@property (nonatomic, weak, nullable) id<HIAHVPNSetupDelegate> delegate;

/// Check if setup is needed (uses state machine)
+ (BOOL)isSetupNeeded;

/// Present the setup wizard
+ (void)presentFrom:(UIViewController *)presenter
           delegate:(nullable id<HIAHVPNSetupDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END

