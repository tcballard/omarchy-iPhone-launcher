// Copyright 2026 Tom Ballard. MIT License.
#include "OmarchyPairing.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <sys/sysctl.h>
#include <unistd.h>

bool omarchy_debugger_attached(void) {
    struct kinfo_proc info = {0};
    size_t size = sizeof(info);
    int query[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    return sysctl(query, 4, &info, &size, NULL, 0) == 0 && (info.kp_proc.p_flag & P_TRACED) != 0;
}

bool omarchy_development_signed(void) {
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *);
    CreateTask create = (CreateTask)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CopyEntitlement copy = (CopyEntitlement)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!create || !copy) return false;
    CFTypeRef task = create(kCFAllocatorDefault);
    if (!task) return false;
    CFTypeRef value = copy(task, CFSTR("get-task-allow"), NULL);
    bool allowed = value && CFEqual(value, kCFBooleanTrue);
    if (value) CFRelease(value);
    CFRelease(task);
    return allowed;
}
