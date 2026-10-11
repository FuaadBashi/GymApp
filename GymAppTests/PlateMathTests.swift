import Testing
@testable import GymApp

struct PlateMathTests {
    let kg = PlateMath.defaultKg

    @Test func anExactLoad() {
        #expect(PlateMath.plates(target: 100, bar: 20, available: kg) == .init(perSide: [25, 15], achieved: 100, shortBy: 0))
        #expect(PlateMath.plates(target: 62.5, bar: 20, available: kg)?.perSide == [20, 1.25])
    }

    @Test func theClosestLoadBelow() {
        #expect(PlateMath.plates(target: 63, bar: 20, available: kg) == .init(perSide: [20, 1.25], achieved: 62.5, shortBy: 0.5))
    }

    @Test func theBarAloneOrLess() {
        #expect(PlateMath.plates(target: 20, bar: 20, available: kg) == .init(perSide: [], achieved: 20, shortBy: 0))
        #expect(PlateMath.plates(target: 15, bar: 20, available: kg) == nil)
    }

    @Test func pounds() {
        #expect(PlateMath.plates(target: 225, bar: 45, available: PlateMath.defaultLb)?.perSide == [45, 45])
    }

    @Test func platesSettingsParseAndIgnoreJunk() {
        #expect(AppSettings.plates("20, 25,x, 1.25 ,0") == [25, 20, 1.25])
    }
}
