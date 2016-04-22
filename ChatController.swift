import UIKit
import Foundation
import ReactiveCocoa

class ChatController: UITableViewController{
    var inbox: MutableProperty<[String]> = MutableProperty([String]())
    static var sharedChatController = ChatController()
    private var messageCellId = "messageCell"
    private var headerCellid = "headerCell"
    private var defaultCellId = "defaultCell"
    private var currentText: MutableProperty<String> = MutableProperty("")
    init() {
        super.init(style: .Plain)
        configureTableView()
    }
    override init(style: UITableViewStyle) {
        super.init(style: .Plain)
        configureTableView()
    }
    func configureTableView() {
        inbox.signal
            .observeNext({_ in
                self.tableView.reloadData()
            })
        tableView.registerNib(UINib(nibName: "MessageCell", bundle: nil), forCellReuseIdentifier: messageCellId)
        tableView.registerNib(UINib(nibName: "HeaderCell", bundle: nil), forCellReuseIdentifier: headerCellid)
        tableView.registerClass(UITableViewCell.self, forCellReuseIdentifier: defaultCellId)
        tableView.separatorStyle = .None
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 2 + inbox.value.count
    }
    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        if indexPath.row == 0 {
            return 50.0
        } else if indexPath.row == 1 {
            return 75.0
        } else {
            return 25.0
        }
    }
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCellWithIdentifier(headerCellid, forIndexPath: indexPath) as? HeaderCell ?? HeaderCell()
            cell.headerLabel.text = "Messages"
            cell.selectionStyle = .None
            cell.backgroundColor = .blackColor()
            return cell
        } else if indexPath.row == 1 {
            let cell = tableView.dequeueReusableCellWithIdentifier(messageCellId, forIndexPath: indexPath) as? MessageCell ?? MessageCell()
            cell.selectionStyle = .None
            cell.sendButton.setGMDIcon(GMDType.GMDSend, forState: .Normal)
            cell.sendButton.addTarget(self, action: #selector(self.sendMessage), forControlEvents: .TouchUpInside)
            cell.deleteButton.addTarget(self, action: #selector(self.clearInbox), forControlEvents: .TouchUpInside)
            currentText <~ cell.messageField.rac_textSignal()
                .toSignalProducer()
                .map{$0 as? String ?? ""}
                .flatMapError{_ in return SignalProducer<String, NoError>.empty}
            return cell
        } else {
            let cell = tableView.dequeueReusableCellWithIdentifier(defaultCellId, forIndexPath: indexPath)
            cell.textLabel?.text = inbox.value[indexPath.row - 2]
            return cell
        }
    }
    func sendMessage(){
        NetworkManager.sharedManager.sendMessageToPeers(currentText.value)
    }
    func clearInbox() {
        print("clearing inbox")
        inbox.value = []
    }
}