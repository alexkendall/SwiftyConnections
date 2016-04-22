import Foundation
import UIKit

class PeerController: UITableViewController {
    static var sharedPeerController = PeerController(style: .Plain)
    let numRows = 6
    let peerTableCellId = "PeerTableCell"
    let multipeerCellId = "MultipeerCell"
    let headerCellId = "headerCell"
    var backgroundView: UIImageView!
    var cellBackgroundColor = UIColor.whiteColor()
    var selectedIndex = 2
    // Data Soucre
    override init(style: UITableViewStyle) {
        super.init(style: style)
        tableView.registerNib(UINib(nibName: "PeerTableCell", bundle: nil), forCellReuseIdentifier: peerTableCellId)
        tableView.registerNib(UINib(nibName: "MultipeerCell", bundle: nil), forCellReuseIdentifier: multipeerCellId)
        tableView.registerNib(UINib(nibName: "HeaderCell", bundle: nil), forCellReuseIdentifier: headerCellId)
        NetworkManager.sharedManager.connectedPeers.signal
            .observeNext({_ in
                self.tableView.reloadData()
            })
        tableView.separatorStyle = .None
        NetworkManager.sharedManager.delegate = self
        NetworkManager.sharedManager.connectedPeers
            .signal
            .observeNext({_ in
                self.tableView.reloadData()
            })
    }
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // Data Source
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return numRows
    }
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCellWithIdentifier(headerCellId, forIndexPath: indexPath) as? HeaderCell ?? HeaderCell()
            cell.headerLabel.text = "Connections"
            cell.backgroundColor = .blackColor()
            return cell
        }
        if indexPath.row == 1 {
            let cell = tableView.dequeueReusableCellWithIdentifier(peerTableCellId, forIndexPath: indexPath) as? PeerTableCell ?? PeerTableCell()
            cell.peerTable.configureRac(NetworkManager.sharedManager.connectedPeers.signal)
            return cell
        } else if indexPath.row == 2 {
            let cell = tableView.dequeueReusableCellWithIdentifier(multipeerCellId, forIndexPath: indexPath) as? MultipeerCell ?? MultipeerCell()
            cell.typeLabel.text = "OFFLINE"
            cell.icon.setGMDIcon(GMDType.GMDLock, forState: .Normal)
            if indexPath.row == selectedIndex {
                selectCellSelected(cell)
            } else {
                setCellUnselected(cell)
            }
            return cell
        } else if indexPath.row == 3 {
            let cell = tableView.dequeueReusableCellWithIdentifier(multipeerCellId, forIndexPath: indexPath) as? MultipeerCell ?? MultipeerCell()
            cell.typeLabel.text = "HOST"
            cell.icon.setGMDIcon(GMDType.GMDLeakAdd, forState: .Normal)
            cell.backgroundColor = cellBackgroundColor
            if indexPath.row == selectedIndex {
                selectCellSelected(cell)
            } else {
                setCellUnselected(cell)
            }
            return cell
        }
        else if indexPath.row == 4 {
            let cell = tableView.dequeueReusableCellWithIdentifier(multipeerCellId, forIndexPath: indexPath) as? MultipeerCell ?? MultipeerCell()
            cell.typeLabel.text = "CLIENT"
            cell.icon.setGMDIcon(GMDType.GMDSpeakerPhone, forState: .Normal)
            cell.backgroundColor = cellBackgroundColor
            if indexPath.row == selectedIndex {
                selectCellSelected(cell)
            } else {
                setCellUnselected(cell)
            }
            return cell
        } else {
            let cell = tableView.dequeueReusableCellWithIdentifier(multipeerCellId, forIndexPath: indexPath) as? MultipeerCell ?? MultipeerCell()
            cell.typeLabel.text = "ADVERTISE/BROWSE"
            cell.icon.setGMDIcon(GMDType.GMDImportExport, forState: .Normal)
            cell.backgroundColor = cellBackgroundColor
            if indexPath.row == selectedIndex {
                selectCellSelected(cell)
            } else {
                setCellUnselected(cell)
            }
            return cell
        }
    }
    private func selectCellSelected(cell: MultipeerCell) {
        cell.backgroundColor = .lightGrayColor()
        cell.icon.setTitleColor(.blackColor(), forState: .Normal)
        cell.typeLabel.textColor = .blackColor()
    }
    private func setCellUnselected(cell: MultipeerCell) {
        cell.backgroundColor = .whiteColor()
        cell.icon.setTitleColor(UIView().tintColor, forState: .Normal)
        cell.typeLabel.textColor = .blackColor()
    }
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        if indexPath.row == 2 {
            NetworkManager.sharedManager.enterSingleUser()
            print("Single User Mode Activated")
        } else if indexPath.row == 3 {
            NetworkManager.sharedManager.advertise()
            print("Host Mode Activated")
        } else if indexPath.row == 4 {
            NetworkManager.sharedManager.browse()
            print("Client Mode Activated ")
        } else if indexPath.row == 5 {
            NetworkManager.sharedManager.advertise()
            NetworkManager.sharedManager.browse()
        }
        selectedIndex = indexPath.row
        tableView.reloadData()
    }
    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        if indexPath.row == 0 {
            return 50.0
        }
        else if indexPath.row == 1 {
            return CGFloat(NetworkManager.sharedManager.connectedPeers.value.count ?? 0) * 75.0
        } else {
            return 120.0
        }
    }
}

extension PeerController: NetworkManagerDelegate {
    func didConnectToUser(user: User) {
        print("did connect to user \(user)")
    }
    func didDisconnectFromUser(user: User) {
        print("did disconnect from user \(user)")
    }
    func discoveredUser(user: User) {
        print("discovered user")
        user.printInfo()
    }
    func didRecieveMessage(message: String) {
        ChatController.sharedChatController.inbox.value.append(message)
        print("Recieved message: \(message)")
    }
    func recievedConnectionRequestFromUser(user: User, autheticateHandler: (user: User, autheticate: Bool) -> Void) {
        print("recieved connection request from user \(user)")
        let alertController = UIAlertController(title: "Connection Request", message: "Would you like to connect to \(user.displayName)", preferredStyle: .Alert)
        let acceptAction = UIAlertAction(title: "Accept", style: .Default, handler: {_ in
            autheticateHandler(user: user, autheticate: true)
        })
        let declineAction = UIAlertAction(title: "Decline", style: .Cancel, handler: {_ in })
        alertController.addAction(acceptAction)
        alertController.addAction(declineAction)
        tabController.presentViewController(alertController, animated: true, completion: nil)
    }
}