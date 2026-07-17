# Build Instructions

## Xcode Setup

1. Open Xcode and create a new macOS App project named "YuLingDongDao"
2. Set deployment target to macOS 26.0
3. Replace the generated files with the source files from this directory
4. Set Objective-C Bridging Header: `$(SRCROOT)/Services/MediaRemoteBridge.h`
5. Add `-framework MediaRemote` to Other Linker Flags (Build Settings > Other Linker Flags)
6. Disable Hardened Runtime OR add entitlement: `com.apple.security.cs.disable-library-validation`
7. Build and run on a MacBook Pro with notch

## Permissions

The app may need Accessibility permissions for some features. Grant in System Settings > Privacy & Security > Accessibility.
