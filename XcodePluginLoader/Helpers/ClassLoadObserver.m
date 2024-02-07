#import "ClassLoadObserver.h"

@interface ClassLoadObserver ()

@property (nonatomic, strong, nonnull) NSMutableSet<NSString *> *remainingClasses;
@property (nonatomic, copy, nonnull) void (^completion)(void);
@property (nonatomic, strong, nullable) id<NSObject> bundleObserver;

@end

@implementation ClassLoadObserver

+ (nonnull instancetype)observerForClasses:(nonnull NSArray<NSString *> *)classes completion:(nonnull void (^)(void))completion {
    return [[ClassLoadObserver alloc] initWithClasses:classes completion:completion];
}

- (instancetype)initWithClasses:(nonnull NSArray<NSString *> *)classes completion:(nonnull void (^)(void))completion {
    if (self = [super init]) {
        _remainingClasses = [NSMutableSet setWithArray:classes];
        _completion = completion;

        [self processExistingClasses];
    }

    return self;
}

- (void)processExistingClasses {
    // Find classes that have already been loaded
    NSMutableSet *alreadyLoadedClasses = [[NSMutableSet alloc] init];

    for (NSString *class in self.remainingClasses) {
        if (NSClassFromString(class)) {
            [alreadyLoadedClasses addObject:class];
        }
    }

    // Remove already-loaded classes from the set of
    // classes that we're still waiting for
    [self.remainingClasses minusSet:alreadyLoadedClasses];

    // If there are no classes left, we're actually finished!
    if (!self.remainingClasses.count) {
        self.completion();
    } else {
        [self setupBundleObserver];
    }
}

- (void)setupBundleObserver {
    __weak typeof(self) weakSelf = self;
    self.bundleObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSBundleDidLoadNotification
                                                    object:nil
                                                     queue:nil
                                                usingBlock:^(NSNotification * _Nonnull notification) {
        typeof(self) strongSelf = weakSelf;
        [strongSelf processNewClasses];
    }];
}

/**
 We could normally look at `NSLoadedClasses` from the bundle load notification,
 but there seems to exist a race condition where the classes we look for might not yet be loaded,
 but we also never receive a bundle notification for them. Easier to just check all classes every time.
 */
- (void)processNewClasses {
    NSMutableSet *alreadyLoadedClasses = [[NSMutableSet alloc] init];

    for (NSString *class in self.remainingClasses) {
        if (NSClassFromString(class)) {
            [alreadyLoadedClasses addObject:class];
        }
    }

    // Remove already-loaded classes from the set of
    // classes that we're still waiting for
    [self.remainingClasses minusSet:alreadyLoadedClasses];

    if (!self.remainingClasses.count) {
        [NSNotificationCenter.defaultCenter removeObserver:self.bundleObserver];
        self.bundleObserver = nil;
        self.completion();
    }
}

@end
