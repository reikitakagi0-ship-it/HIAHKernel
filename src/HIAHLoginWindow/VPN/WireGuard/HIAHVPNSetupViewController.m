/**
 * HIAHVPNSetupViewController.m
 * Clean VPN setup wizard using state machine
 *
 * Copyright (c) 2025 Alex Spaulding - AGPLv3
 */

#import "HIAHVPNSetupViewController.h"
#import "../HIAHVPNStateMachine.h"
#import "../../../HIAHDesktop/HIAHLogging.h"

#pragma mark - Step Configuration

/// Configuration for each setup step (declarative)
typedef struct {
    const char *icon;
    const char *title;
    const char *subtitle;
    const char *instructions;
    const char *primaryButton;
    const char *secondaryButton;
    BOOL showConfig;
} HIAHSetupStepConfig;

static const HIAHSetupStepConfig kStepConfigs[] = {
    // Welcome
    {
        .icon = "lock.shield.fill",
        .title = "VPN Setup Required",
        .subtitle = "HIAH Desktop needs a VPN tunnel to enable advanced features.",
        .instructions = "This setup will guide you through:\n\n"
                        "1. Installing WireGuard (free VPN app)\n"
                        "2. Importing the HIAH VPN configuration\n"
                        "3. Activating the VPN tunnel\n\n"
                        "This enables JIT compilation for apps that need it.",
        .primaryButton = "Get Started",
        .secondaryButton = NULL,
        .showConfig = NO
    },
    // Install WireGuard
    {
        .icon = "arrow.down.app.fill",
        .title = "Install WireGuard",
        .subtitle = "WireGuard is a free, fast VPN app from the App Store.",
        .instructions = "1. Tap \"Open App Store\" below\n"
                        "2. Install WireGuard (it's free)\n"
                        "3. Return here and tap \"Continue\"",
        .primaryButton = "Open App Store",
        .secondaryButton = "I have WireGuard →",
        .showConfig = NO
    },
    // Import Config
    {
        .icon = "doc.text.fill",
        .title = "Import Configuration",
        .subtitle = "Add the HIAH VPN tunnel to WireGuard.",
        .instructions = "1. Tap \"Share Config\" below\n"
                        "2. Select WireGuard from the share sheet\n"
                        "3. Tap \"Allow\" to import\n"
                        "4. Return here and tap \"Continue\"\n\n"
                        "Alternative: Tap \"Copy Config\" and paste manually in WireGuard.",
        .primaryButton = "Share Config",
        .secondaryButton = "Config imported →",
        .showConfig = YES
    },
    // Activate VPN
    {
        .icon = "network",
        .title = "Activate VPN",
        .subtitle = "Turn on the HIAH-VPN tunnel in WireGuard.",
        .instructions = "1. Open WireGuard app\n"
                        "2. Find the \"HIAH-VPN\" tunnel\n"
                        "3. Toggle the switch to ON\n"
                        "4. Allow VPN permission if asked\n"
                        "5. Return here - it will auto-detect",
        .primaryButton = "Open WireGuard",
        .secondaryButton = "Check Connection",
        .showConfig = NO
    },
    // Complete
    {
        .icon = "checkmark.circle.fill",
        .title = "Setup Complete!",
        .subtitle = "HIAH VPN is now active.",
        .instructions = "The VPN tunnel is connected and working.\n\n"
                        "Keep WireGuard running in the background for:\n"
                        "• JIT compilation support\n"
                        "• Running unsigned apps\n\n"
                        "You can now use all HIAH Desktop features.",
        .primaryButton = "Done",
        .secondaryButton = NULL,
        .showConfig = NO
    }
};

#pragma mark - Implementation

@interface HIAHVPNSetupViewController ()

@property (nonatomic, assign) HIAHVPNSetupStep currentStep;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *instructionsLabel;
@property (nonatomic, strong) UIView *configBox;
@property (nonatomic, strong) UITextView *configTextView;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *secondaryButton;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@end

@implementation HIAHVPNSetupViewController

#pragma mark - Class Methods

