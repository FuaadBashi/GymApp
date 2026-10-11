import Foundation
import Testing
@testable import GymApp

private func set(_ kg: Double, _ reps: Int, _ type: SetType = .working) -> PastSet {
    PastSet(kg: kg, reps: reps, type: type)
}

private func close(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (a?, b?): abs(a - b) < 0.001
    default: false
    }
}

struct TrainingMathTests {
    @Test func epleyForFiftyByTenIsSixtySixPointSix() {
        #expect(close(TrainingMath.e1RM(kg: 50, reps: 10), 66.6667))
    }

    @Test func aSingleRepIsTheLoadItself() {
        #expect(close(TrainingMath.e1RM(kg: 100, reps: 1), 100))
    }

    @Test func displayableE1RMStopsAtTwelveReps() {
        #expect(close(TrainingMath.displayableE1RM(kg: 60, reps: 12, loadMode: .total), 84))
        #expect(TrainingMath.displayableE1RM(kg: 60, reps: 13, loadMode: .total) == nil)
    }

    @Test func bodyweightLoadsHaveNoDisplayableE1RM() {
        #expect(TrainingMath.displayableE1RM(kg: -45, reps: 6, loadMode: .bodyweightPlus) == nil)
    }

    @Test func assistanceIsSubtractedFromBodyWeight() {
        #expect(close(TrainingMath.calculationKg(-45, loadMode: .bodyweightPlus, bodyWeightKg: 90), 45))
        #expect(TrainingMath.calculationKg(-45, loadMode: .bodyweightPlus, bodyWeightKg: nil) == nil)
        #expect(close(TrainingMath.calculationKg(-100, loadMode: .bodyweightPlus, bodyWeightKg: 90), 0))
    }

    @Test func repsOnlyHasNoCalculationLoad() {
        #expect(TrainingMath.calculationKg(10, loadMode: .repsOnly, bodyWeightKg: 90) == nil)
    }

    @Test func perHandVolumeCountsBothHandsAndSkipsWarmUps() {
        #expect(close(TrainingMath.volumeKg([set(20, 10), set(20, 10, .warmUp)], loadMode: .perHand, bodyWeightKg: nil), 400))
    }

    @Test func assistedVolumeUsesBodyWeightMinusAssistance() {
        #expect(close(TrainingMath.volumeKg([set(-45, 6)], loadMode: .bodyweightPlus, bodyWeightKg: 90), 270))
    }

    @Test func repsOnlyVolumeIsZero() {
        #expect(close(TrainingMath.volumeKg([set(0, 12)], loadMode: .repsOnly, bodyWeightKg: 90), 0))
    }

    @Test func failedSetsCountTowardVolume() {
        #expect(close(TrainingMath.volumeKg([set(60, 8, .failed)], loadMode: .total, bodyWeightKg: nil), 480))
    }

    @Test func dropSegmentsCountTowardVolume() {
        #expect(close(TrainingMath.volumeKg([set(60, 8), set(40, 6, .drop)], loadMode: .total, bodyWeightKg: nil), 720))
    }

    @Test func bestsIgnoreWarmUps() {
        let b = TrainingMath.bests([set(100, 1, .warmUp), set(80, 5), set(70, 12)], loadMode: .total)
        #expect(close(b.heaviestKg, 80))
        #expect(close(b.bestE1RM, 98))
    }

    @Test func bestsIgnoreDropSegments() {
        let b = TrainingMath.bests([set(60, 8), set(90, 3, .drop)], loadMode: .total)
        #expect(close(b.heaviestKg, 60))
        #expect(close(b.bestE1RM, 76))
    }

    @Test func bodyweightExercisesHaveNoBests() {
        #expect(TrainingMath.bests([set(-45, 6)], loadMode: .bodyweightPlus) == TrainingMath.Bests())
    }

    @Test func musclesMapToTheirRegions() {
        #expect(Muscle.lowerBack.region == .lower)
        #expect(Muscle.traps.region == .upper)
        #expect(Muscle.abdominals.region == .core)
    }
}
