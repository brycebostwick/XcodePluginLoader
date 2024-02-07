#import "XcodePluginLoader.h"

XcodePluginLoader *xcodePluginLoader;

/**
 A function to be run when `XcodePluginLoader` is loaded.
 */
__attribute((constructor)) void init(void) {
    /*
     In the event that `XcodePluginLoader` was loaded
     using `DYLD_INSERT_LIBRARIES`, we need to
     unset DYLD_INSERT_LIBRARIES so it doesn't affect
     any child processes that Xcode launches.

     This has no effect if `XcodePluginLoader` was loaded
     via other means (like injecting a `LC_LOAD_DYLIB`
     command into Xcode itself).
     */
    unsetenv("DYLD_INSERT_LIBRARIES");

    NSLog(@"[XcodePluginLoader] Loaded");

    // Create and start the plugin loader itself
    xcodePluginLoader = [[XcodePluginLoader alloc] init];
    [xcodePluginLoader start];
}
