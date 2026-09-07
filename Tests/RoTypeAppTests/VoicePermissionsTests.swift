import AVFoundation
import Testing
@testable import RoTypeApp

@Test @MainActor func permissionLabelsDistinguishGrantedDeniedPendingAndRestricted() {
    #expect(VoicePermissions.microphoneAuthorization(.authorized) == .granted)
    #expect(VoicePermissions.microphoneAuthorization(.denied) == .denied)
    #expect(VoicePermissions.microphoneAuthorization(.notDetermined) == .notRequested)
    #expect(VoicePermissions.microphoneAuthorization(.restricted) == .restricted)
    #expect(VoicePermissions.Authorization.granted.title == "已授权")
    for state in [VoicePermissions.Authorization.notRequested, .denied, .restricted, .unknown] {
        #expect(state.title != "已授权")
    }
}
