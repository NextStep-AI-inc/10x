import Testing
@testable import TenXApp

@MainActor @Test func activatingANewOwnerStopsThePreviousOwner() async {
    let registry = ComputerUseRegistry()
    let first = TestComputerUseOwner()
    let second = TestComputerUseOwner()

    await registry.activate(first) { owner in
        await owner.stopComputerUse()
    }
    await registry.activate(second) { owner in
        await owner.stopComputerUse()
    }

    #expect(first.stopCount == 1)
    #expect(second.stopCount == 0)
}

@MainActor @Test func releasingANonActiveOwnerDoesNotClearTheCurrentOwner() async {
    let registry = ComputerUseRegistry()
    let first = TestComputerUseOwner()
    let second = TestComputerUseOwner()
    let third = TestComputerUseOwner()

    await registry.activate(first) { owner in
        await owner.stopComputerUse()
    }
    await registry.activate(second) { owner in
        await owner.stopComputerUse()
    }
    registry.release(first)
    await registry.activate(third) { owner in
        await owner.stopComputerUse()
    }

    #expect(first.stopCount == 1)
    #expect(second.stopCount == 1)
    #expect(third.stopCount == 0)
}

@MainActor @Test func registryDoesNotRetainAnInactiveOwner() async {
    let registry = ComputerUseRegistry()
    var first: TestComputerUseOwner? = TestComputerUseOwner()

    await registry.activate(first!) { owner in
        await owner.stopComputerUse()
    }
    first = nil

    let second = TestComputerUseOwner()
    await registry.activate(second) { owner in
        await owner.stopComputerUse()
    }

    #expect(second.stopCount == 0)
}

@MainActor
private final class TestComputerUseOwner: ComputerUseStopping {
    private(set) var stopCount = 0

    func stopComputerUse() async {
        stopCount += 1
    }
}
