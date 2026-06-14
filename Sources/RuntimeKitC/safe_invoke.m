#import "RuntimeKitC.h"

// SPEC: command.uitool.inspect
id _Nullable uitool_safe_value_for_key(id object, NSString *key) {
  @try {
    return [object valueForKey:key];
  } @catch (__unused NSException *exception) {
    // A getter that raises (KVC non-compliance, or a custom accessor throwing) must
    // not crash the inspected app — degrade to nil.
    return nil;
  }
}
