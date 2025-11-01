//
//  SelineWidgetLiveActivity.swift
//  SelineWidget
//
//  Created by Alishah Amin on 2025-11-01.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SelineWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct SelineWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SelineWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension SelineWidgetAttributes {
    fileprivate static var preview: SelineWidgetAttributes {
        SelineWidgetAttributes(name: "World")
    }
}

extension SelineWidgetAttributes.ContentState {
    fileprivate static var smiley: SelineWidgetAttributes.ContentState {
        SelineWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: SelineWidgetAttributes.ContentState {
         SelineWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: SelineWidgetAttributes.preview) {
   SelineWidgetLiveActivity()
} contentStates: {
    SelineWidgetAttributes.ContentState.smiley
    SelineWidgetAttributes.ContentState.starEyes
}
