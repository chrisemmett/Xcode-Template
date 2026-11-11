import Testing
@testable import {{MODULE_NAME}}
import {{MODULE_NAME}}Core

// App-target tests: view models and formatting that need the app module.
// Domain logic belongs in Packages/{{MODULE_NAME}}Core, tested by `make test-core`.
struct SmokeTests {
    @Test func theAppSeesTheCorePackage() {
        #expect(Greeting(name: "Test").text == "Hello, Test!")
    }
}
