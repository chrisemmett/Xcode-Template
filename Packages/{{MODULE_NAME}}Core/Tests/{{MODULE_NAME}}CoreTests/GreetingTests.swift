import Testing
@testable import {{MODULE_NAME}}Core

struct GreetingTests {
    @Test func greetsByName() {
        #expect(Greeting(name: "Ada").text == "Hello, Ada!")
    }

    @Test func trimsWhitespace() {
        #expect(Greeting(name: "  Ada \n").text == "Hello, Ada!")
    }

    @Test func blankNameStillGreets() {
        #expect(Greeting(name: "   ").text == "Hello!")
    }
}