+ (BOOL)isSetupNeeded {
    HIAHVPNStateMachine *sm = [HIAHVPNStateMachine shared];
    
    // If setup was never completed, definitely need setup
    if (!sm.isSetupComplete) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPNSetup", @"Setup needed: never completed");
        return YES;
    }
    
    // If already connected, no setup needed
    if (sm.isConnected) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPNSetup", @"Setup not needed: already connected");
        return NO;
    }
    
    // Setup was completed but not connected - might just need to turn on VPN
    // Start the state machine if not already running
    if (sm.state == HIAHVPNStateIdle) {
        [sm sendEvent:HIAHVPNEventStart];
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"VPNSetup", @"Setup not needed: state=%@", sm.stateName);
    return NO;
}

+ (void)presentFrom:(UIViewController *)presenter
           delegate:(id<HIAHVPNSetupDelegate>)delegate {
    HIAHVPNSetupViewController *vc = [[HIAHVPNSetupViewController alloc] init];
    vc.delegate = delegate;
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = vc.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
    }
    
    [presenter presentViewController:vc animated:YES completion:nil];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self buildUI];
    [self observeStateChanges];
    [self startStateMachine];
    [self showStep:HIAHVPNSetupStepWelcome animated:NO];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI Construction

- (void)buildUI {
    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor tertiaryLabelColor];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeBtn];
    
    // Icon
    self.iconView = [[UIImageView alloc] init];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.tintColor = [UIColor systemBlueColor];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.iconView];
    
    // Title
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.titleLabel];
    
    // Subtitle
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.font = [UIFont systemFontOfSize:15];
    self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.subtitleLabel];
    
    // Instructions
    self.instructionsLabel = [[UILabel alloc] init];
    self.instructionsLabel.font = [UIFont systemFontOfSize:16];
    self.instructionsLabel.numberOfLines = 0;
    self.instructionsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.instructionsLabel];
    
    // Config box
    [self buildConfigBox];
    
    // Primary button
    self.primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.primaryButton.backgroundColor = [UIColor systemBlueColor];
    [self.primaryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.primaryButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.primaryButton.layer.cornerRadius = 14;
    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.primaryButton addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.primaryButton];
    
    // Secondary button
    self.secondaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.secondaryButton.titleLabel.font = [UIFont systemFontOfSize:15];
    self.secondaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.secondaryButton addTarget:self action:@selector(secondaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.secondaryButton];
    
    // Page control
    self.pageControl = [[UIPageControl alloc] init];
    self.pageControl.numberOfPages = 5;
    self.pageControl.currentPageIndicatorTintColor = [UIColor systemBlueColor];
    self.pageControl.pageIndicatorTintColor = [UIColor tertiaryLabelColor];
    self.pageControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.pageControl.userInteractionEnabled = NO;
    [self.view addSubview:self.pageControl];
    
    // Spinner (for checking connection)
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    
    // Layout
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [closeBtn.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
        [closeBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [closeBtn.widthAnchor constraintEqualToConstant:30],
        [closeBtn.heightAnchor constraintEqualToConstant:30],
        
        [self.iconView.topAnchor constraintEqualToAnchor:closeBtn.bottomAnchor constant:24],
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:80],
        [self.iconView.heightAnchor constraintEqualToConstant:80],
        
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:20],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        
        [self.instructionsLabel.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:24],
        [self.instructionsLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.instructionsLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        
        [self.configBox.topAnchor constraintEqualToAnchor:self.instructionsLabel.bottomAnchor constant:16],
        [self.configBox.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.configBox.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [self.configBox.heightAnchor constraintEqualToConstant:120],
        
        [self.pageControl.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
        [self.pageControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [self.secondaryButton.bottomAnchor constraintEqualToAnchor:self.pageControl.topAnchor constant:-16],
        [self.secondaryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [self.primaryButton.bottomAnchor constraintEqualToAnchor:self.secondaryButton.topAnchor constant:-12],
        [self.primaryButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.primaryButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [self.primaryButton.heightAnchor constraintEqualToConstant:54],
        
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.topAnchor constraintEqualToAnchor:self.configBox.bottomAnchor constant:20],
    ]];
}

- (void)buildConfigBox {
    self.configBox = [[UIView alloc] init];
    self.configBox.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.configBox.layer.cornerRadius = 12;
    self.configBox.translatesAutoresizingMaskIntoConstraints = NO;
    self.configBox.hidden = YES;
    [self.view addSubview:self.configBox];
    
    self.configTextView = [[UITextView alloc] init];
    self.configTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.configTextView.textColor = [UIColor secondaryLabelColor];
    self.configTextView.backgroundColor = [UIColor clearColor];
    self.configTextView.editable = NO;
    self.configTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.configBox addSubview:self.configTextView];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyBtn setTitle:@"Copy" forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [copyBtn addTarget:self action:@selector(copyConfig) forControlEvents:UIControlEventTouchUpInside];
    [self.configBox addSubview:copyBtn];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.configTextView.topAnchor constraintEqualToAnchor:self.configBox.topAnchor constant:8],
        [self.configTextView.leadingAnchor constraintEqualToAnchor:self.configBox.leadingAnchor constant:12],
        [self.configTextView.trailingAnchor constraintEqualToAnchor:copyBtn.leadingAnchor constant:-8],
        [self.configTextView.bottomAnchor constraintEqualToAnchor:self.configBox.bottomAnchor constant:-8],
        
        [copyBtn.trailingAnchor constraintEqualToAnchor:self.configBox.trailingAnchor constant:-12],
        [copyBtn.topAnchor constraintEqualToAnchor:self.configBox.topAnchor constant:8],
    ]];
}

