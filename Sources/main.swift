import Cocoa
import CoreAudio
import AVFoundation
import Carbon.HIToolbox

@main
struct MacMicMuteApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var isMuted = false
    var savedVolumes: [AudioDeviceID: Float32] = [:]
    var eventHotKeyRef: EventHotKeyRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menu bar app only
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusItem()
        updateMuteState()
        registerGlobalHotkey()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotkey()
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if statusItem.button != nil {
            updateIcon()
        }
        
        setupMenu()
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(title: isMuted ? "Unmute All Mics" : "Mute All Mics", action: #selector(toggleMute), keyEquivalent: "")
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Show detected microphones
        let devices = getAllInputDevices()
        if !devices.isEmpty {
            let headerItem = NSMenuItem(title: "Detected Microphones:", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)
            
            for deviceID in devices {
                let name = getDeviceName(deviceID: deviceID)
                let deviceItem = NSMenuItem(title: "  • \(name)", action: nil, keyEquivalent: "")
                deviceItem.isEnabled = false
                menu.addItem(deviceItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        let hotkeyItem = NSMenuItem(title: "Hotkey: ⌘⇧M", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Mac Mic Mute", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    func updateIcon() {
        if let button = statusItem.button {
            let symbolName = isMuted ? "mic.slash.fill" : "mic.fill"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isMuted ? "Muted" : "Unmuted")
            image?.isTemplate = true
            button.image = image
            button.toolTip = isMuted ? "Microphones Muted (⌘⇧M to toggle)" : "Microphones Active (⌘⇧M to toggle)"
        }
    }
    
    func updateMuteState() {
        let devices = getAllInputDevices()
        if let firstDevice = devices.first {
            isMuted = isDeviceMuted(deviceID: firstDevice)
        }
        updateIcon()
        setupMenu()
    }
    
    // MARK: - Global Hotkey (Cmd+Shift+M)
    
    func registerGlobalHotkey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4D4D4D), id: 1) // "MMMM"
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async {
                appDelegate.toggleMute()
            }
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        
        // Cmd+Shift+M = keycode 46 (M) with modifiers
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_M), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &eventHotKeyRef)
    }
    
    func unregisterGlobalHotkey() {
        if let hotKeyRef = eventHotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
    
    @objc func toggleMute() {
        isMuted.toggle()
        let devices = getAllInputDevices()
        
        for deviceID in devices {
            if isMuted {
                // Save current volume before muting
                savedVolumes[deviceID] = getDeviceVolume(deviceID: deviceID)
            }
            setDeviceMute(deviceID: deviceID, mute: isMuted)
        }
        
        updateIcon()
        setupMenu()
        
        // Visual feedback
        flashIcon()
    }
    
    @objc func quit() {
        // Unmute all before quitting (optional safety)
        NSApp.terminate(nil)
    }
    
    func flashIcon() {
        if let button = statusItem.button {
            let originalImage = button.image
            let flashSymbol = isMuted ? "mic.slash.circle.fill" : "mic.circle.fill"
            button.image = NSImage(systemSymbolName: flashSymbol, accessibilityDescription: nil)
            button.image?.isTemplate = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                button.image = originalImage
            }
        }
    }
    
    // MARK: - CoreAudio Functions
    
    func getAllInputDevices() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else { return [] }
        
        // Filter to only input devices
        return deviceIDs.filter { hasInputChannels(deviceID: $0) }
    }
    
    func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        
        guard status == noErr, dataSize > 0 else { return false }
        
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        
        let result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        
        guard result == noErr else { return false }
        
        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0
    }
    
    func isDeviceMuted(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Check if device supports mute
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else {
            // Fall back to checking volume
            return getDeviceVolume(deviceID: deviceID) == 0
        }
        
        var mute: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &mute)
        
        if status != noErr {
            return getDeviceVolume(deviceID: deviceID) == 0
        }
        
        return mute != 0
    }
    
    func setDeviceMute(deviceID: AudioDeviceID, mute: Bool) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Try hardware mute first
        if AudioObjectHasProperty(deviceID, &propertyAddress) {
            var isSettable: DarwinBoolean = false
            AudioObjectIsPropertySettable(deviceID, &propertyAddress, &isSettable)
            
            if isSettable.boolValue {
                var muteValue: UInt32 = mute ? 1 : 0
                let status = AudioObjectSetPropertyData(
                    deviceID,
                    &propertyAddress,
                    0,
                    nil,
                    UInt32(MemoryLayout<UInt32>.size),
                    &muteValue
                )
                if status == noErr { return }
            }
        }
        
        // Fall back to setting volume to 0
        setDeviceVolume(deviceID: deviceID, volume: mute ? 0.0 : 1.0)
    }
    
    func getDeviceVolume(deviceID: AudioDeviceID) -> Float32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        
        // Try master channel first
        if AudioObjectHasProperty(deviceID, &propertyAddress) {
            let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &volume)
            if status == noErr { return volume }
        }
        
        // Try channel 1
        propertyAddress.mElement = 1
        if AudioObjectHasProperty(deviceID, &propertyAddress) {
            let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &volume)
            if status == noErr { return volume }
        }
        
        return 1.0
    }
    
    func setDeviceVolume(deviceID: AudioDeviceID, volume: Float32) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var vol = volume
        
        // Try master channel first
        if AudioObjectHasProperty(deviceID, &propertyAddress) {
            var isSettable: DarwinBoolean = false
            AudioObjectIsPropertySettable(deviceID, &propertyAddress, &isSettable)
            if isSettable.boolValue {
                let status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
                if status == noErr { return }
            }
        }
        
        // Try individual channels
        for channel: UInt32 in 1...2 {
            propertyAddress.mElement = channel
            if AudioObjectHasProperty(deviceID, &propertyAddress) {
                var isSettable: DarwinBoolean = false
                AudioObjectIsPropertySettable(deviceID, &propertyAddress, &isSettable)
                if isSettable.boolValue {
                    AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
                }
            }
        }
    }
    
    func getDeviceName(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        
        if status == noErr, let cfName = name?.takeRetainedValue() {
            return cfName as String
        }
        return "Unknown Device"
    }
}
