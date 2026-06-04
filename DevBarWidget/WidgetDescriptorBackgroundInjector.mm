#import "WidgetDescriptorBackgroundInjector.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <TargetConditionals.h>

static NSDictionary<NSString *, NSDictionary *> *_kindBackgroundStyles;

@interface DevBarDescriptorFetchResult : NSObject <NSSecureCoding> {
@public
    NSArray *_activityDescriptors;
    NSArray *_controlDescriptors;
    NSArray *_widgetDescriptors;
}
@end

@implementation DevBarDescriptorFetchResult

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        Class baseDescriptorClass = objc_lookUpClass("CHSBaseDescriptor");
        Class controlDescriptorClass = objc_lookUpClass("CHSControlDescriptor");
        Class widgetDescriptorClass = objc_lookUpClass("CHSWidgetDescriptor");

        NSArray *activityDescriptors = [coder decodeObjectOfClasses:
            [NSSet setWithObjects:NSArray.class, baseDescriptorClass, nil]
            forKey:@"activityDescriptors"];
        NSArray *controlDescriptors = [coder decodeObjectOfClasses:
            [NSSet setWithObjects:NSArray.class, controlDescriptorClass, nil]
            forKey:@"controlDescriptors"];
        NSArray *widgetDescriptors = [coder decodeObjectOfClasses:
            [NSSet setWithObjects:NSArray.class, widgetDescriptorClass, nil]
            forKey:@"widgetDescriptors"];
        NSLog(@"[WidgetBG] initWithCoder: activity=%lu, control=%lu, widget=%lu",
              (unsigned long)activityDescriptors.count,
              (unsigned long)controlDescriptors.count,
              (unsigned long)widgetDescriptors.count);

        NSMutableArray *updatedDescriptors = [[NSMutableArray alloc] initWithCapacity:widgetDescriptors.count];
        for (id descriptor in widgetDescriptors) {
            NSString *kind = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)
                (descriptor, sel_registerName("kind"));
            NSDictionary *styleInfo = _kindBackgroundStyles[kind];
            if (!styleInfo) {
                [updatedDescriptors addObject:descriptor];
                continue;
            }

            id mutableDescriptor = [descriptor mutableCopy];
            reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)
                (mutableDescriptor, sel_registerName("setBackgroundRemovable:"), YES);
            reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)
                (mutableDescriptor, sel_registerName("setTransparent:"), YES);

            NSUInteger style = [styleInfo[@"style"] unsignedIntegerValue];
            if ([styleInfo[@"vibrant"] boolValue]) {
                reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)
                    (mutableDescriptor, sel_registerName("setSupportsVibrantContent:"), YES);
            }
            reinterpret_cast<void (*)(id, SEL, NSUInteger)>(objc_msgSend)
                (mutableDescriptor, sel_registerName("setPreferredBackgroundStyle:"), style);

            [updatedDescriptors addObject:mutableDescriptor];
            [mutableDescriptor release];
            NSLog(@"[WidgetBG] Applied style 0x%lx to %@", (unsigned long)style, kind);
        }

        _activityDescriptors = [activityDescriptors retain];
        _controlDescriptors = [controlDescriptors retain];
        _widgetDescriptors = [updatedDescriptors copy];
        [updatedDescriptors release];
    }
    return self;
}

- (void)dealloc {
    [_activityDescriptors release];
    [_controlDescriptors release];
    [_widgetDescriptors release];
    [super dealloc];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_activityDescriptors forKey:@"activityDescriptors"];
    [coder encodeObject:_controlDescriptors forKey:@"controlDescriptors"];
    [coder encodeObject:_widgetDescriptors forKey:@"widgetDescriptors"];
}

@end

namespace DevBarDescriptorInjection {
    void (*original)(id, SEL, id);

