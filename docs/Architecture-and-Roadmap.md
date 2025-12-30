# HIAH Desktop: Architecture and Roadmap

## Current State (December 2024)

HIAH Desktop is a virtual iOS desktop environment with process spawning capabilities. The project has evolved from a prototype into a production-ready system with integrated VPN/JIT support.

### What's Implemented ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Virtual Desktop Environment | ✅ Complete | Multi-window, app launcher |
| HIAH Kernel | ✅ Complete | Process management, socket IPC |
| HIAH ProcessRunner | ✅ Complete | Extension-based app execution |
| Virtual Filesystem | ✅ Complete | Unix-like filesystem for apps |
| Apple Account Login | ✅ Complete | Via AltSign + Anisette servers |
| 2FA Support | ✅ Complete | In-app verification code entry |
| VPN State Machine | ✅ Complete | Declarative, thread-safe |
| WireGuard Integration | ✅ Complete | Setup wizard, auto-detection |
| EM Proxy (loopback) | ✅ Complete | Linked as static library |
| Bypass Coordinator | ✅ Complete | App Group status sharing |
| HIAH Top (monitor) | ✅ Complete | Real-time VPN/JIT status |

### What's Not Working Yet ❌

| Feature | Status | Blocker |
|---------|--------|---------|
| Unsigned App Execution | ❌ Blocked | JIT (CS_DEBUGGED) not being enabled |
| Self-Refresh (7-day) | ❌ Not started | Depends on JIT working |
| Certificate Management | ⚠️ Partial | Login works, signing untested |

## Architecture

```
HIAH Desktop (Main App)
├── HIAH LoginWindow (AGPLv3 - SideStore Core)
│   ├── Apple Account Authentication (AltSign)
│   ├── Anisette Data (external servers)
│   ├── VPN State Machine (em_proxy + WireGuard)
│   └── Bypass Coordinator (App Group)
├── HIAH ProcessRunner (Extension)
│   ├── Bypass Status Reader
│   ├── Dyld Bypass Hooks
│   └── Guest App Execution
└── HIAH Desktop Environment
    ├── Window Manager (HIAHWindowServer)
    ├── App Launcher
    └── Virtual Filesystem
```

## VPN State Machine

The VPN system uses a declarative state machine for robust, predictable behavior:

```
                    ┌──────────────────────────┐
                    │      HIAHVPNStateMachine │
                    │   (single source of truth)│
                    └────────────┬─────────────┘
                                 │
   ┌─────────────────────────────┼─────────────────────────────┐
   │                             │                             │
   ▼                             ▼                             ▼
[Idle] ──Start──> [StartingProxy] ──ProxyStarted──> [ProxyReady]
                        │                                │
                        │                                │
                   ProxyFailed                     VPNConnected
                        │                                │
                        ▼                                ▼
                    [Error] <──VPNDisconnected── [Connected]
```

**States:**
- `Idle` - Not running
- `StartingProxy` - em_proxy is starting
- `ProxyReady` - em_proxy running, waiting for WireGuard
- `Connected` - em_proxy + WireGuard both active
- `Error` - Something failed

**VPN Detection:**
- Uses `test_emotional_damage()` from em_proxy to verify HIAH VPN specifically
- Does NOT just check for any `utun` interface (user might have other VPNs)
- Only the state machine updates the bypass coordinator (prevents race conditions)

## Known Issues

### 1. JIT Not Being Enabled
**Symptom:** `[HIAHExtension] Bypass status - VPN: NO, JIT: NO, Ready: NO`

**Root Cause:** The extension process cannot see the main app's state directly. While the bypass coordinator writes to App Group storage, the extension may read stale data or the JIT enabling mechanism isn't actually setting the CS_DEBUGGED flag.

**Required:** Minimuxer integration to actually enable JIT via the VPN tunnel.

### 2. Anisette Server Timeouts
**Symptom:** Login fails with "request timed out"

**Root Cause:** When WireGuard VPN is active, it routes ALL traffic through the loopback (127.0.0.1:65399). This blocks access to external anisette servers.

**Workaround:** Disable WireGuard VPN before signing in with Apple Account.

