//
//  NSObject+Swizzling.m
//  DITranquillity
//
//  Created by Admin on 27/08/2017.
//  Copyright © 2017 Alexander Ivlev. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface NSObject (Swizzling)
+ (void)swizzleOriginalSelector:(SEL)originalSelector swizzledSelector:(SEL)swizzledSelector; 
@end

@implementation NSObject (Swizzling)

+ (void)swizzleOriginalSelector:(SEL)originalSelector swizzledSelector:(SEL)swizzledSelector {
  
  Class class = [self class];
  
  Method originalMethod = class_getInstanceMethod(class, originalSelector);
  Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
  
  BOOL didAddMethod =
  class_addMethod(class,
                  originalSelector,
                  method_getImplementation(swizzledMethod),
                  method_getTypeEncoding(swizzledMethod));
  
  if (didAddMethod) {
    class_replaceMethod(class,
                        swizzledSelector,
                        method_getImplementation(originalMethod),
                        method_getTypeEncoding(originalMethod));
  } else {
    method_exchangeImplementations(originalMethod, swizzledMethod);
  }
}

@end
