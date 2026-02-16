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
                        
                        Picker("Output Aspect Ratio", selection: $cameraManager.selectedOutputAspectRatio) {
                            ForEach(OutputAspectRatioOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(CineTheme.orange)
                        
                        HStack {
                            Text("Codec")
                            Spacer()
                            Text("HEVC (H.265)")
                                .foregroundColor(CineTheme.textSecondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Recording Bitrate")
                                Spacer()
                                Text("\(Int(cameraManager.recordingBitrateMbps.rounded())) Mbps")
                                    .foregroundColor(CineTheme.textSecondary)
                            }
                            
                            Slider(
                                value: $cameraManager.recordingBitrateMbps,
                                in: CameraManager.bitrateRangeMbps,
                                step: 5
                            )
                            .tint(CineTheme.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Render Bitrate")
                                Spacer()
                                Text("\(Int(cameraManager.renderBitrateMbps.rounded())) Mbps")
                                    .foregroundColor(CineTheme.textSecondary)
                            }
                            
                            Slider(
                                value: $cameraManager.renderBitrateMbps,
                                in: CameraManager.bitrateRangeMbps,
                                step: 5
                            )
                            .tint(CineTheme.orange)
                        }
                        
                        Text("Higher bitrate = larger files and better detail retention. Actual max quality still depends on device codec limits.")
                            .font(.footnote)
                            .foregroundColor(CineTheme.textSecondary)
                    }
                    .listRowBackground(CineTheme.darkGray)

                    Section(header: Text("Camera").foregroundColor(CineTheme.orange)) {
                        Toggle("Software Stabilization (Crop)", isOn: $cameraManager.useSoftwareStabilization)
                        
                        Text("On: smoother footage with digital crop. Off: no software stabilization crop.")
                            .font(.footnote)
                            .foregroundColor(CineTheme.textSecondary)
                        
                        Toggle("Lock White Balance While Recording", isOn: $cameraManager.lockWhiteBalanceDuringRecording)

                        Text("When enabled, white balance is fixed for the full recording and returns to auto after recording stops.")
                            .font(.footnote)
                            .foregroundColor(CineTheme.textSecondary)
                    }
                    .listRowBackground(CineTheme.darkGray)
                    
                    Section(header: Text("About").foregroundColor(CineTheme.orange)) {
                        Text("Cinerec v1.0")
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
