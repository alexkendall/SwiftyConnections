import Foundation
import UIKit
var API_KEY = "AIzaSyAXZPtC6-dil00BN8pjWL2n7Mzj-jVGf74"

class NetworkManager {
    let messageManager = GNSMessageManager(APIKey: API_KEY)
    let deviceID =  UIDevice.currentDevice().identifierForVendor?.UUIDString
    var subscription: GNSSubscription!
    var hostTimer: NSTimer!
    
    init(mode: NetworkMode) {
        switch mode {
        case .Offline:
            goOffline()
            break
        case .Client:
            browseAsClient()
            break
        case .Host:
            advertiseAsHost()
            break
        }
    }
    func advertiseAsHost() {
        subscription = nil
        if hostTimer != nil {
            hostTimer.invalidate()
        }
    }
    func browseAsClient() {
        subscription = nil
        subscription = messageManager.subscriptionWithMessageFoundHandler({
            message in self.handleMessage(message)
            }, messageLostHandler: {_ in})
        
    }
    func goOffline() {
        subscription = nil
        if hostTimer != nil {
            hostTimer.invalidate()
        }
    }
    func handleMessage(message: GNSMessage) {
        print(message)
    }
    
}