#pragma mark - State Machine Integration

- (void)startStateMachine {
    HIAHVPNStateMachine *sm = [HIAHVPNStateMachine shared];
    
    // Start the state machine if idle
    if (sm.state == HIAHVPNStateIdle) {
        [sm sendEvent:HIAHVPNEventStart];
    }
}

- (void)observeStateChanges {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(stateDidChange:)
                                                 name:HIAHVPNStateDidChangeNotification
                                               object:nil];
}

- (void)stateDidChange:(NSNotification *)note {
    HIAHVPNStateMachine *sm = [HIAHVPNStateMachine shared];
    
    HIAHLogEx(HIAH_LOG_INFO, @"VPNSetup", @"State changed: %@", sm.stateName);
    
    // Auto-advance to complete step when connected
    if (sm.isConnected && self.currentStep == HIAHVPNSetupStepActivateVPN) {
        [self showStep:HIAHVPNSetupStepComplete animated:YES];
    }
}

#pragma mark - Step Display

- (void)showStep:(HIAHVPNSetupStep)step animated:(BOOL)animated {
    self.currentStep = step;
    
    HIAHSetupStepConfig config = kStepConfigs[step];
    
    void (^updateUI)(void) = ^{
        self.iconView.image = [UIImage systemImageNamed:@(config.icon)];
        
        // Green checkmark for complete step
        if (step == HIAHVPNSetupStepComplete) {
            self.iconView.tintColor = [UIColor systemGreenColor];
        } else {
            self.iconView.tintColor = [UIColor systemBlueColor];
        }
        
        self.titleLabel.text = @(config.title);
        self.subtitleLabel.text = @(config.subtitle);
        self.instructionsLabel.text = @(config.instructions);
        
        [self.primaryButton setTitle:@(config.primaryButton) forState:UIControlStateNormal];
        
        if (config.secondaryButton) {
            [self.secondaryButton setTitle:@(config.secondaryButton) forState:UIControlStateNormal];
            self.secondaryButton.hidden = NO;
        } else {
            self.secondaryButton.hidden = YES;
        }
        
        self.configBox.hidden = !config.showConfig;
        if (config.showConfig) {
            self.configTextView.text = [[HIAHVPNStateMachine shared] generateConfig];
        }
        
        self.pageControl.currentPage = step;
    };
    
    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{
            self.view.alpha = 0.8;
        } completion:^(BOOL finished) {
            updateUI();
            [UIView animateWithDuration:0.25 animations:^{
                self.view.alpha = 1.0;
            }];
        }];
    } else {
        updateUI();
    }
}

#pragma mark - Actions

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:^{
        [self.delegate vpnSetupDidCancel];
    }];
}

