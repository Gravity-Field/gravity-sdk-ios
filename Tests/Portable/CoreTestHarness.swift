import Foundation

// Runs the same regression cases where the Command Line Tools lack XCTest.
class XCTestCase {}
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value(), "Expected true", file: file, line: line)
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value(), "Expected false", file: file, line: line)
}
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value() == nil, "Expected nil", file: file, line: line)
}
func XCTAssertNotNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value() != nil, "Expected value", file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ value: @autoclosure () -> T, _ expected: @autoclosure () -> T, file: StaticString = #file, line: UInt = #line) {
    precondition(value() == expected(), "Values differ", file: file, line: line)
}
func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    preconditionFailure(message, file: file, line: line)
}
func XCTUnwrap<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let value else { preconditionFailure("Expected value", file: file, line: line) }
    return value
}

@main struct CoreTestHarness {
    static func main() async throws {
        let gate = InAppPresentationGateTests()
        gate.testConcurrentChooseReservesCampaignOnce()
        try gate.testVisibleCloseKeepsReservationUntilAcknowledgementAndRejectsStaleResponse()
        try gate.testFailedPresentationAndCloseBeforeVisibilityReleaseCampaign()
        try gate.testScreenChangeReleasesDelayedChooseAndOldCancellationCannotReleaseNewOwner()
        try gate.testIdentityResetInvalidatesOldRequestAndLateAcknowledgement()
        try gate.testAckFencesAlreadyReservedUnpresentedResponse()
        try gate.testLateDiscardCannotReleaseReplacementOpening()
        try gate.testMissingAcknowledgementExpiresAndCampaignsAreIndependent()
        try gate.testVisibleOfflineReservationDoesNotExpireOnNavigation()
        try gate.testReloadedQueueAcknowledgementFencesStaleRequestsButAllowsFreshViews()
        try gate.testQueueArrivingAfterReservationCannotPresentAndOldUserAckCannotUnlock()
        let delivery = VisibleImpressionDeliveryTests()
        await delivery.testConcurrentCallbacksShareDeliveryAndSuccessIsNotResent()
        await delivery.testTransientErrorsRetryThreeTimesBeforeSuccess()
        await delivery.testPartialFailureDoesNotResendSuccessfulUrlsAndDoesNotCacheFailure()
        await delivery.testPermanentErrorAndEmptyUrlsCannotAcknowledge()
        await delivery.testCancelledTransportDoesNotCacheSuccess()
        let transport = EngagementTransportTests()
        await transport.testActualHttpTransportRetries500And429AndAccepts204()
        await transport.testActualHttp400CannotAcknowledgeOrRetry()
        await transport.testMalformedUrlCannotAcknowledge()
        try await transport.testDurableHttp400AndInvalidUrlDropWithoutAcknowledgement()
        let modal = ModalVisibleImpressionTests()
        try await modal.testFastExplicitCloseAndStepSignalsFireOnce()
        modal.testFailedPersistenceStopsFurtherFrameAndCloseAttempts()
        modal.testUnappearedAndInactiveDisposalReleasesWithoutImpression()
        modal.testExplicitCloseAfterInactiveFrameKeepsConfirmedImpression()
        modal.testConcurrentDetectorAndCloseUseOneAtomicFlag()
        let durable = DurableVisibleImpressionTests()
        try await durable.testAsyncRestoreAndEnqueueProtectBeforeDiskAndSendOnlyAfterPersistence()
        try await durable.testExponentialRetryCapsAndResetsOnNetworkRestoreAndInsert()
        try durable.testLegacyUserSnapshotIsRemovedOnLoadAndRewrite()
        try await durable.testOfflineCloseReloadRestoreAndUserSectionIsolation()
        try await durable.testPersistencePrecedesSendAndSuccessfulUrlsAreRemoved()
        try await durable.testQueuedEventWaitsForSdkStartAndThenDeliversOnce()
        try await durable.testFreshOpeningCanReuseUrlAfterAcknowledgement()
        try await durable.testPermanentRejectionDropsEventAndReleasesProtection()
        try await durable.testProtectionEndsAt24HoursAcrossRestartButDeliveryContinuesUntilSevenDays()
        try await durable.testInFlightSendCannotExtendProtectionPast24Hours()
        try durable.testByteCapacityEvictsOldestAndKeepsNewestWrimp()
        try durable.testNamespaceSweepIsBoundedAndPreservesFreshCurrentAndUnrelatedFiles()
        try await durable.testExpiredQueueReleasesVisibleReservationWithoutAckFence()
        try durable.testCorruptStoreIsQuarantinedAndMixedRecordsRecover()
        try durable.testUnreadableFileIsPreservedAndRetriedBeforeInsert()
        try durable.testQueueCapacityAndBackupExclusion()
        print("41 Swift core regression cases passed (portable harness)")
    }
}
