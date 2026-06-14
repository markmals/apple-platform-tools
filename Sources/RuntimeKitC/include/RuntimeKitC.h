#pragma once

#import <Foundation/Foundation.h>

// SPEC: command.uitool.inspect
// The native safety floor for value-fetching. Invoking a property getter via KVC
// can raise an Objective-C exception (NSUnknownKeyException, and others a custom
// getter may throw) that Swift cannot catch — an uncaught ObjC exception is a hard
// crash. This shim wraps the call in @try/@catch so a throwing getter degrades to
// nil instead of taking down the inspected app. (A getter that *hangs* the main
// thread is handled by the caller's bounded main-thread hop, not here.)
NS_ASSUME_NONNULL_BEGIN

/// `[object valueForKey:key]`, returning nil if the getter raises rather than
/// letting the exception cross into Swift (where it would crash).
id _Nullable uitool_safe_value_for_key(id object, NSString *key);

NS_ASSUME_NONNULL_END
