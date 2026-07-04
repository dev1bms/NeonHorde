import UIKit
import SpriteKit

final class GameViewController: UIViewController {
    private(set) var skView: SKView!

    override func loadView() {
        skView = SKView()
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 60
        skView.backgroundColor = Palette.uiBackground
        #if DEBUG
        skView.showsFPS = true
        skView.showsNodeCount = true
        skView.showsDrawCount = true
        #endif
        view = skView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Games legitimately keep the screen awake — joystick play can go
        // long stretches without new touch events (GOAL Phase 9 soak).
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Present once the view has its real size — creating the scene in
        // viewDidLoad positions everything against pre-layout bounds.
        guard skView.scene == nil, view.bounds.width > 0 else { return }
        // Harness arg — inert unless passed (store-screenshot builds are Release).
        let scene: SKScene = ProcessInfo.processInfo.arguments.contains("OPENLAB")
            ? UpgradeLabScene(size: view.bounds.size)
            : GameScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}
