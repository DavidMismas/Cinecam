import SwiftUI
import AVKit

struct CineVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var showsPlaybackControls: Bool = true
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = showsPlaybackControls
        controller.updatesNowPlayingInfoCenter = false
        controller.allowsPictureInPicturePlayback = false
        if #available(iOS 14.2, *) {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
        }
        controller.player = player
        return controller
    }
    
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.showsPlaybackControls = showsPlaybackControls
        controller.updatesNowPlayingInfoCenter = false
        controller.allowsPictureInPicturePlayback = false
        if #available(iOS 14.2, *) {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
        }
        
        if controller.player !== player {
            controller.player = player
        }
    }
    
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player = nil
    }
}
