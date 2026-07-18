import AudioToolbox
import CoreAudio
import Foundation

/// Reads and writes the system's default output-device volume via CoreAudio.
///
/// The now-playing adapter has no volume command, so the island's volume slider
/// drives the system output volume instead — the same behavior other notch apps
/// use. All calls are cheap HAL property gets/sets on the default output device.
enum SystemAudio {
    /// The current default output device, or `nil` if none is available.
    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// The virtual-main-volume property address for a device's output scope.
    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Reads the current output volume as 0...1, or `nil` if it can't be read.
    static func currentVolume() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = volumeAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return status == noErr ? min(max(volume, 0), 1) : nil
    }

    /// Sets the output volume, clamped to 0...1. No-op if unsettable.
    static func setVolume(_ value: Float) {
        guard let device = defaultOutputDevice() else { return }
        var address = volumeAddress()
        guard AudioObjectHasProperty(device, &address) else { return }

        var isSettable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
              isSettable.boolValue else { return }

        var volume = Float32(min(max(value, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
    }
}
