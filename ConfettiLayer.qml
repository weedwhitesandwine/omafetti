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
  // Spell the word out as part of the burst. The letters are thrown like
  // everything else once they are released; what makes them read as a word
  // is that they hold still, upright and in a row, for a moment first.
  property bool spell: false
  // Every piece of paper is a letter instead. The word is only the alphabet
  // here — the glyphs are picked at random, not spelled — so the screen fills
  // with tumbling O M A R C H Y rather than reading as anything.
  property bool letterStorm: false
  property string word: "OMARCHY"
  // Sized against the screen rather than fixed: the word is the thing being
  // read, so it has to be obviously larger than the paper around it, and a
  // number that suits a laptop is lost on a 4K panel.
  property int letterSize: Math.max(56, Math.round(layer.height * 0.11))
  // Remembered only long enough to keep two neighbours from matching.
  property string lastLetterColor: ""
  // How the word assembles: each letter appears this long after the one to
  // its left, the finished word is held this long, and then the letters are
  // let go in the same order, so it peels apart rather than dropping as a
  // block.
  readonly property real letterAppear: 0.07
  readonly property real letterHold: 0.85
  readonly property real letterPeel: 0.05
  property int pieceCount: 600
  // Room for a second burst thrown before the first has landed.
  readonly property int wantedPoolSize: Math.min(1600, Math.round(layer.pieceCount * 1.4))

  // The pool only ever changes size while it is empty, so poolSize is set
  // rather than bound. Shrinking it with pieces still in the air would strand
  // every slot above the new size: step() would stop visiting them, so they
  // would never be freed and never decrement `alive`, finished() would never
  // be emitted, and the frame callback would keep running for the life of the
  // shell process. Density is changed from the settings card, which is exactly
  // when a burst can still be falling.
  property int poolSize: 0
  Component.onCompleted: layer.poolSize = layer.wantedPoolSize
  onWantedPoolSizeChanged: layer.applyPoolSize()

  function applyPoolSize() {
    if (layer.poolSize === layer.wantedPoolSize || layer.alive > 0) return
    layer.clear()
    layer.poolSize = layer.wantedPoolSize
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

    if (layer.letterStorm) {
      // Sized over a wide range so the fall has depth to it: a field of
      // identical glyphs reads as a texture rather than as falling paper.
      var lh = layer.rnd(16, 46)
      p.letter = layer.word.charAt(Math.floor(Math.random() * layer.word.length))
      p.w = lh * 0.72; p.h = lh; p.r = 0
      // Storm letters are thrown immediately: they are paper, not a word, so
      // there is nothing to hold for. Leaving these undefined makes fire()
      // test `undefined <= 0` and start every piece invisible.
      p.showAt = 0
      p.releaseAt = 0
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

    var shape = Math.random()
    if (shape < 0.6) {            // paper rectangle
      p.w = layer.rnd(7, 13); p.h = layer.rnd(9, 16); p.r = 0
    } else if (shape < 0.85) {    // streamer
      p.w = layer.rnd(3, 5); p.h = layer.rnd(18, 30); p.r = 0
    } else {                      // dot
      p.w = layer.rnd(6, 11); p.h = p.w; p.r = p.w / 2
    }

    p.color = layer.pickOne(layer.palette)
    // Ordinary paper is on screen from the first frame and never held.
    p.letter = ""
    p.showAt = 0
    p.releaseAt = 0
    p.spin = layer.rnd(-200, 200)
    p.flip = layer.rnd(160, 760) * (Math.random() < 0.5 ? -1 : 1)
    p.zAngle = layer.rnd(0, 360)
    p.flipAngle = layer.rnd(0, 360)
    p.swayAmp = layer.rnd(20, 95)
    p.swayFreq = layer.rnd(1.5, 4.2)
    p.swayPhase = layer.rnd(0, 6.28)
    return p
  }

  // One letter of the word, parked where it will be read and told when to
  // appear and when to let go. Until it is released it ignores gravity, the
  // sway and both rotations, so the row stays legible instead of drifting
  // apart while it is still being spelled.
  function makeLetter(i, total) {
    var p = layer.makePiece()
    var glyph = layer.word.charAt(i)
    var span = layer.letterSize * 0.82
    var rowW = span * (total - 1)

    p.letter = glyph
    p.w = layer.letterSize * 0.72
    p.h = layer.letterSize
    p.r = 0
    p.x = (layer.width - rowW) / 2 + i * span - p.w / 2
    p.y = layer.height * 0.36
    p.showAt = i * layer.letterAppear
    p.releaseAt = (total - 1) * layer.letterAppear + layer.letterHold
                  + i * layer.letterPeel

    // Adjacent letters take different colours, so a short palette cannot
    // produce OO or MM sitting next to each other in the same shade.
    if (layer.palette.length > 1 && i > 0) {
      var prev = layer.lastLetterColor
      var guard = 0
      while (p.color === prev && guard++ < 8) p.color = layer.pickOne(layer.palette)
    }
    layer.lastLetterColor = p.color

    // Held still, so nothing moves until the word has been read. The push it
    // is given on release throws it away from the middle, which opens the row
    // outward rather than dropping it straight down.
    p.vx = ((p.x + p.w / 2) - layer.width / 2) * 1.1 + layer.rnd(-60, 60)
    p.vy = -layer.height * layer.rnd(0.30, 0.55)
    p.spin = layer.rnd(-150, 150)
    p.flip = layer.rnd(150, 520) * (Math.random() < 0.5 ? -1 : 1)
    p.zAngle = 0
    p.flipAngle = 0
    return p
  }

  // Returns whether anything was actually thrown: a layer whose panel has not
  // been given a size yet must not be counted as flying, or the burst is
  // recorded as in progress and never lands.
  function fire() {
    if (layer.width <= 0 || layer.height <= 0) return false
    var placed = 0
    // The word is claimed first so it always gets slots, however full the
    // pool is — a burst that spelled five letters of seven would be worse
    // than one that spelled none.
    var wordLeft = layer.spell ? layer.word.length : 0
    var wordIdx = 0
    for (var i = 0; i < layer.poolSize && placed < layer.pieceCount; i++) {
      if (layer.pieces[i]) continue
      var p
      if (wordLeft > 0) {
        p = layer.makeLetter(wordIdx, layer.word.length)
        wordIdx++; wordLeft--
      } else {
        p = layer.makePiece()
      }
      layer.pieces[i] = p
      var item = repeater.itemAt(i)
      if (item) {
        item.width = p.w
        item.height = p.h
        item.radius = p.r
        item.tint = p.color
        item.letterText = p.letter
        item.x = p.x
        item.y = p.y
        // A letter that has not reached its cue stays hidden rather than
        // appearing and waiting, so the word writes itself on.
        item.visible = (p.showAt <= 0)
      }
      placed++
    }
    layer.alive += placed
    if (layer.alive > 0) frames.running = true
    return placed > 0
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

      // A letter waiting for its cue, or holding the row while the word is
      // read, is skipped entirely: no gravity, no drag, no sway, no rotation.
      // It is drawn where it was placed and nowhere else.
      if (p.releaseAt > 0 && layer.clock < p.releaseAt) {
        var waiting = repeater.itemAt(i)
        if (waiting && layer.clock >= p.showAt && !waiting.visible)
          waiting.visible = true
        continue
      }

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
      layer.applyPoolSize()
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
        font.pixelSize: Math.round(parent.height)
        font.bold: true
        font.family: "JetBrainsMono Nerd Font"
      }
    }
  }
}
