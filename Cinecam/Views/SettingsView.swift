import SwiftUI

struct SettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                CineTheme.darkBackground.edgesIgnoringSafeArea(.all)
                
                Form {
                    Section(header: Text("Video Format").foregroundColor(CineTheme.orange)) {
                        Picker("Frame Rate", selection: $cameraManager.selectedFrameRate) {
                            Text("30 FPS").tag(30)
                            Text("60 FPS").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .tint(CineTheme.orange)
                        
                        Toggle("Apple ProRes", isOn: $cameraManager.useProRes)
                    }
                    .listRowBackground(CineTheme.darkGray)
                    
                    Section(header: Text("About").foregroundColor(CineTheme.orange)) {
                        Text("Cinecam v1.0")
                            .foregroundColor(.white)
                    }
                    .listRowBackground(CineTheme.darkGray)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationBarTitle("Settings", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .accentColor(CineTheme.orange)
    }
}
