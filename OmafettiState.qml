pragma Singleton
import QtQuick

// Lets the bar icon reach the overlay without the two knowing about each
// other's lifetimes.
QtObject {
  property var overlay: null
}
