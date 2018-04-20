//
//  UIStoryboard+Swizzling.m
//  DITranquillity
//
//  Created by Alexander Ivlev on 27/08/2017.
//  Copyright © 2017 Alexander Ivlev. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <DITranquillity/DITranquillity-Swift.h>

@interface UICollectionView (Swizzling)
@end

@implementation UICollectionView (Swizzling)

+ (void)load {
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        [self swizzleOriginalSelector:@selector(dequeueReusableCellWithReuseIdentifier:forIndexPath:)
                     swizzledSelector:@selector(di_dequeueReusableCellWithReuseIdentifier:forIndexPath:)];
    });
}


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


-(NSDIContainer *)diContainer {
    return (NSDIContainer *)objc_getAssociatedObject(self, [_DIStoryboardBase RESOLVER_UNIQUE_VC_KEY]);
}


- (__kindof UICollectionViewCell *)di_dequeueReusableCellWithReuseIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath {
  UICollectionViewCell *cell = [self di_dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
  [[self diContainer] injectInto:cell];
  return cell;
}


@end
