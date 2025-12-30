/**
 * HIAHJITEnablerHelper.h
 * HIAH LoginWindow - JIT Enablement Helper (C bridge)
 *
 * C helper functions for JIT enablement.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>

/// Check if JIT is currently enabled (CS_DEBUGGED flag)
BOOL HIAHJITEnablerHelper_isJITEnabled(void);

