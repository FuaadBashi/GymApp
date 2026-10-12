import Foundation
import Testing
@testable import GymApp

struct SigningExpiryTests {
    /// Bytes like a real profile: binary CMS framing around an XML plist.
    private func profile(expiring date: Date) throws -> Data {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Name": "GymApp", "ExpirationDate": date, "TeamName": "Personal"],
                                                       format: .xml, options: 0)
        return Data([0x30, 0x82, 0x0D, 0x9A, 0x06, 0x09, 0x2A, 0x86]) + plist + Data([0xA0, 0x82, 0x03, 0x00, 0x30])
    }

    @Test func theExpiryIsReadFromAProfile() throws {
        let date = Date(timeIntervalSince1970: 1_791_000_000)
        #expect(SigningExpiry.expirationDate(fromProfile: try profile(expiring: date)) == date)
    }

    @Test func garbageHasNoExpiry() {
        #expect(SigningExpiry.expirationDate(fromProfile: Data("not a profile".utf8)) == nil)
        #expect(SigningExpiry.expirationDate(fromProfile: Data("<?xml version=\"1.0\"?><plist><dict></dict></plist>".utf8)) == nil)
    }

    @Test func theWarningStartsTwoDaysBefore() {
        let expiry = Date(timeIntervalSince1970: 1_791_000_000)
        #expect(SigningExpiry.warningStart(for: expiry) == expiry.addingTimeInterval(-172_800))
        #expect(SigningExpiry.state(expiry: expiry, now: expiry.addingTimeInterval(-172_801)) == .fine)
        #expect(SigningExpiry.state(expiry: expiry, now: expiry.addingTimeInterval(-172_800)) == .expiringSoon(expiry))
        #expect(SigningExpiry.state(expiry: expiry, now: expiry) == .expired(expiry))
        #expect(SigningExpiry.state(expiry: nil, now: expiry) == .fine)
    }

    @Test func theSimulatorHasNoProfile() {
        #expect(SigningExpiry.current(bundle: Bundle(for: BundleToken.self)) == nil)
    }
}

private final class BundleToken {}