    void replacement(id self, SEL command, void (^completion)(id fetchResult)) {
        original(self, command, ^(id originalResult) {
            NSLog(@"[WidgetBG] getAllCurrentDescriptorsWithCompletion called");
            NSError *error = nil;
            NSKeyedArchiver *sourceArchiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
            [originalResult encodeWithCoder:sourceArchiver];
            NSData *sourceData = sourceArchiver.encodedData;
            [sourceArchiver release];
            NSLog(@"[WidgetBG] Step 1: archived %lu bytes", (unsigned long)sourceData.length);

            NSKeyedUnarchiver *sourceUnarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:sourceData error:&error];
            if (error) {
                NSLog(@"[WidgetBG] Step 2 FAILED: unarchive error: %@", error);
                [sourceUnarchiver release];
                completion(originalResult);
                return;
            }

            DevBarDescriptorFetchResult *updatedResult = [[DevBarDescriptorFetchResult alloc] initWithCoder:sourceUnarchiver];
            [sourceUnarchiver release];
            NSLog(@"[WidgetBG] Step 2: created result, widgetDescriptors: %lu",
                  (unsigned long)updatedResult->_widgetDescriptors.count);

            NSKeyedArchiver *updatedArchiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
            [updatedResult encodeWithCoder:updatedArchiver];
            NSData *updatedData = updatedArchiver.encodedData;
            [updatedArchiver release];
            [updatedResult release];
            NSLog(@"[WidgetBG] Step 3: re-archived %lu bytes", (unsigned long)updatedData.length);

            NSKeyedUnarchiver *updatedUnarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:updatedData error:&error];
            if (error) {
                NSLog(@"[WidgetBG] Step 4 FAILED: unarchive error: %@", error);
                [updatedUnarchiver release];
                completion(originalResult);
                return;
            }

            Class originalClass = objc_lookUpClass("_TtC9WidgetKit21DescriptorFetchResult");
            if (!originalClass) {
                originalClass = objc_lookUpClass("_TtCC9WidgetKit24DescriptorFetchResult");
            }
            if (!originalClass) {
                originalClass = [originalResult class];
            }
            NSLog(@"[WidgetBG] Step 4: using class: %@", NSStringFromClass(originalClass));

            id finalResult = reinterpret_cast<id (*)(id, SEL, id)>(objc_msgSend)
                ([originalClass alloc], @selector(initWithCoder:), updatedUnarchiver);
            [updatedUnarchiver release];

            if (finalResult) {
                NSLog(@"[WidgetBG] Step 5: calling completion with modified result");
                completion(finalResult);
                [finalResult release];
            } else {
                NSLog(@"[WidgetBG] Step 5 FAILED: nil result, falling back to original");
                completion(originalResult);
            }
        });
    }

    void install() {
        const char *classNames[] = {
            "_TtCC9WidgetKit24WidgetExtensionXPCServer14ExportedObject",
            "_TtC9WidgetKit21WidgetExtensionXPCServer14ExportedObject",
            "_TtCC9WidgetKit21WidgetExtensionXPCServer14ExportedObject",
            NULL
        };

        Class targetClass = nil;
        for (int index = 0; classNames[index] != NULL; index++) {
            targetClass = objc_lookUpClass(classNames[index]);
            if (targetClass) {
                NSLog(@"[WidgetBG] Found class: %s", classNames[index]);
                break;
            }
        }

        SEL selector = sel_registerName("getAllCurrentDescriptorsWithCompletion:");
        if (!targetClass) {
            unsigned int classCount = 0;
            Class *classes = objc_copyClassList(&classCount);
            for (unsigned int index = 0; index < classCount; index++) {
                if (class_getInstanceMethod(classes[index], selector)) {
                    targetClass = classes[index];
                    break;
                }
            }
            free(classes);
        }

        Method method = targetClass ? class_getInstanceMethod(targetClass, selector) : nil;
        if (!method) {
            NSLog(@"[WidgetBG] No target class found");
            return;
        }

        original = reinterpret_cast<decltype(original)>(method_getImplementation(method));
        method_setImplementation(method, reinterpret_cast<IMP>(replacement));
        NSLog(@"[WidgetBG] Swizzled successfully");
    }
}

@implementation WidgetDescriptorBackgroundInjector
@end

__attribute__((constructor))
static void InstallDevBarWidgetDescriptorBackgroundInjector(void) {
#if TARGET_OS_IOS
    _kindBackgroundStyles = @{
        @"DevBarTransparentWidget": @{ @"style": @(0x1), @"vibrant": @NO },
        @"DevBarLiquidGlassWidget": @{ @"style": @(0x2), @"vibrant": @YES },
        @"DevBarDarkWidget": @{ @"style": @(0x1), @"vibrant": @NO },
    };
    NSLog(@"[WidgetBG] Constructor starting");
    DevBarDescriptorInjection::install();
    NSLog(@"[WidgetBG] Constructor completed");
#endif
}
