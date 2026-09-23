#ifndef TapBridge_h
#define TapBridge_h

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CATapDescription.h>

NS_ASSUME_NONNULL_BEGIN

// Declared in the SDK's AudioHardwareTapping.h under `#ifdef __OBJC__`, so Swift
// cannot see them through `import CoreAudio`; re-exported here for Swift.
API_AVAILABLE(macos(14.2))
extern OSStatus AudioHardwareCreateProcessTap(CATapDescription *inDescription, AudioObjectID *outTap);

API_AVAILABLE(macos(14.2))
extern OSStatus AudioHardwareDestroyProcessTap(AudioObjectID inTapID);

NS_ASSUME_NONNULL_END

#endif /* TapBridge_h */