- (void)primaryTapped {
    switch (self.currentStep) {
        case HIAHVPNSetupStepWelcome:
            [self showStep:HIAHVPNSetupStepInstallWireGuard animated:YES];
            break;
            
        case HIAHVPNSetupStepInstallWireGuard:
            [self openAppStore];
            break;
            
        case HIAHVPNSetupStepImportConfig:
            [self shareConfig];
            break;
            
        case HIAHVPNSetupStepActivateVPN:
            [self openWireGuard];
            break;
            
        case HIAHVPNSetupStepComplete:
            [self finishSetup];
            break;
    }
}

- (void)secondaryTapped {
    switch (self.currentStep) {
        case HIAHVPNSetupStepInstallWireGuard:
            // User says they have WireGuard
            [self showStep:HIAHVPNSetupStepImportConfig animated:YES];
            break;
            
        case HIAHVPNSetupStepImportConfig:
            // User says config is imported
            [self showStep:HIAHVPNSetupStepActivateVPN animated:YES];
            break;
            
        case HIAHVPNSetupStepActivateVPN:
            // Check connection manually
            [self checkConnection];
            break;
            
        default:
            break;
    }
}

- (void)copyConfig {
    [[HIAHVPNStateMachine shared] copyConfigToClipboard];
    
    // Brief visual feedback
    UILabel *toast = [[UILabel alloc] init];
    toast.text = @"Copied!";
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 8;
    toast.clipsToBounds = YES;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:toast];
    
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toast.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [toast.widthAnchor constraintEqualToConstant:100],
        [toast.heightAnchor constraintEqualToConstant:36],
    ]];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{
            toast.alpha = 0;
        } completion:^(BOOL finished) {
            [toast removeFromSuperview];
        }];
    });
}

- (void)openAppStore {
    NSURL *url = [NSURL URLWithString:@"itms-apps://apps.apple.com/app/id1441195209"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)shareConfig {
    HIAHVPNStateMachine *sm = [HIAHVPNStateMachine shared];
    NSString *path = [sm saveConfigToDocuments];
    
    if (!path) {
        [sm copyConfigToClipboard];
        [self showAlert:@"Config Copied" message:@"Paste it manually in WireGuard."];
        return;
    }
    
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] 
        initWithActivityItems:@[fileURL]
        applicationActivities:nil];
    
    activityVC.excludedActivityTypes = @[
        UIActivityTypePostToFacebook, UIActivityTypePostToTwitter,
        UIActivityTypePostToWeibo, UIActivityTypeMessage,
        UIActivityTypeMail, UIActivityTypePrint,
        UIActivityTypeAssignToContact, UIActivityTypeSaveToCameraRoll,
    ];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.primaryButton;
        activityVC.popoverPresentationController.sourceRect = self.primaryButton.bounds;
    }
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)openWireGuard {
    // Try to open WireGuard app directly
    // Note: wireguard:// scheme requires LSApplicationQueriesSchemes in Info.plist
    NSURL *url = [NSURL URLWithString:@"wireguard://"];
    
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) {
            // The URL scheme might not work even if WireGuard is installed
            // This is a known iOS limitation with URL schemes
            // Don't show an alert - user can find the app themselves
            HIAHLogEx(HIAH_LOG_WARNING, @"VPNSetup", @"Could not open WireGuard via URL scheme");
        }
    }];
}

- (void)checkConnection {
    [self.spinner startAnimating];
    self.primaryButton.enabled = NO;
    self.secondaryButton.enabled = NO;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating];
        self.primaryButton.enabled = YES;
        self.secondaryButton.enabled = YES;
        
        HIAHVPNStateMachine *sm = [HIAHVPNStateMachine shared];
        
        if (sm.isConnected) {
            [self showStep:HIAHVPNSetupStepComplete animated:YES];
        } else {
            [self showAlert:@"VPN Not Connected" 
                  message:@"Please make sure the HIAH-VPN tunnel is turned ON in WireGuard."];
        }
    });
}

- (void)finishSetup {
    [[HIAHVPNStateMachine shared] markSetupComplete];
    
    [self dismissViewControllerAnimated:YES completion:^{
        [self.delegate vpnSetupDidComplete];
    }];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

