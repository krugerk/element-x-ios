//
// Copyright 2022 New Vector Ltd
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import SwiftUI

struct SettingsScreenCoordinatorParameters {
    weak var navigationStackCoordinator: NavigationStackCoordinator?
    weak var userIndicatorController: UserIndicatorControllerProtocol?
    let userSession: UserSessionProtocol
    let bugReportService: BugReportServiceProtocol
    let notificationSettings: NotificationSettingsProxyProtocol
    let appSettings: AppSettings
}

enum SettingsScreenCoordinatorAction {
    case dismiss
    case logout
    case clearCache
}

final class SettingsScreenCoordinator: CoordinatorProtocol {
    private let parameters: SettingsScreenCoordinatorParameters
    private var viewModel: SettingsScreenViewModelProtocol

    var callback: ((SettingsScreenCoordinatorAction) -> Void)?
    
    // MARK: - Setup
    
    init(parameters: SettingsScreenCoordinatorParameters) {
        self.parameters = parameters
        
        viewModel = SettingsScreenViewModel(userSession: parameters.userSession, appSettings: ServiceLocator.shared.settings)
        viewModel.callback = { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .close:
                self.callback?(.dismiss)
            case .account:
                self.presentAccountSettings()
            case .analytics:
                self.presentAnalyticsScreen()
            case .reportBug:
                self.presentBugReportScreen()
            case .about:
                self.presentLegalInformationScreen()
            case .sessionVerification:
                self.verifySession()
            case .developerOptions:
                self.presentDeveloperOptions()
            case .logout:
                self.callback?(.logout)
            case .notifications:
                self.presentNotificationSettings()
            }
        }
    }
    
    // MARK: - Public
    
    func toPresentable() -> AnyView {
        AnyView(SettingsScreen(context: viewModel.context))
    }
    
    // MARK: - Private
    
    private var accountSettingsPresenter: OIDCAccountSettingsPresenter?
    private func presentAccountSettings() {
        guard let accountURL = viewModel.context.viewState.accountURL else {
            MXLog.error("Account URL is missing.")
            return
        }
        
        guard let window = viewModel.context.viewState.window else {
            MXLog.error("The window is missing.")
            return
        }
        
        #if targetEnvironment(simulator)
        let canOpenURL = false // Safari can't access the cookie on the iOS 16 simulator 🤷‍♂️
        #else
        let canOpenURL = UIApplication.shared.canOpenURL(accountURL)
        #endif
        
        if canOpenURL {
            UIApplication.shared.open(accountURL)
        } else {
            // Fall back to an ASWebAuthenticationSession to handle the URL inside the app.
            accountSettingsPresenter = OIDCAccountSettingsPresenter(accountURL: accountURL, presentationAnchor: window)
            accountSettingsPresenter?.start()
        }
    }
    
    private func presentAnalyticsScreen() {
        let coordinator = AnalyticsSettingsScreenCoordinator(parameters: .init(appSettings: ServiceLocator.shared.settings,
                                                                               analytics: ServiceLocator.shared.analytics))
        parameters.navigationStackCoordinator?.push(coordinator)
    }
    
    private func presentBugReportScreen() {
        let params = BugReportScreenCoordinatorParameters(bugReportService: parameters.bugReportService,
                                                          userID: parameters.userSession.userID,
                                                          deviceID: parameters.userSession.deviceID,
                                                          userIndicatorController: parameters.userIndicatorController,
                                                          screenshot: nil,
                                                          isModallyPresented: false)
        let coordinator = BugReportScreenCoordinator(parameters: params)
        coordinator.completion = { [weak self] result in
            switch result {
            case .finish:
                self?.showSuccess(label: L10n.actionDone)
            default:
                break
            }
            
            self?.parameters.navigationStackCoordinator?.pop()
        }
        
        parameters.navigationStackCoordinator?.push(coordinator)
    }
    
    private func presentLegalInformationScreen() {
        parameters.navigationStackCoordinator?.push(LegalInformationScreenCoordinator(appSettings: parameters.appSettings))
    }
    
    private func verifySession() {
        guard let sessionVerificationController = parameters.userSession.sessionVerificationController else {
            fatalError("The sessionVerificationController should aways be valid at this point")
        }
        
        let verificationParameters = SessionVerificationScreenCoordinatorParameters(sessionVerificationControllerProxy: sessionVerificationController)
        let coordinator = SessionVerificationScreenCoordinator(parameters: verificationParameters)
        
        coordinator.callback = { [weak self] in
            self?.parameters.navigationStackCoordinator?.setSheetCoordinator(nil)
        }
        
        parameters.navigationStackCoordinator?.setSheetCoordinator(coordinator) { [weak self] in
            self?.parameters.navigationStackCoordinator?.setSheetCoordinator(nil)
        }
    }
    
    private func presentDeveloperOptions() {
        let coordinator = DeveloperOptionsScreenCoordinator()
        
        coordinator.callback = { [weak self] action in
            switch action {
            case .clearCache:
                self?.callback?(.clearCache)
            }
        }
        
        parameters.navigationStackCoordinator?.push(coordinator)
    }

    private func showSuccess(label: String) {
        parameters.userIndicatorController?.submitIndicator(UserIndicator(title: label))
    }
    
    private func presentNotificationSettings() {
        let notificationParameters = NotificationSettingsScreenCoordinatorParameters(navigationStackCoordinator: parameters.navigationStackCoordinator,
                                                                                     userSession: parameters.userSession,
                                                                                     userNotificationCenter: UNUserNotificationCenter.current(),
                                                                                     notificationSettings: parameters.notificationSettings,
                                                                                     isModallyPresented: false)
        let coordinator = NotificationSettingsScreenCoordinator(parameters: notificationParameters)
        parameters.navigationStackCoordinator?.push(coordinator)
    }
}
