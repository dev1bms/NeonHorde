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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Present once the view has its real size — creating the scene in
        // viewDidLoad positions everything against pre-layout bounds.
        guard skView.scene == nil, view.bounds.width > 0 else { return }
        let scene = GameScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}