**Better Solution (TODO):** Stop routing during auth, or use local anisette via minimuxer.

### 3. Code Signature Invalid on dlopen
**Symptom:** `dlopen failed: code signature invalid`

**Root Cause:** JIT (CS_DEBUGGED flag) is not enabled. The dyld bypass hooks require JIT to work.

## Technical Flow

### How VPN/JIT Should Work
```
1. User launches HIAH Desktop
2. State machine → [StartingProxy] → em_proxy starts on 127.0.0.1:65399
3. State machine → [ProxyReady]
4. User enables WireGuard VPN with HIAH-VPN tunnel
5. WireGuard connects to em_proxy endpoint
6. test_emotional_damage() succeeds → [Connected]
7. Minimuxer connects via em_proxy (TODO)
8. Minimuxer enables JIT (CS_DEBUGGED flag) (TODO)
9. Bypass coordinator writes: VPN=YES, JIT=YES
10. ProcessRunner reads status, uses dyld bypass
11. dlopen() succeeds on unsigned binary
12. Guest app runs!
```

### Current Reality
```
Steps 1-6 work ✅
Steps 7-8 NOT IMPLEMENTED - JIT never gets enabled
Steps 9-11 fail because JIT=NO
Step 12 fails with "code signature invalid"
```

## Next Steps

### Priority 1: Minimuxer Integration
The missing piece is Minimuxer, which enables JIT by:
1. Connecting to lockdownd through em_proxy
2. Starting a debug server
3. Attaching to the process
4. Setting the CS_DEBUGGED flag

**Files to create:**
- `src/HIAHLoginWindow/JIT/MinimuxerBridge.h/m` - Objective-C wrapper
- Link `libminimuxer.a` in project.yml

### Priority 2: Local Anisette
To avoid the VPN-blocking-auth problem:
- Use Minimuxer's local anisette generation
- Or temporarily disable VPN routing during auth

### Priority 3: Self-Refresh
Once JIT works:
- Monitor certificate expiration
- Auto-resign HIAH Desktop before 7-day expiry
- Background refresh via iOS background tasks

## File Structure

```
src/
├── HIAHDesktop/           # Main app (MIT license)
│   ├── HIAHDesktopApp.m   # App delegate, scene management
│   ├── HIAHWindowServer.m # Multi-window management
│   └── HIAHLogging.h/m    # Centralized logging
├── HIAHLoginWindow/       # AGPLv3 (SideStore integration)
│   ├── Auth/              # Apple Account authentication
│   │   ├── HIAHAccountManager.swift
│   │   └── AltSignExtensions.swift
│   ├── VPN/               # VPN management
│   │   ├── HIAHVPNStateMachine.h/m  # Single source of truth
│   │   ├── EMProxyBridge.h/m        # em_proxy C library wrapper
│   │   └── WireGuard/               # WireGuard setup wizard
│   ├── JIT/               # JIT enablement (TODO: Minimuxer)
│   └── Signing/           # Bypass coordination
│       └── HIAHBypassCoordinator.h/m
├── HIAHTop/               # System monitor
├── extension/             # ProcessRunner extension
│   ├── HIAHBypassStatus.h/m  # Reads status from App Group
│   └── HIAHDyldBypass.h/m    # Dyld hooks (requires JIT)
└── hooks/                 # Kernel hooks
```

## Resources

- **SideStore**: https://github.com/SideStore/SideStore
- **EM Proxy**: https://github.com/jkcoxson/em_proxy
- **Minimuxer**: https://github.com/jkcoxson/minimuxer
- **Jitterbug**: https://github.com/osy/Jitterbug
- **LocalDevVPN**: https://github.com/jkcoxson/LocalDevVPN

## Licensing

- **HIAH Desktop Core**: MIT
- **HIAH LoginWindow**: AGPLv3 (due to SideStore/AltSign integration)

---

**Current Phase**: VPN Integration Complete ✅  
**Blocking Issue**: Minimuxer/JIT not integrated  
**Next Milestone**: Enable JIT via Minimuxer  
**Status**: Apps cannot run unsigned until JIT is enabled

