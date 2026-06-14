#import <Foundation/Foundation.h>

// SPEC: domain.uitool.boot
// The image-load shim. The ObjC runtime calls +load for every class in a freshly
// loaded image, so when the boot dylib is loaded (DYLD_INSERT at launch, or a
// remote dlopen at attach) this fires and starts the injected server. +load is
// used over a C constructor because the ObjC runtime guarantees it runs for any
// class in the image and the class metadata keeps the linker from stripping it.
//
// The work is delegated immediately to the Swift entry (uitool_boot_start), which
// starts the server on a background thread and returns — +load itself does no
// blocking work and touches no AppKit, per the boot constructor contract.
extern void uitool_boot_start(void);

@interface UIToolBootLoader : NSObject
@end

@implementation UIToolBootLoader
+ (void)load {
  uitool_boot_start();
}
@end
