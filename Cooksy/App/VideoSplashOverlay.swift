import SwiftUI
import AVKit
import AVFoundation

/// Plays the bundled splash video (`SplashVideo.mp4` / `Cooksy-2.mp4`) full-screen,
/// then calls `onFinished` once it reaches the end. Used at the very top of the
/// view hierarchy so the same animation appears regardless of whether the user
/// is heading into onboarding, paywall, tutorial, or home.
struct VideoSplashOverlay: View {
    let onFinished: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let player {
                SplashVideoPlayerView(player: player)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .allowsHitTesting(true)
    }

    private func setupPlayer() {
        let supportedExtensions = ["mp4", "mov", "m4v"]
        var videoURL: URL?

        for ext in supportedExtensions {
            if let url = Bundle.main.url(forResource: "SplashVideo", withExtension: ext) {
                videoURL = url
                break
            }
        }

        guard let url = videoURL else {
            onFinished()
            return
        }

        let avPlayer = AVPlayer(url: url)
        avPlayer.actionAtItemEnd = .none

        // Prevent iOS from ducking Spotify / Apple Music / podcasts while
        // the splash plays. `.ambient` + `.mixWithOthers` means our audio
        // (if any) mixes silently with other apps instead of taking the
        // monopoly — the default `.soloAmbient` behaviour would duck
        // whatever the user was already listening to.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        avPlayer.isMuted = true
        avPlayer.volume = 0

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onFinished()
            }
        }

        self.player = avPlayer
        avPlayer.play()
    }
}

private struct SplashVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
