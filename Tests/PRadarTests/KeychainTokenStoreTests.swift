import Testing

@testable import PRadar

struct KeychainTokenStoreTests {
    private let store = KeychainTokenStore(service: "io.github.lucastenboom.PRadar.tests")

    @Test func savedTokenCanBeReadAndDeleted() throws {
        try store.save("first")
        try store.save("second")
        #expect(store.read() == "second")

        store.delete()
        #expect(store.read() == nil)
    }
}
