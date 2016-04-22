import Foundation
import UIKit

var globalMainQueue: dispatch_queue_t {
    return dispatch_get_main_queue()
}
var globalUserInteractiveQueue: dispatch_queue_t {
    return dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0)
}
var globalUserInitiatedQueue: dispatch_queue_t {
    return dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
}
var globalUtilityQueue: dispatch_queue_t {
    return dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)
}
var globalBackgroundQueue: dispatch_queue_t {
    return dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)
}
var globalHighPriorityQueue: dispatch_queue_t {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
}

#if arch(i386) || arch(x86_64)
    private let deviceId = "SimulatorTesting"
#else
    private let deviceId = UIDevice.currentDevice().identifierForVendor!.UUIDString
#endif