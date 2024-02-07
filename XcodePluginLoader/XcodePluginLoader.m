#import "XcodePluginLoader.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "ClassLoadObserver.h"
#import "XcodeHeaders/DVTPlugInManager.h"
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

    // Wait for `DVTPlugInManager` to load before performing actual plugin loading
    __weak typeof(self) weakSelf = self;
    self.classLoadObserver = [ClassLoadObserver observerForClasses:@[@"DVTPlugInManager"] completion:^{
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

        // Run compatibility check using `DTXcodeBuildCompatibleVersions` (needed for Xcode 15.3+)
        NSString *xcodeBuildVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"DTXcodeBuild"];
        NSArray<NSString *> *compatibleBuildVersions = [bundle objectForInfoDictionaryKey:@"DTXcodeBuildCompatibleVersions"];
        BOOL hasCompatibleBuildVersion = NO;
        if (compatibleBuildVersions) {
            if (![compatibleBuildVersions isKindOfClass:[NSArray class]]) {
                NSLog(@"[XcodePluginLoader] Skipping %@ (invalid DTXcodeBuildCompatibleVersions format)", potentialBundleName);
                return;
            }

            compatibleBuildVersions = [compatibleBuildVersions sortedArrayUsingSelector:@selector(length)];
            for (NSString *buildVersion in compatibleBuildVersions) {
                if ([xcodeBuildVersion isEqualToString:buildVersion]) {
                    hasCompatibleBuildVersion = YES;
                    NSLog(@"[XcodePluginLoader] %@ is compatible with DTXcodeBuild version %@", potentialBundleName, xcodeBuildVersion);
                    break;
                }

                // Apple sometimes releases multiple builds of Xcode using the same version number
                // (e.g., some people will have Xcode 13.3b1 with a build number of "15E5178i", others
                // may have "15E5178b"). Treat the lowercase suffix as optional
                if ([xcodeBuildVersion hasPrefix:buildVersion]) {
                    NSString *unmatchedBuildVersionString = [xcodeBuildVersion substringFromIndex:[buildVersion length]];
                    NSCharacterSet *nonLowercaseLetters = [[NSCharacterSet lowercaseLetterCharacterSet] invertedSet];
                    NSRange rangeOfNonLowercaseLetters = [unmatchedBuildVersionString rangeOfCharacterFromSet:nonLowercaseLetters];
                    if (rangeOfNonLowercaseLetters.location == NSNotFound) {
                        hasCompatibleBuildVersion = YES;
                        NSLog(@"[XcodePluginLoader] %@ is compatible because Xcode has a more-specific DTXcodeBuild version (Xcode version %@, compatible version: %@)", potentialBundleName, xcodeBuildVersion, buildVersion);
                        break;
                    }
                }
            }
        }

        // Fall back to doing a compatibility check using `DVTPlugInCompatibilityUUIDs`
        // (matches Xcode's original plugin loader behavior, but is only available on Xcode 15.2 or older)
        if (!hasCompatibleBuildVersion) {
            NSLog(@"[XcodePluginLoader] No DTXcodeBuildCompatibleVersions in %@ matching version %@. Falling back to DVTPlugInCompatibilityUUIDs", potentialBundleName, xcodeBuildVersion);

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


