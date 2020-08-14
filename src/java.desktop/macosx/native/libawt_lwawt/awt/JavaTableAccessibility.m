// Copyright 2000-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE file.

#include "jni.h"
#import "JavaRowAccessibility.h"
#import "JavaAccessibilityAction.h"
#import "JavaAccessibilityUtilities.h"
#import "JavaTextAccessibility.h"
#import "JavaTableAccessibility.h"
#import "JavaCellAccessibility.h"
#import "ThreadUtilities.h"

@implementation JavaTableAccessibility

- (NSString *)getPlatformAxElementClassName {
    return @"PlatformAxTable";
}

@end

@implementation PlatformAxTable

- (nullable NSArray<id<NSAccessibilityRow>> *)accessibilityRows {
    NSArray *children = [super accessibilityChildren];
    if (children == NULL) {
        return NULL;
    }
    JNIEnv *env = [ThreadUtilities getJNIEnv];
    jmethodID methodId = (*env)->GetMethodID(env, (*env)->GetObjectClass(env, [[self javaBase] component]), "getRowCount", "()Ljava/lang/Integer;");
    jint rowCount = (jint)(*env)->CallObjectMethod(env, [[self javaBase] component], methodId);
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:rowCount];
    int k = 0, cellCount = [children count] / rowCount;
    for (int i = 0; i < rowCount; i++) {
        NSMutableArray *cells = [NSMutableArray arrayWithCapacity:cellCount];
        NSMutableString *a11yName = @"row";
        CGFloat width = 0;
        for (int j = 0; j < cellCount; j++) {
            [cells addObject:[children objectAtIndex:k]];
            k += 1;
            width += [[children objectAtIndex:k] accessibilityFrame].size.width;
        }
        CGPoint point = [[cells objectAtIndex:0] accessibilityFrame].origin;
        CGFloat height = [[cells objectAtIndex:0] accessibilityFrame].size.height;
        NSAccessibilityElement *a11yRow = [NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityRowRole frame:NSRectFromCGRect(CGRectMake(point.x, point.y, width, height)) label:a11yName parent:self];
        [a11yRow setAccessibilityChildren:cells];
        for (JavaCellAccessibility *cell in cells) [cell setParent:a11yRow];
        [rows addObject:a11yRow];
    }
    (*env)->DeleteLocalRef(env, rowCount);
    (*env)->DeleteLocalRef(env, methodId);
    return rows;
}

/*
- (nullable NSArray<id<NSAccessibilityRow>> *)accessibilitySelectedRows {
    return [self accessibilitySelectedChildren];
}
 */

- (NSString *)accessibilityLabel {
    if (([super accessibilityLabel] == NULL) || [[super accessibilityLabel] isEqualToString:@""]) {
        return @"Table";
    }
    return [super accessibilityLabel];
}

/*
- (nullable NSArray<id<NSAccessibilityRow>> *)accessibilityVisibleRows;
- (nullable NSArray *)accessibilityColumns;
- (nullable NSArray *)accessibilityVisibleColumns;
- (nullable NSArray *)accessibilitySelectedColumns;

- (nullable NSArray *)accessibilitySelectedCells;
- (nullable NSArray *)accessibilityVisibleCells;
- (nullable NSArray *)accessibilityRowHeaderUIElements;
- (nullable NSArray *)accessibilityColumnHeaderUIElements;
 */

@end
