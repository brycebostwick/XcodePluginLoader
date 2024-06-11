#import "XcodePluginLoader.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "ClassLoadObserver.h"
#import "XcodeHeaders/DVTPlugInManager.h"
#import "NSProcessInfo+PBXTSPlatformAdditions.h"
#import "XcodeHeaders/XcodePlugin.h"

/**
 The path to the plugin directory used by Xcode's original / built-in plugin loader
 */
NSString * __nonnull  const pluginDirectory = @"~/Library/Application Support/Developer/Shared/Xcode/Plug-ins/";

@interface XcodePluginLoader()

@property (nonatomic, strong, nullable) ClassLoadObserver *classLoadObserver;

@end

@implementation XcodePluginLoader

- (void)start {
    NSLog(@"[XcodePluginLoader] Waiting for required classes to load");

    // Wait for classes to load before performing actual plugin loading
    __weak typeof(self) weakSelf = self;
    self.classLoadObserver = [ClassLoadObserver observerForClasses:@[
        @"TSFileManager", // Needed for Xcode 15.3+ compatibility checks (as a proxy for NSProcessInfo(PBXTSPlatformAdditions) being loaded)
        @"DVTPlugInManager" // Needed for pre Xcode 15.3 compatibility checks
    ] completion:^{
        [weakSelf loadPlugins];
    }];
}

