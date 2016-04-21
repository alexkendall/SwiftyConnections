import Foundation
import UIKit

public protocol NetworkManagerDelegate {
    func didConnectToUser(user: User)
    func didDisconnectFromUser(user: User)
    func discoveredUser(user: User)
    func recievedConnectionRequestFromUser(user: User, autheticateHandler: (user: User, autheticate: Bool)->Void)
}