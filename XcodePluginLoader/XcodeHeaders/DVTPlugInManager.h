/**
 Based on `DVTPlugInManager` class in Xcode 15.2
 */
@interface DVTPlugInManager: NSObject

+ (DVTPlugInManager *)defaultPlugInManager;
- (NSUUID *)plugInHostUUID;

@end
