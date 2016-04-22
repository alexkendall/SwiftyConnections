import Foundation
import Underdark
import ReactiveCocoa
import Result

var loopNodes = [Int64]()
public class NetworkManager: NSObject, UDTransportDelegate {
    // MARK: Public Vars
    public let usersInRange: MutableProperty<[User]?> = MutableProperty(nil)
    public var connectedPeers: MutableProperty<[User]?> =  MutableProperty(nil)
    // MARK: Private Vars
    private var links: [UDLink] = []
    private var appId: Int32 = 123456
    private var nodeId: Int64 = 0
    private var transport: UDTransport!
    private let queue = dispatch_get_main_queue()
    private let lastIncommingMessage: MutableProperty<String> = MutableProperty("")
    private let displayName = UIDevice.currentDevice().name
    private var timer: NSTimer = NSTimer()
    private let deviceId = UIDevice.currentDevice().identifierForVendor!.UUIDString
    var mode: NetworkMode!
    static var sharedManager = NetworkManager(inMode: .Offline)
    public var delegate: NetworkManagerDelegate!
    
    
    // browse advertise logic tracking
    private let isBrowsing: MutableProperty<Bool> = MutableProperty(false)
    private let isAdvertising: MutableProperty<Bool> = MutableProperty(false)
    required public init(inMode: NetworkMode) {
        super.init()
        mode = inMode
        usersInRange.signal
            .ignoreNil()
            .observeNext {userList in
                var hostList = [User]()
                for user in userList {
                    user.printInfo()
                    if self.mode == .Browser || self.mode == .AdvertiserBrowser {
                        if user.mode == .Advertiser || user.mode == .AdvertiserBrowser {
                            hostList.append(user)
                        }
                    } else if self.mode == .Advertiser {
                        if user.connected {
                            hostList.append(user)
                        }
                    }
                }
                if hostList.count > 0 {
                    self.connectedPeers.value = hostList
                }
        }
        if mode == .Browser {
            browse()
        } else if mode == .Advertiser {
            advertise()
        } else if mode == .AdvertiserBrowser {
            advertiseBrowse()
        }
        initTransport()
        connectedPeers.signal
            .ignoreNil()
            .observeNext({peers in
                print("Peers value changed")
                for peer in peers {
                    peer.printInfo()
                }
            })
    }
    // MARK: Broweer/Advertise Functions
    public func advertise() {
        isAdvertising.value = true
        if isBrowsing.value {
            advertiseBrowse()
        } else {
            disconnectFromPeers()
            usersInRange.value = []
            connectedPeers.value = []
            mode = .Advertiser
            broadcastType()
            timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: #selector(NetworkManager.broadcastType), userInfo: nil, repeats: true)  // start advertising
        }
    }
    public func browse() {
        isBrowsing.value = true
        if isAdvertising.value {
            advertiseBrowse()
        } else {
            disconnectFromPeers()
            usersInRange.value = []
            connectedPeers.value = []
            timer.invalidate()
            mode = .Browser
            broadcastType()
            timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: #selector(NetworkManager.broadcastType), userInfo: nil, repeats: true)  // start advertising
        }
    }
    private func advertiseBrowse() {
        timer.invalidate()
        print("advertise and browse")
        mode = .AdvertiserBrowser
        broadcastType()
        timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: #selector(NetworkManager.broadcastType), userInfo: nil, repeats: true)
    }
    public func enterSingleUser() {
        disconnectFromPeers()
        usersInRange.value = []
        connectedPeers.value = []
        timer.invalidate()
        mode = .Offline
        broadcastType()
        timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: #selector(NetworkManager.broadcastType), userInfo: nil, repeats: true)
    }
    private func initTransport() {
        stopTransport()
        var buf: Int64 = 0
        repeat {
            arc4random_buf(&buf, sizeofValue(buf))
        } while buf == 0
        if buf < 0 {
            buf = -buf
        }
        nodeId = buf
        loopNodes.append(buf)
        let transportKinds = [UDTransportKind.Wifi.rawValue, UDTransportKind.Bluetooth.rawValue]
        transport = UDUnderdark.configureTransportWithAppId(appId, nodeId: nodeId, delegate: self, queue: dispatch_get_main_queue(), kinds: transportKinds)
        transport.start()
        print("starting transport")
    }
    // MARK: Transport Delegate
    public func transport(transport: UDTransport!, link: UDLink!, didReceiveFrame frameData: NSData!) {
        if mode == .Browser || mode == .Advertiser {
            let message = String(data: frameData, encoding: NSUTF8StringEncoding) ?? ""
            lastIncommingMessage.value = message
            if message.containsString("advertiserbrowser") {
                let id = getUserIDFromMessage(message)
                let displayName = getDisplayNameFromMessage(message)
                addUser(User(userId: id, userlink: link, userMode: .AdvertiserBrowser, isConnected: false, inName: displayName))
            } else if message.containsString("advertiser_") {
                let id = getUserIDFromMessage(message)
                let displayName = getDisplayNameFromMessage(message)
                addUser(User(userId: id, userlink: link, userMode: .Advertiser, isConnected: false, inName: displayName))
            } else if message.containsString("browser_") {
                let id = getUserIDFromMessage(message)
                let displayName = getDisplayNameFromMessage(message)
                addUser(User(userId: id, userlink: link, userMode: .Browser, isConnected: false, inName: displayName))
            } else if message.containsString("connectionrequest_") {
                let name = getDisplayNameFromMessage(message)
                let userId = getUserIDFromMessage(message)
                var mode: NetworkMode!
                if message.containsString("advetiserbrowser") {
                    mode = .AdvertiserBrowser
                } else {
                    mode = .Browser
                }
                let user = User(userId: userId, userlink: link, userMode: mode, isConnected: false, inName: name)
                if delegate != nil {
                    delegate.recievedConnectionRequestFromUser(user, autheticateHandler: self.authenticateUser)
                }
            } else if message.containsString("allow_") {
                let userId = getUserIDFromMessage(message)
                let name = getDisplayNameFromMessage(message)
                if message.containsString("advetiserbrowser") {
                    mode = .AdvertiserBrowser
                } else {
                    mode = .Browser
                }
                let user = User(userId: userId, userlink: link, userMode: mode, isConnected: false, inName: name)
                self.addUser(user)
                // notify other use this user has connected to the other
                if delegate != nil {
                    delegate.didConnectToUser(user)
                }
                self.notifyConnected(user)
            } else if message.containsString("connected_") {
                let userId = getUserIDFromMessage(message)
                let name = getDisplayNameFromMessage(message)
                if message.containsString("advetiserbrowser") {
                    mode = .AdvertiserBrowser
                } else {
                    mode = .Browser
                }
                let user = User(userId: userId, userlink: link, userMode: mode, isConnected: false, inName: name)
                self.addUser(user)
                if delegate != nil {
                    delegate.didConnectToUser(user)
                }
            } else {
                delegate.didRecieveMessage(message)
            }
            print("message: \(message)")
        }
    }
    public func transport(transport: UDTransport!, linkConnected link: UDLink!) {
        // check if link belongs to prexisting user, if not then add
        if usersInRangeExist() {
            for i in 0..<usersInRange.value!.count {
                if link.nodeId == usersInRange.value![i].link.nodeId || link.nodeId == nodeId {
                    return
                }
            }
        }
        addLink(link)
        broadcastType()
    }
    public func transport(transport: UDTransport!, linkDisconnected link: UDLink!) {
        removeLink(link)
        if connectedPeers.value != nil {
            for i in 0..<connectedPeers.value!.count {
                if connectedPeers.value![i].link.nodeId == link.nodeId {
                    connectedPeers.value?.removeAtIndex(i)
                }
            }
        }
        if usersInRange.value != nil {
            for i in 0..<usersInRange.value!.count {
                if usersInRange.value![i].link.nodeId == link.nodeId {
                    if delegate != nil {
                        delegate.didDisconnectFromUser(usersInRange.value![i])
                    }
                    usersInRange.value?.removeAtIndex(i)
                }
            }
        }
    }
    // MARK: Private functions
    private func disconnectFromUser(user: User) {
        dispatch_async(dispatch_get_main_queue(), {
            for i in 0..<self.connectedPeers.value!.count {
                if user.id == self.connectedPeers.value![i].id {
                    self.connectedPeers.value!.removeAtIndex(i)
                }
            }
        })
    }
    private func removeUser(user: User) {
        if connectedPeers.value != nil {
            if connectedPeers.value != nil {
                for i in 0..<connectedPeers.value!.count {
                    if user.id == connectedPeers.value![i].id {
                        connectedPeers.value!.removeAtIndex(i)
                    }
                }
            }
            if usersInRange.value != nil {
                for i in 0..<usersInRange.value!.count {
                    if user.id == usersInRange.value![i].id {
                        usersInRange.value!.removeAtIndex(i)
                    }
                }
            }
            
        }
    }
    private func addUser(user: User) {
        print("should add user)")
        user.printInfo()
        
        /*
        if user.id != deviceId {
            dispatch_async(dispatch_get_main_queue(), {
                if !self.usersInRangeExist() {
                    self.usersInRange.value = []
                }
                for i in 0..<self.usersInRange.value!.count {
                    if user.id == self.usersInRange.value![i].id {
                        if !self.usersInRange.value![i].connected && user.connected || (self.usersInRange.value![i].mode == .Browser && user.mode == .Advertiser) || (self.usersInRange.value![i].mode == .Advertiser && user.mode == .Browser) {
                            self.usersInRange.value?.removeAtIndex(i)
                            self.usersInRange.value?.append(user)
                            return
                        } else {
                            return
                        }
                    }
                }
                assert(self.usersInRange.value != nil)
                self.usersInRange.value?.append(user)
                if self.delegate != nil {
                    self.delegate.discoveredUser(user)
                }
            })
        } else {
            print("Detected Self over network")
        }
        */
    }
    private func removeLink(link: UDLink) {
        for i in 0..<links.count {
            if link.nodeId == links[i].nodeId {
                links.removeAtIndex(i)
            }
        }
        if usersInRangeExist() {
            for i in 0..<usersInRange.value!.count {
                if usersInRange.value![i].link.nodeId == link.nodeId {
                    removeUser(usersInRange.value![i])
                }
            }
        }
    }
    private func addLink(link: UDLink) {
        // if link already in list, return
        for i in 0..<links.count {
            if link.nodeId == links[i].nodeId {
                return
            }
        }
        links.append(link)
    }
    public func broadcastType() {
        let text = mode.rawValue + "_" + UIDevice.currentDevice().identifierForVendor!.UUIDString + "_" + displayName
        let data = text.dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
        if !links.isEmpty {
            for link in links {
                link.sendFrame(data)
            }
        }
    }
    public func authenticateUser(user: User, autheticate: Bool) {
        if autheticate {
            let data = ("\(user.mode.rawValue)allow_\(deviceId)_\(self.displayName)").dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
            user.link.sendFrame(data)
        }
    }
    private func notifyConnected(user: User) {
        let data = ("\(user.mode.rawValue)connected_\(deviceId)_\(self.displayName)").dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
        user.link.sendFrame(data)
    }
    func stopTransport() {
        if transport != nil {
            transport.stop()
            timer.invalidate()
        }
    }
    // MARK: Public Functions
    func sendMessageToPeers(text: String) {
        let data = text.dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
        if mode == .Browser || mode == .Advertiser {
            if usersInRangeExist() {
                if connectedPeers.value != nil {
                    for peer in connectedPeers.value! {
                        if peer.connected {
                            peer.link.sendFrame(data)
                        }
                    }
                }
            }
        }
    }
    func askToConnectToPeer(user: User) {
        dispatch_async(dispatch_get_global_queue(qos_class_main(), 0), {
            let data = ("\(self.mode.rawValue)connectionrequest_\(self.deviceId)_\(self.displayName))").dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
            user.link.sendFrame(data)
        })
    }
    func disconnectFromPeers() {
        let message = "disconnect_\(self.deviceId)_\(self.displayName)"
        let data = message.dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
        if usersInRange.value != nil {
            for i in 0..<usersInRange.value!.count {
                usersInRange.value![i].link.sendFrame(data)
                let user = usersInRange.value![i]
                if mode == .Browser && user.mode == .Advertiser {
                    let updatedUser = User(userId: user.id, userlink: user.link , userMode: user.mode, isConnected: false, inName: user.displayName)
                    usersInRange.value?.removeAtIndex(i)
                    usersInRange.value?.append(updatedUser)
                }
            }
        }
    }
    private func usersInRangeExist() -> Bool {
        return usersInRange.value != nil
    }
    private func getUserIDFromMessage(message: String) -> String {
        let filteredMessage = message
            .stringByReplacingOccurrencesOfString("advertiser", withString: "")
            .stringByReplacingOccurrencesOfString("advertiser_", withString: "")
            .stringByReplacingOccurrencesOfString("browser_", withString: "")
            .stringByReplacingOccurrencesOfString("connectionrequest_", withString: "")
            .stringByReplacingOccurrencesOfString("allow_", withString: "")
            .stringByReplacingOccurrencesOfString("current", withString: "")
            .stringByReplacingOccurrencesOfString("connected_", withString: "")
            .stringByReplacingOccurrencesOfString("disconnect_", withString: "")
            .stringByReplacingOccurrencesOfString(")", withString: "")
        var index = 0
        for c in filteredMessage.characters {
            if c == "_" {
                break
            }
            index += 1
        }
        // use index to split message
        //print("USER ID: \(filteredMessage.substringToIndex(filteredMessage.startIndex.advancedBy(index)))")
        return filteredMessage.substringToIndex(filteredMessage.startIndex.advancedBy(index))
    }
    private func getDisplayNameFromMessage(message: String) -> String {
        let filteredMessage = message
            .stringByReplacingOccurrencesOfString("advertiser", withString: "")
            .stringByReplacingOccurrencesOfString("advertiser_", withString: "")
            .stringByReplacingOccurrencesOfString("browser_", withString: "")
            .stringByReplacingOccurrencesOfString("connectionrequest_", withString: "")
            .stringByReplacingOccurrencesOfString("allow_", withString: "")
            .stringByReplacingOccurrencesOfString("current", withString: "")
            .stringByReplacingOccurrencesOfString("connected_", withString: "")
            .stringByReplacingOccurrencesOfString("disconnect_", withString: "")
            .stringByReplacingOccurrencesOfString(")", withString: "")
        var index = 0
        for c in filteredMessage.characters {
            if c == "_" {
                break
            }
            index += 1
        }
        // use index to split message
        //print("DISPLAY NAME: \(filteredMessage.substringFromIndex(filteredMessage.startIndex.advancedBy(index+1)))")
        return filteredMessage.substringFromIndex(filteredMessage.startIndex.advancedBy(index+1))
    }
}
