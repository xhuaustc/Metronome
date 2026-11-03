import SwiftUI

@main
struct PianoMetronomeApp: App {

    @StateObject private var viewModel = MetronomeViewModel()

    var body: some Scene {
        WindowGroup {
            MetronomeView(vm: viewModel)
        }
    }
}
