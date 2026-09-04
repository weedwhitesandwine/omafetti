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
  // Not `layer`: every Item carries a built-in `layer` grouped property, and
  // inside the Repeater delegate below — a separate component — the delegate's
  // own properties are resolved before this file's ids. `layer.glyphFamily`
  // there found QQuickItemLayer instead of this object and evaluated to
  // undefined, silently leaving every glyph in the fallback font.
  id: field

  property var palette: ["#ffffff"]
  property string style: "corners"
  // Every piece of paper is a letter instead: each one takes a glyph at
  // random from `word`, so the screen fills with tumbling O M A R C H Y.
  property bool letterStorm: false
  property string word: "OMARCHY"
  // Passed in rather than named here so the letters take the shell's own font
  // instead of one hardcoded here. A proportional family is fine: a piece is
  // sized from its line height alone, so a wide glyph simply overflows its
  // transparent rectangle — the tumble is about the horizontal axis through
  // the centre, and culling tests position rather than width.
  property string glyphFamily: "monospace"
  property int pieceCount: 600
  // Room for a second burst thrown before the first has landed.
  readonly property int wantedPoolSize: Math.min(1600, Math.round(field.pieceCount * 1.4))

  // The pool only ever changes size while it is empty, so poolSize is set
  // rather than bound. Shrinking it with pieces still in the air would strand
  // every slot above the new size: step() would stop visiting them, so they
  // would never be freed and never decrement `alive`, finished() would never
  // be emitted, and the frame callback would keep running for the life of the
  // shell process. Density is changed from the settings card, which is exactly
  // when a burst can still be falling.
  property int poolSize: 0
  Component.onCompleted: field.poolSize = field.wantedPoolSize
  onWantedPoolSizeChanged: field.applyPoolSize()

  function applyPoolSize() {
    if (field.poolSize === field.wantedPoolSize || field.alive > 0) return
    field.clear()
    field.poolSize = field.wantedPoolSize
  }

  signal finished()

  property int alive: 0
  // Slot i holds the state for repeater.itemAt(i); null means free.
  property var pieces: new Array(1600)
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
    var w = field.width
    var h = field.height

    if (field.style === "rain") {
      p.x = field.rnd(-40, w + 40)
      p.y = field.rnd(-h * 0.7, -20)
      p.vx = field.rnd(-90, 90)
      p.vy = field.rnd(80, 260)
    } else if (field.style === "cannon") {
      // A cone from the bottom centre. Speed falls off towards the edges of
      // the cone, so the burst has a soft round front rather than a wedge.
      var spread = field.bell(-1.05, 1.05)
      var ang = -Math.PI / 2 + spread
      var sp = h * field.bell(1.1, 3.2) * (1 - 0.3 * Math.abs(spread))
      p.x = w / 2 + field.rnd(-40, 40)
      p.y = h + field.rnd(0, 30)
      p.vx = Math.cos(ang) * sp
      p.vy = Math.sin(ang) * sp
    } else {
      // Corners: the same cone as the cannon, fired twice — once from each
      // bottom corner, aimed diagonally up and inward at roughly 45°. Launch
      // speeds are given in screens-per-second, so the plume clears the top of
      // any monitor.
      var left = Math.random() < 0.5
      var cSpread = field.bell(-0.85, 0.85)
      var cAng = (left ? -Math.PI / 4 : -3 * Math.PI / 4) + cSpread
      var cSp = h * field.bell(1.3, 3.4) * (1 - 0.3 * Math.abs(cSpread))
      p.x = left ? field.rnd(-30, 60) : w - field.rnd(-30, 60)
      p.y = h + field.rnd(0, 30)
      p.vx = Math.cos(cAng) * cSp
      p.vy = Math.sin(cAng) * cSp
    }

    if (field.letterStorm) {
      // Sized over a wide range so the fall has depth to it: a field of
      // identical glyphs reads as a texture rather than as falling paper.
      var lh = field.rnd(16, 46)
      p.letter = field.word.charAt(Math.floor(Math.random() * field.word.length))
      p.w = lh * 0.72; p.h = lh; p.r = 0
      p.color = field.pickOne(field.palette)
      p.spin = field.rnd(-200, 200)
      p.flip = field.rnd(160, 760) * (Math.random() < 0.5 ? -1 : 1)
      p.zAngle = field.rnd(0, 360)
      p.flipAngle = field.rnd(0, 360)
      p.swayAmp = field.rnd(20, 95)
      p.swayFreq = field.rnd(1.5, 4.2)
      p.swayPhase = field.rnd(0, 6.28)
      return p
    }

    var shape = Math.random()
    if (shape < 0.6) {            // paper rectangle
      p.w = field.rnd(7, 13); p.h = field.rnd(9, 16); p.r = 0
    } else if (shape < 0.85) {    // streamer
      p.w = field.rnd(3, 5); p.h = field.rnd(18, 30); p.r = 0
    } else {                      // dot
      p.w = field.rnd(6, 11); p.h = p.w; p.r = p.w / 2
    }

    p.color = field.pickOne(field.palette)
    p.letter = ""
    p.spin = field.rnd(-200, 200)
    p.flip = field.rnd(160, 760) * (Math.random() < 0.5 ? -1 : 1)
    p.zAngle = field.rnd(0, 360)
    p.flipAngle = field.rnd(0, 360)
    p.swayAmp = field.rnd(20, 95)
    p.swayFreq = field.rnd(1.5, 4.2)
    p.swayPhase = field.rnd(0, 6.28)
    return p
  }

  // Returns whether anything was actually thrown: a layer whose panel has not
  // been given a size yet must not be counted as flying, or the burst is
  // recorded as in progress and never lands.
  function fire() {
    if (field.width <= 0 || field.height <= 0) return false
    var placed = 0
    for (var i = 0; i < field.poolSize && placed < field.pieceCount; i++) {
      if (field.pieces[i]) continue
      var p = field.makePiece()
      field.pieces[i] = p
      var item = repeater.itemAt(i)
      if (item) {
        item.width = p.w
        item.height = p.h
        item.radius = p.r
        item.tint = p.color
        item.letterText = p.letter
        item.x = p.x
        item.y = p.y
        item.visible = true
      }
      placed++
    }
    field.alive += placed
    if (field.alive > 0) frames.running = true
    return placed > 0
  }

  function clear() {
    for (var i = 0; i < field.poolSize; i++) {
      if (!field.pieces[i]) continue
      field.pieces[i] = null
      var item = repeater.itemAt(i)
      if (item) item.visible = false
    }
    field.alive = 0
    frames.running = false
  }

  function step(dt) {
    field.clock += dt
    var h = field.height
    var w = field.width
    var d = 1 - field.drag * dt

    for (var i = 0; i < field.poolSize; i++) {
      var p = field.pieces[i]
      if (!p) continue

      p.vy = (p.vy + field.gravity * dt) * d
      p.vx = p.vx * d
      var sway = p.swayAmp * Math.sin(field.clock * p.swayFreq + p.swayPhase)
      p.x += (p.vx + sway) * dt
      p.y += p.vy * dt
      p.zAngle += p.spin * dt
      p.flipAngle += p.flip * dt

      var item = repeater.itemAt(i)
      if (p.y > h + 90 || p.x < -250 || p.x > w + 250) {
        field.pieces[i] = null
        field.alive--
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

    if (field.alive <= 0) {
      frames.running = false
      field.clock = 0
      field.applyPoolSize()
      field.finished()
    }
  }

  FrameAnimation {
    id: frames
    running: false
    // A long stall between frames would teleport every piece; better to lose
    // a moment of motion than to have the burst jump across the screen.
    onTriggered: field.step(Math.min(frameTime, 0.05))
  }

  Repeater {
    id: repeater
    model: field.poolSize

    Rectangle {
      // Tumble about the horizontal axis. Without projection this reads as a
      // squash to nothing and back, which is exactly how paper flips.
      property real flipAngle: 0
      // A piece is either paper or a letter. Both take a colour from the
      // palette; paper fills itself with it, a letter draws its glyph in it
      // and leaves the rectangle empty, so the same pool and the same tumble
      // serve both without a second Repeater.
      property string letterText: ""
      property color tint: "white"
      visible: false
      antialiasing: true
      color: letterText === "" ? tint : "transparent"
      transform: Rotation {
        origin.x: width / 2
        origin.y: height / 2
        axis { x: 1; y: 0; z: 0 }
        angle: flipAngle
      }
      Text {
        anchors.centerIn: parent
        visible: parent.letterText !== ""
        text: parent.letterText
        textFormat: Text.PlainText
        color: parent.tint
        // The delegate has no size of its own until fire() gives it one, so
        // this binding is evaluated once against a height of zero. A pixel
        // size of zero is not a legal font size.
        font.pixelSize: Math.max(1, Math.round(parent.height))
        font.bold: true
        font.family: field.glyphFamily
      }
    }
  }
}
