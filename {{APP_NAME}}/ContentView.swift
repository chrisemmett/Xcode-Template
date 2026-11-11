import {{MODULE_NAME}}Core
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text(Greeting(name: "{{DISPLAY_NAME}}").text)
            .font(.largeTitle)
            .padding()
    }
}

#Preview {
    ContentView()
}
