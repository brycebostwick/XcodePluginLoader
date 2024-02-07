#import <Foundation/Foundation.h>

@interface XcodePluginLoader : NSObject

/**
 Starts the plugin loading process.

 Plugins may be loaded at some point after this method is called,
 in the event that we need to wait for certain Xcode frameworks be loaded first.
 */
- (void)start;

@end
