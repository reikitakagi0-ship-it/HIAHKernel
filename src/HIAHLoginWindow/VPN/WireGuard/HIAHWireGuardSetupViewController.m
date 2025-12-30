/**
 * HIAHWireGuardSetupViewController.m
 * HIAH LoginWindow - WireGuard Setup Guide
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHWireGuardSetupViewController.h"
#import "HIAHWireGuardManager.h"
#import "../../../HIAHDesktop/HIAHLogging.h"

@interface HIAHWireGuardSetupViewController ()

@property (nonatomic, assign) HIAHWireGuardSetupStep currentStep;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *stepImageView;
@property (nonatomic, strong) UILabel *instructionsLabel;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *secondaryButton;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, strong) UIView *configBox;
@property (nonatomic, strong) UITextView *configTextView;
@property (nonatomic, strong) NSTimer *vpnCheckTimer;

@end

@implementation HIAHWireGuardSetupViewController

#pragma mark - Class Methods

+ (BOOL)isSetupNeeded {
    HIAHWireGuardManager *manager = [HIAHWireGuardManager sharedManager];
    
    // First check: Is the setup flag set?
    if (![manager isHIAHVPNConfigured]) {
        HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Setup needed: HIAHVPNSetupCompleted flag not set");
        return YES;  // Setup never completed
    }
    
    // Second check: Is em_proxy actually running?
    if (![manager isEMProxyRunning]) {
        // Try to start it
        if (![manager startEMProxy]) {
            HIAHLogEx(HIAH_LOG_WARNING, @"WireGuard", @"Setup needed: em_proxy failed to start");
            // Reset the setup flag since something is wrong
            [manager resetSetup];
            return YES;
        }
    }
    
    // Third check: Is the full VPN connection working?
    // Use a quick test - if em_proxy is running and VPN interface exists, we're good
    [manager refreshVPNStatus];
    if (manager.isVPNActive && [manager isEMProxyRunning]) {
        HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Setup not needed: VPN is active and em_proxy running");
        return NO;  // Everything is working
    }
    
    // VPN interface not active - but setup was completed before
    // This could mean WireGuard is disconnected (user turned it off)
    // Don't force re-setup, just warn in logs
    if ([manager isEMProxyRunning]) {
        HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Setup not needed: em_proxy running (VPN may be disconnected)");
        return NO;  // Setup was done, user just needs to enable WireGuard
    }
    
    HIAHLogEx(HIAH_LOG_WARNING, @"WireGuard", @"Setup needed: VPN stack not working");
    [manager resetSetup];
    return YES;
}

+ (void)presentSetupFromViewController:(UIViewController *)presenter
                              delegate:(id<HIAHWireGuardSetupDelegate>)delegate {
    HIAHWireGuardSetupViewController *setupVC = [[HIAHWireGuardSetupViewController alloc] init];
    setupVC.delegate = delegate;
    setupVC.modalPresentationStyle = UIModalPresentationPageSheet;
    
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = setupVC.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
    }
    
    [presenter presentViewController:setupVC animated:YES completion:nil];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setupUI];
    [self determineInitialStep];
    [self updateUIForCurrentStep];
    [self startVPNMonitoring];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopVPNMonitoring];
}

- (void)dealloc {
    [self stopVPNMonitoring];
}

#pragma mark - UI Setup

- (void)setupUI {
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeButton.tintColor = [UIColor tertiaryLabelColor];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];
    
    // Scroll view for content
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];
    
    // Content stack
    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.alignment = UIStackViewAlignmentCenter;
    self.contentStack.spacing = 20;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentStack];
    
    // Step icon
    self.stepImageView = [[UIImageView alloc] init];
    self.stepImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.stepImageView.tintColor = [UIColor systemBlueColor];
    self.stepImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.stepImageView];
    
    // Title
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 0;
    [self.contentStack addArrangedSubview:self.titleLabel];
    
    // Subtitle
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 0;
    [self.contentStack addArrangedSubview:self.subtitleLabel];
    
    // Spacer
    UIView *spacer1 = [[UIView alloc] init];
    spacer1.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer1.heightAnchor constraintEqualToConstant:10].active = YES;
    [self.contentStack addArrangedSubview:spacer1];
    
    // Instructions
    self.instructionsLabel = [[UILabel alloc] init];
    self.instructionsLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    self.instructionsLabel.textColor = [UIColor labelColor];
    self.instructionsLabel.textAlignment = NSTextAlignmentLeft;
    self.instructionsLabel.numberOfLines = 0;
    self.instructionsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStack addArrangedSubview:self.instructionsLabel];
    
    // Config box (hidden by default)
    [self setupConfigBox];
    [self.contentStack addArrangedSubview:self.configBox];
    self.configBox.hidden = YES;
    
    // Now that configBox is in the stack, we can constrain its width
    [self.configBox.leadingAnchor constraintEqualToAnchor:self.contentStack.leadingAnchor].active = YES;
    [self.configBox.trailingAnchor constraintEqualToAnchor:self.contentStack.trailingAnchor].active = YES;
    
    // Spacer
    UIView *spacer2 = [[UIView alloc] init];
    spacer2.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer2.heightAnchor constraintEqualToConstant:20].active = YES;
    [self.contentStack addArrangedSubview:spacer2];
    
    // Primary button
    self.primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.primaryButton.backgroundColor = [UIColor systemBlueColor];
    [self.primaryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.primaryButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.primaryButton.layer.cornerRadius = 14;
    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.primaryButton addTarget:self action:@selector(primaryButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentStack addArrangedSubview:self.primaryButton];
    
    // Secondary button
    self.secondaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.secondaryButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    [self.secondaryButton addTarget:self action:@selector(secondaryButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentStack addArrangedSubview:self.secondaryButton];
    
    // Page control
    self.pageControl = [[UIPageControl alloc] init];
    self.pageControl.numberOfPages = 4;
    self.pageControl.currentPageIndicatorTintColor = [UIColor systemBlueColor];
    self.pageControl.pageIndicatorTintColor = [UIColor tertiaryLabelColor];
    self.pageControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.pageControl.userInteractionEnabled = NO;
    [self.view addSubview:self.pageControl];
    
    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [closeButton.widthAnchor constraintEqualToConstant:30],
        [closeButton.heightAnchor constraintEqualToConstant:30],
        
        [self.scrollView.topAnchor constraintEqualToAnchor:closeButton.bottomAnchor constant:16],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.pageControl.topAnchor constant:-20],
        
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:20],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-20],
        
        [self.stepImageView.heightAnchor constraintEqualToConstant:80],
        [self.stepImageView.widthAnchor constraintEqualToConstant:80],
        
        [self.instructionsLabel.leadingAnchor constraintEqualToAnchor:self.contentStack.leadingAnchor],
        [self.instructionsLabel.trailingAnchor constraintEqualToAnchor:self.contentStack.trailingAnchor],
        
        [self.primaryButton.heightAnchor constraintEqualToConstant:54],
        [self.primaryButton.leadingAnchor constraintEqualToAnchor:self.contentStack.leadingAnchor],
        [self.primaryButton.trailingAnchor constraintEqualToAnchor:self.contentStack.trailingAnchor],
        
        [self.pageControl.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [self.pageControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    ]];
}

- (void)setupConfigBox {
    self.configBox = [[UIView alloc] init];
    self.configBox.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.configBox.layer.cornerRadius = 12;
    self.configBox.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *configTitle = [[UILabel alloc] init];
    configTitle.text = @"WireGuard Configuration";
    configTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    configTitle.textColor = [UIColor secondaryLabelColor];
    configTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.configBox addSubview:configTitle];
    
    self.configTextView = [[UITextView alloc] init];
    self.configTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.configTextView.textColor = [UIColor labelColor];
    self.configTextView.backgroundColor = [UIColor clearColor];
    self.configTextView.editable = NO;
    self.configTextView.scrollEnabled = NO;
    self.configTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.configBox addSubview:self.configTextView];
    
    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyButton setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    [copyButton setTitle:@" Copy" forState:UIControlStateNormal];
    copyButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    copyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [copyButton addTarget:self action:@selector(copyConfigTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.configBox addSubview:copyButton];
    
    // Only set internal constraints - external constraints to contentStack will be set after adding to stack
    [NSLayoutConstraint activateConstraints:@[
        [configTitle.topAnchor constraintEqualToAnchor:self.configBox.topAnchor constant:12],
        [configTitle.leadingAnchor constraintEqualToAnchor:self.configBox.leadingAnchor constant:12],
        
        [copyButton.centerYAnchor constraintEqualToAnchor:configTitle.centerYAnchor],
        [copyButton.trailingAnchor constraintEqualToAnchor:self.configBox.trailingAnchor constant:-12],
        
        [self.configTextView.topAnchor constraintEqualToAnchor:configTitle.bottomAnchor constant:8],
        [self.configTextView.leadingAnchor constraintEqualToAnchor:self.configBox.leadingAnchor constant:12],
        [self.configTextView.trailingAnchor constraintEqualToAnchor:self.configBox.trailingAnchor constant:-12],
        [self.configTextView.bottomAnchor constraintEqualToAnchor:self.configBox.bottomAnchor constant:-12],
    ]];
}

#pragma mark - Step Management

- (void)determineInitialStep {
    HIAHWireGuardManager *manager = [HIAHWireGuardManager sharedManager];
    
    if (manager.isVPNActive) {
        self.currentStep = HIAHWireGuardSetupStepComplete;
    } else if ([manager isWireGuardInstalled]) {
        self.currentStep = HIAHWireGuardSetupStepConfigure;
    } else {
        self.currentStep = HIAHWireGuardSetupStepInstall;
    }
}

- (void)updateUIForCurrentStep {
    self.pageControl.currentPage = self.currentStep;
    
    switch (self.currentStep) {
        case HIAHWireGuardSetupStepInstall:
            [self showInstallStep];
            break;
        case HIAHWireGuardSetupStepConfigure:
            [self showConfigureStep];
            break;
        case HIAHWireGuardSetupStepActivate:
            [self showActivateStep];
            break;
        case HIAHWireGuardSetupStepComplete:
            [self showCompleteStep];
            break;
    }
}

- (void)showInstallStep {
    self.stepImageView.image = [UIImage systemImageNamed:@"arrow.down.app.fill"];
    self.stepImageView.tintColor = [UIColor systemBlueColor];
    
    self.titleLabel.text = @"Install WireGuard";
    self.subtitleLabel.text = @"WireGuard VPN is required to enable advanced features like JIT compilation and signature bypass.";
    
    self.instructionsLabel.text = @"WireGuard is a free, open-source VPN app available on the App Store. HIAH Desktop uses it to create a local VPN tunnel that enables:\n\n• JIT (Just-In-Time) compilation\n• Running unsigned apps\n• Better app compatibility\n\nTap the button below to download WireGuard from the App Store.\n\nIf you already have WireGuard installed, tap \"Skip to Configuration\".";
    
    self.configBox.hidden = YES;
    
    [self.primaryButton setTitle:@"Open App Store" forState:UIControlStateNormal];
    [self.secondaryButton setTitle:@"Skip to Configuration →" forState:UIControlStateNormal];
    self.secondaryButton.hidden = NO;
}

- (void)showConfigureStep {
    self.stepImageView.image = [UIImage systemImageNamed:@"gearshape.fill"];
    self.stepImageView.tintColor = [UIColor systemOrangeColor];
    
    self.titleLabel.text = @"Import HIAH VPN Config";
    self.subtitleLabel.text = @"Add the HIAH tunnel to WireGuard.";
    
    // Save config file to Documents for easy sharing
    HIAHWireGuardManager *manager = [HIAHWireGuardManager sharedManager];
    NSString *savedPath = [manager saveConfigurationToDocuments];
    
    if (savedPath) {
        self.instructionsLabel.text = @"The HIAH VPN configuration has been saved to your Documents folder.\n\nEasiest method:\n1. Tap \"Share Config File\" below\n2. Select \"WireGuard\" from the share sheet\n3. Tap \"Allow\" to import the tunnel\n4. Return here when done\n\nAlternative method:\n1. Open Files app → HIAH Desktop\n2. Tap \"HIAH-VPN.conf\"\n3. Share it to WireGuard";
    } else {
        self.instructionsLabel.text = @"1. Tap \"Copy Configuration\" below\n2. Open WireGuard app\n3. Tap \"+\" → \"Add from scratch\"\n4. Name it \"HIAH-VPN\"\n5. Paste the configuration\n6. Tap \"Save\"";
    }
    
    // Show config preview
    self.configTextView.text = [manager generateLoopbackConfiguration];
    self.configBox.hidden = NO;
    
    [self.primaryButton setTitle:@"Share Config File" forState:UIControlStateNormal];
    [self.secondaryButton setTitle:@"I've imported the config →" forState:UIControlStateNormal];
    self.secondaryButton.hidden = NO;
}

- (void)showActivateStep {
    self.stepImageView.image = [UIImage systemImageNamed:@"power.circle.fill"];
    self.stepImageView.tintColor = [UIColor systemGreenColor];
    
    self.titleLabel.text = @"Activate HIAH-VPN";
    self.subtitleLabel.text = @"Enable the HIAH-VPN tunnel in WireGuard.";
    
    self.instructionsLabel.text = @"Final step:\n\n1. Open WireGuard app\n2. Find \"HIAH-VPN\" tunnel\n3. Toggle the switch to turn it ON\n4. Allow VPN permission if prompted\n5. Return here and tap \"Verify Connection\"\n\n⚠️ Make sure you activate the HIAH-VPN tunnel specifically, not a different VPN.";
    
    self.configBox.hidden = YES;
    
    [self.primaryButton setTitle:@"Open WireGuard" forState:UIControlStateNormal];
    [self.secondaryButton setTitle:@"Verify Connection" forState:UIControlStateNormal];
    self.secondaryButton.hidden = NO;
}

- (void)showCompleteStep {
    self.stepImageView.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
    self.stepImageView.tintColor = [UIColor systemGreenColor];
    
    self.titleLabel.text = @"All Set!";
    self.subtitleLabel.text = @"WireGuard VPN is connected and ready.";
    
    self.instructionsLabel.text = @"HIAH Desktop can now:\n\n✓ Enable JIT compilation for apps\n✓ Run unsigned applications\n✓ Bypass signature verification\n\nKeep WireGuard connected while using apps that require these features.\n\nYou can manage the VPN connection anytime from the WireGuard app or HIAH Top.";
    
    self.configBox.hidden = YES;
    
    [self.primaryButton setTitle:@"Done" forState:UIControlStateNormal];
    self.secondaryButton.hidden = YES;
}

#pragma mark - Actions

- (void)primaryButtonTapped {
    HIAHWireGuardManager *manager = [HIAHWireGuardManager sharedManager];
    
    switch (self.currentStep) {
        case HIAHWireGuardSetupStepInstall:
            [manager openWireGuardInAppStore];
            break;
            
        case HIAHWireGuardSetupStepConfigure:
            [self shareConfigFile];
            break;
            
        case HIAHWireGuardSetupStepActivate:
            // Try to open WireGuard app
            // Note: WireGuard doesn't have a reliable public URL scheme on iOS
            // The wireguard:// scheme may or may not work depending on the version
            {
                NSURL *wireguardURL = [NSURL URLWithString:@"wireguard://"];
                if ([[UIApplication sharedApplication] canOpenURL:wireguardURL]) {
                    [[UIApplication sharedApplication] openURL:wireguardURL
                                                       options:@{}
                                             completionHandler:^(BOOL success) {
                        if (!success) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self showOpenWireGuardManuallyAlert];
                            });
                        }
                    }];
                } else {
                    // URL scheme not available - show manual instructions
                    [self showOpenWireGuardManuallyAlert];
                }
            }
            break;
            
        case HIAHWireGuardSetupStepComplete:
            [self completeSetup];
            break;
    }
}

- (void)shareConfigFile {
    HIAHWireGuardManager *manager = [HIAHWireGuardManager sharedManager];
    
    // Save config file first
    NSString *savedPath = [manager saveConfigurationToDocuments];
    if (!savedPath) {
        // Fallback to copy to clipboard
        [manager copyConfigurationToPasteboard];
        [self showAlert:@"Config Copied" message:@"Configuration copied to clipboard.\n\nOpen WireGuard → Add Tunnel → Create from scratch → paste config."];
        return;
    }
    
    NSURL *configURL = [NSURL fileURLWithPath:savedPath];
    
    // Create share sheet with file URL
    // Note: UIActivityViewController can be slow because iOS scans the file
    // We minimize this by keeping the file small and excluding unnecessary activities
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] 
        initWithActivityItems:@[configURL]
        applicationActivities:nil];
    
    // Exclude ALL social and irrelevant activities to speed up loading
    activityVC.excludedActivityTypes = @[
        UIActivityTypePostToFacebook,
        UIActivityTypePostToTwitter,
        UIActivityTypePostToWeibo,
        UIActivityTypeMessage,
        UIActivityTypeMail,
        UIActivityTypeAssignToContact,
        UIActivityTypeSaveToCameraRoll,
        UIActivityTypeAddToReadingList,
        UIActivityTypePostToFlickr,
        UIActivityTypePostToVimeo,
        UIActivityTypePostToTencentWeibo,
        UIActivityTypePrint,
        UIActivityTypeCopyToPasteboard,  // We have our own copy button
        UIActivityTypeMarkupAsPDF
    ];
    
    // For iPad
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.primaryButton;
        activityVC.popoverPresentationController.sourceRect = self.primaryButton.bounds;
    }
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)secondaryButtonTapped {
    HIAHWireGuardManager *manager = [HIAHWireGuardManager sharedManager];
    
    switch (self.currentStep) {
        case HIAHWireGuardSetupStepInstall:
            // User says they have WireGuard - allow them to proceed
            // (canOpenURL might fail due to LSApplicationQueriesSchemes not being properly loaded)
            HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"User skipping to configuration step");
            self.currentStep = HIAHWireGuardSetupStepConfigure;
            [self updateUIForCurrentStep];
            break;
            
        case HIAHWireGuardSetupStepConfigure:
            // User says config is ready - advance to activate
            self.currentStep = HIAHWireGuardSetupStepActivate;
            [self updateUIForCurrentStep];
            break;
            
        case HIAHWireGuardSetupStepActivate:
            // Check if full VPN connection is working (em_proxy + WireGuard)
            [manager refreshVPNStatus];
            
            // First make sure em_proxy is running
            if (![manager isEMProxyRunning]) {
                HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Starting em_proxy before verification...");
                [manager startEMProxy];
            }
            
            // Verify the connection (em_proxy running + any VPN active)
            if ([manager verifyFullVPNConnection]) {
                // VPN connection verified - mark setup as completed
                HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"✅ VPN connection verified - setup complete");
                [manager markSetupCompleted];
                self.currentStep = HIAHWireGuardSetupStepComplete;
                [self updateUIForCurrentStep];
            } else {
                // Either em_proxy failed to start or no VPN is active
                [self showAlert:@"VPN Not Active"
                        message:@"Please ensure:\n\n1. WireGuard app is installed\n2. A VPN tunnel is configured\n3. The VPN tunnel is turned ON\n\nReturn here and tap \"Verify Connection\" when ready."];
            }
            break;
            
        case HIAHWireGuardSetupStepComplete:
            break;
    }
}

- (void)copyConfigTapped {
    [[HIAHWireGuardManager sharedManager] copyConfigurationToPasteboard];
    
    // Visual feedback
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:@"Configuration copied!"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)closeTapped {
    if ([self.delegate respondsToSelector:@selector(wireGuardSetupDidSkip)]) {
        [self.delegate wireGuardSetupDidSkip];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)completeSetup {
    HIAHLogEx(HIAH_LOG_INFO, @"WireGuard", @"Setup completed successfully");
    
    if ([self.delegate respondsToSelector:@selector(wireGuardSetupDidComplete)]) {
        [self.delegate wireGuardSetupDidComplete];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - VPN Monitoring

- (void)startVPNMonitoring {
    // Start the manager's monitoring
    [[HIAHWireGuardManager sharedManager] startMonitoringVPNStatus];
    
    // Also poll periodically to update UI
    self.vpnCheckTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                          target:self
                                                        selector:@selector(checkVPNAndAdvance)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)stopVPNMonitoring {
    [self.vpnCheckTimer invalidate];
    self.vpnCheckTimer = nil;
}

- (void)checkVPNAndAdvance {
    HIAHWireGuardManager *manager = [HIAHWireGuardManager sharedManager];
    [manager refreshVPNStatus];
    
    // Only auto-advance from Install step if WireGuard is detected via canOpenURL
    // (This often fails due to LSApplicationQueriesSchemes caching issues)
    if ([manager isWireGuardInstalled] && self.currentStep == HIAHWireGuardSetupStepInstall) {
        self.currentStep = HIAHWireGuardSetupStepConfigure;
        [self updateUIForCurrentStep];
        return;
    }
    
    // Don't auto-advance on other steps - let user control the flow
}

#pragma mark - Helpers

- (void)showOpenWireGuardManuallyAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Open WireGuard Manually"
                                                                   message:@"WireGuard cannot be opened automatically.\n\nPlease:\n1. Press Home button or swipe up\n2. Find and tap the WireGuard app\n3. Turn on the \"HIAH-VPN\" tunnel\n4. Return here to verify"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

