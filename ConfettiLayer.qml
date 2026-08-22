import QtQuick

// One screen's worth of paper.
//
// A fixed pool of pieces is stepped by hand every frame rather than handed to
// QtQuick's particle system: paper needs to tumble about its own horizontal
// axis, not just spin in the plane, and that axial flip — which squashes each
// piece to a line and back as it turns — is the whole difference between
// confetti and spinning sticks. Idle pieces are invisible and cost nothing,
// so the pool can sit loaded between bursts.
Item {
  id: layer

  property var palette: ["#ffffff"]
  property string style: "corners"
  property int pieceCount: 600
  // Room for a second burst thrown before the first has landed.
  readonly property int poolSize: Math.min(1600, Math.round(layer.pieceCount * 1.4))

  signal finished()

  property int alive: 0
  // Slot i holds the state for repeater.itemAt(i); null means free.
  property var pieces: new Array(700)
  property real clock: 0

  // Air drag is what makes paper fall slowly: terminal speed is gravity/drag,
  // so these two numbers together set the whole feel of the fall.
  readonly property real gravity: 1000
  readonly property real drag: 1.3

  function rnd(a, b) { return a + Math.random() * (b - a) }

  // Triangular distribution: values cluster in the middle instead of filling
  // a range evenly. Uniform speeds and angles give a burst hard, straight
  // edges — a visible wedge or box — where a real popper fades out at the
  // limits of its throw.
  function bell(a, b) { return a + (Math.random() + Math.random()) / 2 * (b - a) }
  function pickOne(arr) { return arr[Math.floor(Math.random() * arr.length)] }

  function makePiece() {
    var p = {}
    var w = layer.width
    var h = layer.height

    if (layer.style === "rain") {
      p.x = layer.rnd(-40, w + 40)
      p.y = layer.rnd(-h * 0.7, -20)
      p.vx = layer.rnd(-90, 90)
      p.vy = layer.rnd(80, 260)
    } else if (layer.style === "cannon") {
      // A cone from the bottom centre. Speed falls off towards the edges of
      // the cone, so the burst has a soft round front rather than a wedge.
      var spread = layer.bell(-1.05, 1.05)
      var ang = -Math.PI / 2 + spread
      var sp = h * layer.bell(1.1, 3.2) * (1 - 0.3 * Math.abs(spread))
      p.x = w / 2 + layer.rnd(-40, 40)
      p.y = h + layer.rnd(0, 30)
      p.vx = Math.cos(ang) * sp
      p.vy = Math.sin(ang) * sp
    } else {
      // Corners: the same cone as the cannon, fired twice — once from each
      // bottom corner, aimed diagonally up and inward at roughly 45°. Launch
      // speeds are given in screens-per-second, so the plume clears the top of
      // any monitor.
      var left = Math.random() < 0.5
      var cSpread = layer.bell(-0.85, 0.85)
      var cAng = (left ? -Math.PI / 4 : -3 * Math.PI / 4) + cSpread
      var cSp = h * layer.bell(1.3, 3.4) * (1 - 0.3 * Math.abs(cSpread))
      p.x = left ? layer.rnd(-30, 60) : w - layer.rnd(-30, 60)
      p.y = h + layer.rnd(0, 30)
      p.vx = Math.cos(cAng) * cSp
      p.vy = Math.sin(cAng) * cSp
    }

    var shape = Math.random()
    if (shape < 0.6) {            // paper rectangle
      p.w = layer.rnd(7, 13); p.h = layer.rnd(9, 16); p.r = 0
    } else if (shape < 0.85) {    // streamer
      p.w = layer.rnd(3, 5); p.h = layer.rnd(18, 30); p.r = 0
    } else {                      // dot
      p.w = layer.rnd(6, 11); p.h = p.w; p.r = p.w / 2
    }

    p.color = layer.pickOne(layer.palette)
    p.spin = layer.rnd(-200, 200)
    p.flip = layer.rnd(160, 760) * (Math.random() < 0.5 ? -1 : 1)
    p.zAngle = layer.rnd(0, 360)
    p.flipAngle = layer.rnd(0, 360)
    p.swayAmp = layer.rnd(20, 95)
    p.swayFreq = layer.rnd(1.5, 4.2)
    p.swayPhase = layer.rnd(0, 6.28)
    return p
  }

  function fire() {
    if (layer.width <= 0 || layer.height <= 0) return
    var placed = 0
    for (var i = 0; i < layer.poolSize && placed < layer.pieceCount; i++) {
      if (layer.pieces[i]) continue
      var p = layer.makePiece()
      layer.pieces[i] = p
      var item = repeater.itemAt(i)
      if (item) {
        item.width = p.w
        item.height = p.h
        item.radius = p.r
        item.color = p.color
        item.x = p.x
        item.y = p.y
        item.visible = true
      }
      placed++
    }
    layer.alive += placed
    if (layer.alive > 0) frames.running = true
  }

  function clear() {
    for (var i = 0; i < layer.poolSize; i++) {
      if (!layer.pieces[i]) continue
      layer.pieces[i] = null
      var item = repeater.itemAt(i)
      if (item) item.visible = false
    }
    layer.alive = 0
    frames.running = false
  }

  function step(dt) {
    layer.clock += dt
    var h = layer.height
    var w = layer.width
    var d = 1 - layer.drag * dt

    for (var i = 0; i < layer.poolSize; i++) {
      var p = layer.pieces[i]
      if (!p) continue

      p.vy = (p.vy + layer.gravity * dt) * d
      p.vx = p.vx * d
      var sway = p.swayAmp * Math.sin(layer.clock * p.swayFreq + p.swayPhase)
      p.x += (p.vx + sway) * dt
      p.y += p.vy * dt
      p.zAngle += p.spin * dt
      p.flipAngle += p.flip * dt

      var item = repeater.itemAt(i)
      if (p.y > h + 90 || p.x < -250 || p.x > w + 250) {
        layer.pieces[i] = null
        layer.alive--
        if (item) item.visible = false
        continue
      }
      if (item) {
        item.x = p.x
        item.y = p.y
        item.rotation = p.zAngle
        item.flipAngle = p.flipAngle
      }
    }

    if (layer.alive <= 0) {
      frames.running = false
      layer.clock = 0
      layer.finished()
    }
  }

  FrameAnimation {
    id: frames
    running: false
    // A long stall between frames would teleport every piece; better to lose
    // a moment of motion than to have the burst jump across the screen.
    onTriggered: layer.step(Math.min(frameTime, 0.05))
  }

  Repeater {
    id: repeater
    model: layer.poolSize

    Rectangle {
      // Tumble about the horizontal axis. Without projection this reads as a
      // squash to nothing and back, which is exactly how paper flips.
      property real flipAngle: 0
      visible: false
      antialiasing: true
      transform: Rotation {
        origin.x: width / 2
        origin.y: height / 2
        axis { x: 1; y: 0; z: 0 }
        angle: flipAngle
      }
    }
  }
}
