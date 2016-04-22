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
    required public init(inMode: NetworkMode) {
        //print("THIS DEVICE ID: \(deviceId)")
        super.init()
        mode = inMode
        usersInRange.signal
            .ignoreNil()
            .observeNext {userList in
                var hostList = [User]()
                for user in userList {
                    if self.mode == .Client {
                        if user.mode == .Host || user.connected {
                            hostList.append(user)
                        }
                    } else if self.mode == .Host {
                        if user.connected {
                            hostList.append(user)
                        }
                    }
                }
                if hostList.count > 0 {
                    self.connectedPeers.value = hostList
                }
        }
        if mode == .Client {
            searchAsClient()
        } else if mode == .Host {
            advertiseAsHost()
        } else {
            enterSingleUser()
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
    func advertiseAsHost() {
        disconnectFromPeers()
        usersInRange.value = []
        connectedPeers.value = []
        mode = .Host
        broadcastType()
        timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: #selector(NetworkManager.broadcastType), userInfo: nil, repeats: true)  // start advertising
    }
    func searchAsClient() {
        disconnectFromPeers()
        usersInRange.value = []
        connectedPeers.value = []
        timer.invalidate()
        mode = .Client
        broadcastType()
        timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: #selector(NetworkManager.broadcastType), userInfo: nil, repeats: true)  // start advertising
    }
    func enterSingleUser() {
        disconnectFromPeers()
        usersInRange.value = []
        connectedPeers.value = []
        timer.invalidate()
        mode = .Offline
        broadcastType()
        timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: #selector(NetworkManager.broadcastType), userInfo: nil, repeats: true)  // start advertising
    }
    func initTransport() {
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
    // MARK: Delegate
    public func transport(transport: UDTransport!, link: UDLink!, didReceiveFrame frameData: NSData!) {
        if mode == .Client || mode == .Host {
            let message = String(data: frameData, encoding: NSUTF8StringEncoding) ?? ""
            lastIncommingMessage.value = message
            if message.containsString("host_") {
                let id = getUserIDFromMessage(message)
                let displayName = getDisplayNameFromMessage(message)
                addUser(User(userId: id, userlink: link, userMode: .Host, isConnected: false, inName: displayName))
            } else if message.containsString("client_") {
                let id = getUserIDFromMessage(message)
                let displayName = getDisplayNameFromMessage(message)
                addUser(User(userId: id, userlink: link, userMode: .Client, isConnected: false, inName: displayName))
            } else if message.containsString("connectionrequest_") {
                let name = getDisplayNameFromMessage(message)
                let userId = getUserIDFromMessage(message)
                let user = User(userId: userId, userlink: link, userMode: NetworkMode.Client, isConnected: false, inName: name)
                if delegate != nil {
                    delegate.recievedConnectionRequestFromUser(user, autheticateHandler: self.authenticateUser)
                }
            } else if message.containsString("allow_") {
                let userId = getUserIDFromMessage(message)
                let name = getDisplayNameFromMessage(message)
                let user = User(userId: userId, userlink: link, userMode: NetworkMode.Host, isConnected: true, inName: name)
                // notify other use this user has connected to the other
                if delegate != nil {
                    delegate.didConnectToUser(user)
                }
                self.addUser(user)
                self.notifyConnected(user)
            } else if message.containsString("connected_") {
                let userId = getUserIDFromMessage(message)
                let name = getDisplayNameFromMessage(message)
                let user = User(userId: userId, userlink: link, userMode: NetworkMode.Client, isConnected: true, inName: name)
                if delegate != nil {
                    delegate.didConnectToUser(user)
                }
                self.addUser(user)
            } else if message.containsString("booted_") {
                let userId = getUserIDFromMessage(message)
                let name = getDisplayNameFromMessage(message)
                let user = User(userId: userId, userlink: link, userMode: NetworkMode.Client, isConnected: true, inName: name)
                self.removeUser(user)
                let alertController = UIAlertController()
                alertController.title = "Disconnected"
                alertController.message = "\(name) removed you from the queue."
                let declineAction = UIAlertAction(title: "Exit", style: UIAlertActionStyle.Cancel, handler: nil)
                alertController.addAction(declineAction)
            } else if message.containsString("disconnect_") {
                let userId = getUserIDFromMessage(message)
                let name = getDisplayNameFromMessage(message)
                let user = User(userId: userId, userlink: link, userMode: NetworkMode.Client, isConnected: true, inName: name)
                self.removeUser(user)
            } else {
                delegate.didRecieveMessage(message)
            }
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
        if user.id != deviceId {
            dispatch_async(dispatch_get_main_queue(), {
                if !self.usersInRangeExist() {
                    self.usersInRange.value = []
                }
                for i in 0..<self.usersInRange.value!.count {
                    if user.id == self.usersInRange.value![i].id {
                        if !self.usersInRange.value![i].connected && user.connected || (self.usersInRange.value![i].mode == .Client && user.mode == .Host) || (self.usersInRange.value![i].mode == .Host && user.mode == .Client) {
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
            let data = ("allow_\(deviceId)_\(self.displayName)").dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
            user.link.sendFrame(data)
        }
    }
    private func notifyConnected(user: User) {
        let data = ("connected_\(deviceId)_\(self.displayName)").dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
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
        if mode == .Client || mode == .Host {
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
            let data = ("connectionrequest_\(self.deviceId)_\(self.displayName))").dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
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
                if mode == .Client && user.mode == .Host {
                    let updatedUser = User(userId: user.id, userlink: user.link , userMode: user.mode, isConnected: false, inName: user.displayName)
                    usersInRange.value?.removeAtIndex(i)
                    usersInRange.value?.append(updatedUser)
                }
            }
        }
    }
    func bootUser(user: User) {
        let message = "booted_\(self.deviceId)_\(self.displayName))"
        let data = message.dataUsingEncoding(NSUTF8StringEncoding) ?? NSData()
        user.link.sendFrame(data)
        removeUser(user)
    }
    private func usersInRangeExist() -> Bool {
        return usersInRange.value != nil
    }
    private func getUserIDFromMessage(message: String) -> String {
        let filteredMessage = message
            .stringByReplacingOccurrencesOfString("booted_", withString: "")
            .stringByReplacingOccurrencesOfString("host_", withString: "")
            .stringByReplacingOccurrencesOfString("client_", withString: "")
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
            .stringByReplacingOccurrencesOfString("booted_", withString: "")
            .stringByReplacingOccurrencesOfString("host_", withString: "")
            .stringByReplacingOccurrencesOfString("client_", withString: "")
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
