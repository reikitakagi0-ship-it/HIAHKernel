# HIAH Signature Bypass Implementation

## Overview

HIAH Desktop implements a complete signature verification bypass system that allows unsigned iOS apps (loaded as .dylibs) to run inside HIAH Desktop. This is similar to SideStore's LiveProcess/LiveContainer approach but implemented uniquely for HIAH.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    HIAH Desktop (Main App)                   │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         HIAH LoginWindow (SideStore Core)          │   │
│  │                                                      │   │
│  │  ┌──────────────────────────────────────────────┐ │   │
│  │  │  HIAHSignatureBypass Service                  │ │   │
│  │  │  - Coordinates VPN + JIT + Signing            │ │   │
│  │  │  - Ensures bypass is ready before dlopen      │ │   │
│  │  └──────────────────────────────────────────────┘ │   │
│  │                                                      │   │
│  │  ┌──────────────────────────────────────────────┐ │   │
│  │  │  HIAHVPNManager                               │ │   │
│  │  │  - Starts EM Proxy loopback VPN                │ │   │
│  │  │  - Creates tunnel to 127.0.0.1:65399          │ │   │
│  │  └──────────────────────────────────────────────┘ │   │
│  │                                                      │   │
│  │  ┌──────────────────────────────────────────────┐ │   │
│  │  │  HIAHJITManager                               │ │   │
│  │  │  - Enables JIT via Minimuxer                  │ │   │
│  │  │  - Sets CS_DEBUGGED flag                      │ │   │
│  │  └──────────────────────────────────────────────┘ │   │
│  │                                                      │   │
│  │  ┌──────────────────────────────────────────────┐ │   │
│  │  │  HIAHBypassCoordinator                       │ │   │
│  │  │  - Shares VPN/JIT status via App Group       │ │   │
│  │  │  - Allows extension to check bypass status    │ │   │
│  │  └──────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ App Group Shared Storage
                            │ (HIAH_BypassStatus.plist)
                            │
┌───────────────────────────▼─────────────────────────────────┐
│              HIAH ProcessRunner (Extension)                 │
│                                                              │
│  ┌────────────────────────────────────────────────────┐   │
│  │  HIAHBypassStatus                                   │   │
│  │  - Reads VPN/JIT status from shared storage        │   │
│  │  - Verifies JIT via direct CS_DEBUGGED check       │   │
│  └────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌────────────────────────────────────────────────────┐   │
│  │  ExecuteGuestApplication()                         │   │
│  │  1. Patch binary to MH_BUNDLE (dylib)              │   │
│  │  2. Check bypass status (VPN + JIT)                 │   │
│  │  3. Sign binary if JIT not available (fallback)    │   │
│  │  4. dlopen() binary as dylib                       │   │
│  │  5. dyld bypass skips signature validation        │   │
│  └────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌────────────────────────────────────────────────────┐   │
│  │  HIAHDyldBypass (Initialized at startup)           │   │
│  │  - Patches dyld's mmap/fcntl functions            │   │
│  │  - Bypasses library validation when JIT enabled   │   │
│  └────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. HIAHSignatureBypass (Main App)
- **Location**: `src/HIAHLoginWindow/Signing/HIAHSignatureBypass.h/m`
- **Purpose**: Coordinates VPN, JIT, and signing
- **Key Methods**:
  - `ensureBypassReadyWithCompletion:` - Starts VPN, enables JIT, verifies status
  - `prepareBinaryForDlopen:completion:` - Prepares binary before dlopen
  - `signDylibAtPath:error:` - Signs dylib with user certificate (fallback)

### 2. HIAHBypassCoordinator (Main App)
- **Location**: `src/HIAHLoginWindow/Signing/HIAHBypassCoordinator.h/m`
- **Purpose**: Shares bypass status between main app and extension
- **Mechanism**: App Group shared storage (`HIAH_BypassStatus.plist`)
- **Key Properties**:
  - `isVPNActive` - VPN connection status
  - `isJITEnabled` - JIT enablement status (CS_DEBUGGED flag)
  - `isBypassReady` - Both VPN and JIT are active

### 3. HIAHBypassStatus (Extension)
- **Location**: `src/extension/HIAHBypassStatus.h/m`
- **Purpose**: Lightweight status reader for ProcessRunner extension
- **Mechanism**: Reads from App Group shared storage
- **Key Methods**:
  - `refreshStatus` - Updates status from shared storage
  - `isBypassReady` - Checks if bypass is ready

### 4. HIAHVPNManager (Main App)
- **Location**: `src/HIAHLoginWindow/VPN/HIAHVPNManager.h/m`
- **Purpose**: Manages VPN loopback tunnel
- **Key Features**:
  - Starts EM Proxy process (`em-proxy -l 127.0.0.1:65399`)
  - Creates NEPacketTunnelProvider connection
  - Updates HIAHBypassCoordinator when status changes

### 5. HIAHJITManager (Main App)
- **Location**: `src/HIAHLoginWindow/JIT/HIAHJITManager.h/m`
- **Purpose**: Enables JIT for processes
- **Key Features**:
  - Ensures VPN is active before enabling JIT
  - Uses HIAHJITEnabler (Swift) to enable JIT via Minimuxer
  - Verifies JIT is enabled (CS_DEBUGGED flag)
  - Updates HIAHBypassCoordinator when JIT is enabled

