import Foundation
import UIKit
import MultipeerConnectivity
import ReactiveCocoa
import enum Result.NoError
public typealias NoError = Result.NoError

class PeerTable: UITableView, UITableViewDataSource, UITableViewDelegate {
    let users: MutableProperty<[User]?> = MutableProperty(nil)
    let peerCellId = "peerCell"
    override init(frame: CGRect, style: UITableViewStyle) {
        super.init(frame: frame, style: .Plain)
        users.signal
            .ignoreNil()
            .observeNext {_ in
                print("Peers changed (table) with count \(self.users.value?.count ?? 0)")
                dispatch_async(globalMainQueue, {
                    self.reloadData()
                })
        }
        self.dataSource = self
        self.delegate = self
    }
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        users.signal
            .ignoreNil()
            .observeNext {_ in
                self.reloadData()
        }
        self.dataSource = self
        self.delegate = self
    }
    // MARK: Data Source
    func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == UITableViewCellEditingStyle.Delete {
            if NetworkManager.sharedManager.mode == .Host {
                // boot user
                NetworkManager.sharedManager.bootUser(users.value![indexPath.row])
            }
            if NetworkManager.sharedManager.mode == .Client {
                // disconnect
                NetworkManager.sharedManager.disconnectFromPeers()
            }
        }
    }
    func tableView(tableView: UITableView, titleForDeleteConfirmationButtonForRowAtIndexPath indexPath: NSIndexPath) -> String? {
        if NetworkManager.sharedManager.mode == .Client {
            return "DISCONNECT"
        } else {
            return "BOOT USER"
        }
    }
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return users.value?.count ?? 0
    }
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(peerCellId, forIndexPath: indexPath) as? PeerCell ?? PeerCell()
        if let user = users.value?[indexPath.row] {
            cell.peerLabel.text = user.displayName 
            if users.value![indexPath.row].connected {
                cell.peerLabel.text = "\(user.displayName) (Connected)"
            }
            cell.peerLabel.textColor = .blackColor()
            cell.connectButton.setGMDIcon(GMDType.GMDWifi, forState: .Normal)
            if user.connected {
                cell.connectButton.setTitleColor(UIView().tintColor, forState: .Normal)
            } else {
                cell.connectButton.setTitleColor(.lightGrayColor(), forState: .Normal)
            }
        }
        cell.userIDLabel.text = users.value![indexPath.row].id
        cell.backgroundColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        return cell
    }
    func configureRac(signal: Signal<[User]?, NoError>) {
        registerNib(UINib(nibName: "PeerCell", bundle: NSBundle.mainBundle()), forCellReuseIdentifier: peerCellId)
        users <~ signal
        users.signal
            .ignoreNil()
            .observeNext {_ in
                dispatch_async(globalMainQueue, {
                    self.reloadData()
                })
            }
        self.backgroundColor = .clearColor()
    }
    // MARK: Delegate
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return 75.0
    }
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let user = users.value![indexPath.row]
        print("attempting to send join request to peer \(user.id)")
        NetworkManager.sharedManager.askToConnectToPeer(users.value![indexPath.row])
    }
}
