#import <Foundation/Foundation.h>

/**
 Based on `NSProcessInfo(PBXTSPlatformAdditions)` category in Xcode 15.2
 */
@interface NSProcessInfo (PBXTSPlatformAdditions)

- (NSString *)xcodeProductBuildVersion;

@end
