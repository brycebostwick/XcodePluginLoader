/**
 This class is not actually implemented anywhere (neither here nor in Xcode);
 we're just using it to indicate the expected interface of a plugin bundle's
 principal class.
 */
@interface XcodePlugin

- (void)pluginDidLoad:(NSBundle *)bundle;

@end
