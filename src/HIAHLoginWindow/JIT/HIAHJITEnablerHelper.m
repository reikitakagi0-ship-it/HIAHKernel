/**
 * HIAHJITEnablerHelper.m
 * HIAH LoginWindow - JIT Enablement Helper (C bridge)
 *
 * C helper functions for JIT enablement that can be called from Swift.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>
#import <sys/sysctl.h>

// Code signing definitions
#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000

// Private code signing function
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

BOOL HIAHJITEnablerHelper_isJITEnabled(void) {
    int flags = 0;
    if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) == 0) {
        return (flags & CS_DEBUGGED) != 0;
    }
    return NO;
}

