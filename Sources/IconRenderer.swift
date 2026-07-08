import Cocoa

public class IconRenderer {
    
    /// Generates a template NSImage containing two stacked horizontal progress bars.
    /// - Parameters:
    ///   - hoursRemainingPercent: The remaining percentage for the hours quota (0.0 to 100.0). If nil, renders an empty track.
    ///   - weeklyRemainingPercent: The remaining percentage for the weekly quota (0.0 to 100.0). If nil, renders an empty track.
    /// - Returns: A native template NSImage ready to be placed in the status bar.
    public static func generateMenuBarIcon(hoursRemainingPercent: Double?, weeklyRemainingPercent: Double?) -> NSImage {
        let size = NSSize(width: 12, height: 16)
        let image = NSImage(size: size)
        image.isTemplate = true // Crucial for automatic light/dark mode styling in macOS status bar
        
        image.lockFocus()
        
        // --- 1. Draw Top Bar (Hours / Up Limit) ---
        let topY: CGFloat = 10
        let barHeight: CGFloat = 3
        let barWidth: CGFloat = 12
        
        // Track (Background)
        let topTrackRect = NSRect(x: 0, y: topY, width: barWidth, height: barHeight)
        NSColor.textColor.withAlphaComponent(0.3).set()
        let topTrackPath = NSBezierPath(roundedRect: topTrackRect, xRadius: 1, yRadius: 1)
        topTrackPath.fill()
        
        // Fill (Remaining Quota)
        if let hours = hoursRemainingPercent {
            let clampedHours = max(0.0, min(100.0, hours))
            let fillWidth = barWidth * CGFloat(clampedHours / 100.0)
            if fillWidth > 0 {
                let topFillRect = NSRect(x: 0, y: topY, width: fillWidth, height: barHeight)
                NSColor.textColor.set()
                let topFillPath = NSBezierPath(roundedRect: topFillRect, xRadius: 1, yRadius: 1)
                topFillPath.fill()
            }
        }
        
        // --- 2. Draw Bottom Bar (Weekly / Down Limit) ---
        let bottomY: CGFloat = 3
        
        // Track (Background)
        let bottomTrackRect = NSRect(x: 0, y: bottomY, width: barWidth, height: barHeight)
        NSColor.textColor.withAlphaComponent(0.3).set()
        let bottomTrackPath = NSBezierPath(roundedRect: bottomTrackRect, xRadius: 1, yRadius: 1)
        bottomTrackPath.fill()
        
        // Fill (Remaining Quota)
        if let weekly = weeklyRemainingPercent {
            let clampedWeekly = max(0.0, min(100.0, weekly))
            let fillWidth = barWidth * CGFloat(clampedWeekly / 100.0)
            if fillWidth > 0 {
                let bottomFillRect = NSRect(x: 0, y: bottomY, width: fillWidth, height: barHeight)
                NSColor.textColor.set()
                let bottomFillPath = NSBezierPath(roundedRect: bottomFillRect, xRadius: 1, yRadius: 1)
                bottomFillPath.fill()
            }
        }
        
        image.unlockFocus()
        return image
    }
}
