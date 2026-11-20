import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isBuiltIn: Bool
    let isEarPods: Bool
}

/// CoreAudio helper for listing and switching macOS default audio input (microphone) devices.
final class AudioInputManager {
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var isListening = false

    static func listInputDevices() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }
        let actualCount = min(count, Int(dataSize) / MemoryLayout<AudioDeviceID>.size)

        var result: [AudioInputDevice] = []
        for id in ids.prefix(actualCount) {
            guard inputChannelCount(for: id) > 0, let name = deviceName(for: id) else { continue }
            let uid = deviceUID(for: id).flatMap { $0.isEmpty ? nil : $0 } ?? name
            let transport = transportType(for: id)
            let isBuiltIn = (transport == kAudioDeviceTransportTypeBuiltIn)
            let isEarPods = name.localizedCaseInsensitiveContains("earpods")
            result.append(AudioInputDevice(id: id, uid: uid, name: name, isBuiltIn: isBuiltIn, isEarPods: isEarPods))
        }
        return result.sorted { a, b in
            if a.isBuiltIn != b.isBuiltIn { return a.isBuiltIn }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID) == noErr,
              devID != kAudioObjectUnknown else {
            return nil
        }
        return devID
    }

    @discardableResult
    static func setDefaultInputDevice(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var targetID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &targetID)
        return status == noErr
    }

    func startObserving(_ onChange: @escaping () -> Void) {
        stopObserving()
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            onChange()
        }
        listenerBlock = block

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, DispatchQueue.main, block)
        isListening = true
    }

    func stopObserving() {
        guard isListening, let block = listenerBlock else { return }
        isListening = false
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, DispatchQueue.main, block)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, DispatchQueue.main, block)
        listenerBlock = nil
    }

    // MARK: - Private CoreAudio queries

    private static func inputChannelCount(for id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr,
              Int(size) >= MemoryLayout<AudioBufferList>.size else {
            return 0
        }
        let capacity = Int(size)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr,
              Int(size) >= MemoryLayout<AudioBufferList>.size,
              Int(size) <= capacity else {
            return 0
        }
        let listPtr = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard let mBuffersOffset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers) else {
            return 0
        }
        let bufferCount = Int(listPtr.pointee.mNumberBuffers)
        let requiredBytes = mBuffersOffset + bufferCount * MemoryLayout<AudioBuffer>.stride
        guard bufferCount >= 0, Int(size) >= requiredBytes else {
            return 0
        }
        let buffers = UnsafeMutableAudioBufferListPointer(listPtr)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func deviceName(for id: AudioDeviceID) -> String? {
        stringProperty(for: id, selector: kAudioObjectPropertyName)
    }

    private static func deviceUID(for id: AudioDeviceID) -> String? {
        stringProperty(for: id, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func stringProperty(for id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var valueRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &valueRef) == noErr,
              let cfStr = valueRef?.takeRetainedValue() else {
            return nil
        }
        return cfStr as String
    }

    private static func transportType(for id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else {
            return 0
        }
        return value
    }
}