- (void)loadPlugins {
    NSLog(@"[XcodePluginLoader] Loading Plugins");

    // Iterate through plugin directory
    NSString *expandedPluginDirectory = [pluginDirectory stringByExpandingTildeInPath];
    NSArray *pluginDirectoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:expandedPluginDirectory error:NULL];
    if (!pluginDirectoryContents.count) {
        NSLog(@"[XcodePluginLoader] Found no plugins in plugin directory ( %@ )", pluginDirectory);
        return;
    }

    // For each item in the plugin directory...
    [pluginDirectoryContents enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSString *potentialBundlePath = [expandedPluginDirectory stringByAppendingPathComponent:obj];
        NSString *potentialBundleName = [potentialBundlePath lastPathComponent];
        NSString *potentialBundleExtension = [potentialBundleName pathExtension];

        BOOL isDir = NO;
        if(![[NSFileManager defaultManager] fileExistsAtPath:potentialBundlePath isDirectory:&isDir] || !isDir) {
            // Path does not represent a directory; just skip it.
            // Non-directory cases would generally be caught by additional
            // checks below, but nicer to filter them here
            // so that they don't generate confusing logs
            return;
        }

        // Only allow directories suffixed with `.xcplugin`.
        // There may be more allowed cases than this; we can add more in the future if so
        if (![potentialBundleExtension isEqualToString:@"xcplugin"]) {
            NSLog(@"[XcodePluginLoader] Skipping %@ (unknown extension)", potentialBundleName);
            return;
        }

        NSLog(@"[XcodePluginLoader] Attempting to load %@", potentialBundleName);

        // Attempt to instantiate a bundle
        NSBundle *bundle = [NSBundle bundleWithPath:potentialBundlePath];
        if (!bundle) {
            NSLog(@"[XcodePluginLoader] Skipping %@ (not a bundle)", potentialBundleName);
            return;
        }

        // Run compatibility check using `ProductBuildVersion` (needed for Xcode 15.3+).
        // Start by getting Xcode's `ProductBuildVersion`
        NSProcessInfo *processInfo = [NSProcessInfo processInfo];
        NSString *xcodeBuildVersion;
        if ([processInfo respondsToSelector:@selector(xcodeProductBuildVersion)]) {
            xcodeBuildVersion = [[NSProcessInfo processInfo] xcodeProductBuildVersion];
        }

        // Then get all `CompatibleProductBuildVersions` values from the plugin and compare
        NSArray<NSString *> *compatibleBuildVersions = [bundle objectForInfoDictionaryKey:@"CompatibleProductBuildVersions"];
        BOOL hasCompatibleBuildVersion = NO;
        if (xcodeBuildVersion && compatibleBuildVersions) {
            if (![compatibleBuildVersions isKindOfClass:[NSArray class]]) {
                NSLog(@"[XcodePluginLoader] Skipping %@ (invalid CompatibleProductBuildVersions format)", potentialBundleName);
                return;
            }

            // Check for a match
            for (NSString *buildVersion in compatibleBuildVersions) {
                if ([buildVersion isEqualToString:xcodeBuildVersion]) {
                    hasCompatibleBuildVersion = YES;
                    NSLog(@"[XcodePluginLoader] %@ is compatible with ProductBuildVersion version %@", potentialBundleName, xcodeBuildVersion);
                    break;
                }
            }
        }

        // Fall back to doing a compatibility check using `DVTPlugInCompatibilityUUIDs`
        // (matches Xcode's original plugin loader behavior, but is only available on Xcode 15.2 or older)
        if (!hasCompatibleBuildVersion) {
            NSLog(@"[XcodePluginLoader] No CompatibleProductBuildVersions in %@ matching version %@. Falling back to DVTPlugInCompatibilityUUIDs", potentialBundleName, xcodeBuildVersion);

            // Read the list of compatibility UUIDs specified by the plugin that we're loading
            NSArray<NSString *> *compatibilityUUIDs = [bundle objectForInfoDictionaryKey:@"DVTPlugInCompatibilityUUIDs"];
            if (![compatibilityUUIDs isKindOfClass:[NSArray class]]) {
                NSLog(@"[XcodePluginLoader] Skipping %@ (missing/invalid DVTPlugInCompatibilityUUIDs)", potentialBundleName);
                return;
            }

            // Get Xcode's plugin manager...
            DVTPlugInManager *pluginManager = [NSClassFromString(@"DVTPlugInManager") defaultPlugInManager];
            if (![pluginManager respondsToSelector:@selector(plugInHostUUID)]) {
                NSLog(@"[XcodePluginLoader] Skipping %@ (this version of Xcode does not support DVTPlugInCompatibilityUUIDs. Use DTXcodeBuildCompatibleVersions instead.)", potentialBundleName);
                return;
            }

            // ... And use it to get Xcode's compatibility UUID.
            // This might actually just turn around to read `DVTPlugInCompatibilityUUID` from Xcode's Info.plist;
            // in which case, we could simplify this setup significantly. I'm not sure if it does so in all cases.
            NSUUID *goalUUID = [[NSClassFromString(@"DVTPlugInManager") defaultPlugInManager] plugInHostUUID];
            if (!goalUUID) {
                NSLog(@"[XcodePluginLoader] Skipping %@ (this version of Xcode does not support DVTPlugInCompatibilityUUIDs. Use DTXcodeBuildCompatibleVersions instead.)", potentialBundleName);
                return;
            }

            // Check for a match
            BOOL hasCompatibleUUID = NO;
            for (NSString *uuidString in compatibilityUUIDs) {
                if ([[[NSUUID alloc] initWithUUIDString:uuidString] isEqual:goalUUID]) {
                    NSLog(@"[XcodePluginLoader] %@ is compatible with DVTPlugInCompatibilityUUID %@", potentialBundleName, goalUUID);
                    hasCompatibleUUID = YES;
                    break;
                }
            }
            if (!hasCompatibleUUID) {
                NSLog(@"[XcodePluginLoader] Skipping %@ (no compatibility range + no DVTPlugInCompatibilityUUIDs entry for %@)", potentialBundleName, [goalUUID UUIDString]);
                return;
            }

        }

        // Compatibility check passed;
        // actually load the plugin bundle
        NSError *error;
        if (![bundle loadAndReturnError:&error]) {
            NSLog(@"[XcodePluginLoader] Skipping %@ ([NSBundle load] failed (%@))", potentialBundleName, error);
            return;
        }
        
        NSLog(@"[XcodePluginLoader] Loaded %@", potentialBundleName);

        // If the plugin implements `pluginDidLoad:`,
        // invoke it now
        Class principalClass = [bundle principalClass];
        if ([principalClass respondsToSelector:@selector(pluginDidLoad:)]) {
            NSLog(@"[XcodePluginLoader] Calling pluginDidLoad in %@", potentialBundleName);
            [principalClass pluginDidLoad:bundle];
        }
    }];
}

@end


