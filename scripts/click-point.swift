import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else {
    fputs("usage: click-point.swift <x> <y>\n", stderr)
    exit(64)
}

let point = CGPoint(x: x, y: y)
guard let source = CGEventSource(stateID: .hidSystemState),
      let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
      let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
      let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
    fputs("click-point failed: cannot create mouse event\n", stderr)
    exit(1)
}

move.post(tap: .cghidEventTap)
usleep(50_000)
down.post(tap: .cghidEventTap)
usleep(70_000)
up.post(tap: .cghidEventTap)
