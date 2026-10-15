import CoreAudio
import Foundation

/// Tracks the default output device's volume and mute state for "Keep loudness constant".
/// Listener based (no polling); only runs while that preference is on.
@MainActor final class SystemVolumeMonitor {
    private(set) var volume: Float = 1
    private(set) var isMuted = false
    var onChange: (@MainActor () -> Void)?

    private var isStarted = false
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var deviceAddresses: [AudioObjectPropertyAddress] = []

    private static var defaultDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.rebind() }
        }
        var address = Self.defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        defaultDeviceListener = block
        rebind()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        removeDeviceListeners()
        if let block = defaultDeviceListener {
            var address = Self.defaultDeviceAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
        defaultDeviceListener = nil
    }

    // MARK: - Private

    private func rebind() {
        guard isStarted else { return }
        removeDeviceListeners()
        deviceID = Self.defaultOutputDevice()
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else {
            refresh()
            return
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        var addresses: [AudioObjectPropertyAddress] = []
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            addresses.append(Self.address(kAudioDevicePropertyVolumeScalar, element: element))
        }
        addresses.append(Self.address(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain))

        for candidate in addresses {
            var address = candidate
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            if AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block) == noErr {
                deviceAddresses.append(address)
            }
        }
        deviceListener = block
        refresh()
    }

    private func removeDeviceListeners() {
        if let block = deviceListener {
            for var address in deviceAddresses {
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
            }
        }
        deviceAddresses = []
        deviceListener = nil
    }

    private func refresh() {
        if deviceID != AudioObjectID(kAudioObjectUnknown) {
            volume = Self.readVolume(deviceID) ?? 1
            isMuted = Self.readMute(deviceID) ?? false
        } else {
            volume = 1
            isMuted = false
        }
        onChange?()
    }

    private static func address(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var address = defaultDeviceAddress
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr ? id : AudioObjectID(kAudioObjectUnknown)
    }

    /// Main element volume, or the average of channels 1 and 2 when the device has no main control.
    private static func readVolume(_ device: AudioObjectID) -> Float? {
        if let main = readFloat(device, address(kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain)) {
            return main
        }
        let channels = [1, 2].compactMap { readFloat(device, address(kAudioDevicePropertyVolumeScalar, element: $0)) }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float(channels.count)
    }

    private static func readMute(_ device: AudioObjectID) -> Bool? {
        var muteAddress = Self.address(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &muteAddress) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static func readFloat(_ device: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Float? {
        var address = addr
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
