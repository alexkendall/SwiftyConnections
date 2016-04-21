import UIKit
import Foundation
import Underdark

public enum NetworkMode: String {
    case Host = "host"
    case Client = "client"
    case Offline = "offline"
}

public class User {
    var link: UDLink!
    var mode: NetworkMode!
    var id: String!
    var displayName: String!
    var connected: Bool = false
    init(userId: String, userlink: UDLink!, userMode: NetworkMode, isConnected: Bool, inName: String) {
        link = userlink
        mode = userMode
        id = userId
        connected = isConnected
        displayName = inName
    }
    func printInfo() {
        print("User\nId: \(id)\nNodeId: \(link.nodeId)\nType: \(mode.rawValue)\nConnected: \(connected)")
    }
}
