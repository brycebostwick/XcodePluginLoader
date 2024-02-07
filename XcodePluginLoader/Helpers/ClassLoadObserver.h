#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Provides a mechanism for waiting for certain classes to be loaded
 before performing an action.

 E.g., for code that relies on an Xcode-provided class called `DVTPlugInManager`,
 which may not be available immediately, we can use:

 ```
 self.classLoadObserver = [ClassLoadObserver observerForClasses:@[@"DVTPlugInManager"] completion:^{
     // Use `DVTPlugInManager`
 }];
 ```
 */
@interface ClassLoadObserver : NSObject

+ (instancetype)observerForClasses:(NSArray<NSString *> *)classes completion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