### 6. HIAHJITEnabler (Swift)
- **Location**: `src/HIAHLoginWindow/JIT/HIAHJITEnabler.swift`
- **Purpose**: Swift interface for JIT enablement
- **Key Features**:
  - Checks if JIT is already enabled
  - Ensures VPN is active
  - Enables JIT via Minimuxer (when fully integrated)
  - Verifies JIT status

### 7. HIAHProcessRunner (Extension)
- **Location**: `src/extension/HIAHProcessRunner.m`
- **Purpose**: Executes guest iOS apps as dylibs
- **Key Flow**:
  1. Receives spawn request from HIAHKernel
  2. Patches binary to MH_BUNDLE (dylib format)
  3. Checks bypass status via HIAHBypassStatus
  4. Signs binary if JIT not available (fallback)
  5. Calls `dlopen()` to load binary as dylib
  6. dyld bypass (initialized at startup) skips signature validation

### 8. HIAHDyldBypass (Extension)
- **Location**: `src/hooks/HIAHDyldBypass.m`
- **Purpose**: Patches dyld to bypass signature validation
- **Key Features**:
  - Only works when JIT is enabled (CS_DEBUGGED flag)
  - Patches dyld's `mmap` and `fcntl` functions
  - Allows unsigned dylibs to be loaded
  - Initialized in ProcessRunner's constructor

## Flow Diagram

### App Launch Flow
```
1. HIAH Desktop launches
   ↓
2. AppDelegate.didFinishLaunchingWithOptions
   ↓
3. HIAHSignatureBypass.ensureBypassReadyWithCompletion:
   ↓
4. HIAHVPNManager.startVPNWithCompletion:
   - Starts EM Proxy process
   - Creates VPN tunnel
   - Updates HIAHBypassCoordinator (VPN active)
   ↓
5. HIAHJITManager.enableJITForPID:
   - Ensures VPN is active
   - Enables JIT via Minimuxer (through VPN tunnel)
   - Verifies CS_DEBUGGED flag is set
   - Updates HIAHBypassCoordinator (JIT enabled)
   ↓
6. Bypass system ready
   - VPN active ✓
   - JIT enabled ✓
   - Status saved to App Group
```

### App Execution Flow
```
1. User installs .ipa via HIAH Installer
   ↓
2. .ipa extracted to .app bundle in virtual filesystem
   ↓
3. User launches app from HIAH Desktop
   ↓
4. HIAHKernel spawns app via ProcessRunner extension
   ↓
5. ProcessRunner.ExecuteGuestApplication()
   ↓
6. Patch binary to MH_BUNDLE (dylib format)
   ↓
7. HIAHBypassStatus.checkBypassReady()
   - Reads VPN/JIT status from App Group
   - Verifies CS_DEBUGGED flag directly
   ↓
8. If JIT enabled:
   - dyld bypass will skip signature validation
   - Binary can be unsigned
   ↓
9. If JIT not enabled:
   - Sign binary with HIAHSigner (fallback)
   - Binary has valid signature
   ↓
10. dlopen(binaryPath) - Load as dylib
   ↓
11. dyld validates signature
    - If JIT enabled: bypass validation (patched)
    - If signed: normal validation passes
   ↓
12. App runs successfully ✓
```

## Key Differences from LiveProcess/LiveContainer

1. **Unique Implementation**: All code is written from scratch, not copied
2. **App Group Communication**: Uses shared storage instead of direct class access
3. **Integrated into Desktop**: Bypass is part of HIAH Desktop, not a separate app
4. **Self-Contained**: HIAH Desktop manages its own VPN/JIT, no external tools
5. **Extension-Based**: ProcessRunner is an extension, not a separate process

## Status Verification

The system verifies bypass status at multiple levels:

1. **Main App**: HIAHSignatureBypass checks VPN + JIT status
2. **Shared Storage**: HIAHBypassCoordinator writes status to App Group
3. **Extension**: HIAHBypassStatus reads from shared storage
4. **Direct Check**: Both verify CS_DEBUGGED flag directly via `csops()`

## Fallback Mechanism

If JIT cannot be enabled:
1. System falls back to signing dylibs with user's certificate
2. HIAHSigner signs the binary before dlopen
3. Signed binary passes normal signature validation
4. App still runs, just requires signing step

## Testing Checklist

- [ ] VPN starts successfully on app launch
- [ ] JIT is enabled (CS_DEBUGGED flag set)
- [ ] Status is written to App Group shared storage
- [ ] ProcessRunner can read status from shared storage
- [ ] dyld bypass is initialized in ProcessRunner
- [ ] Unsigned dylibs can be loaded when JIT is enabled
- [ ] Signed dylibs work as fallback when JIT is not enabled
- [ ] Apps installed via HIAH Installer can run

## Implementation Status

✅ **Completed**:
- VPN loopback infrastructure
- JIT enablement framework
- Signature bypass coordination
- App Group communication
- ProcessRunner integration
- dyld bypass implementation
- Fallback signing mechanism

⚠️ **Needs Full Integration**:
- Complete Minimuxer API integration for JIT enablement
- User certificate signing for dylibs (currently ad-hoc)
- Full testing on physical device

## Notes

- The implementation is unique and not copied from LiveProcess/LiveContainer
- All communication between main app and extension uses App Group shared storage
- The system gracefully falls back to signing if JIT cannot be enabled
- dyld bypass only works when JIT is enabled (CS_DEBUGGED flag)
- VPN must be active for JIT enablement to work

