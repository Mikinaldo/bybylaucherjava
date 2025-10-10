//
//  bybylaucherjava-Bridging-Header.h
//  bybylaucherjava
//
//  Created by macos on 03/09/2025.
//

#ifndef bybylaucherjava_Bridging_Header_h
#define bybylaucherjava_Bridging_Header_h
#import <Foundation/Foundation.h>

// ============================
// Export functions
// ============================
id createDynamicObject(NSArray<NSString*>* methods);
void callDynamicMethod(id obj, NSString *selName);
void registerCallbackForMethod(NSString *methodName, void (^callback)(id));

#endif /* bybylaucherjava_Bridging_Header_h */
