import AppKit
import SampleAppKit

// SPEC: domain.uitool.server
// The launchable oracle: a real NSApplication presenting the known-geometry scene,
// used as the cooperative injection target for `uitool launch` / `attach`. Built
// debug (get-task-allow, no hardened runtime), so it honors DYLD_INSERT and
// task_for_pid on a stock Mac. Accessory activation so a test run never steals
// focus; the windows still register with NSApp, which is what the walker reads.
MainActor.assumeIsolated {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let scene = SampleScene.make()
  scene.orderFront()
  _ = scene  // the run loop + NSApp keep the windows alive
  app.run()
}
