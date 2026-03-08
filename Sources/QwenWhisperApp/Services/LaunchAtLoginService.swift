import Foundation
import ServiceManagement

final class LaunchAtLoginService: LaunchAtLoginManaging {
    func setEnabled(_ enabled: Bool) throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
