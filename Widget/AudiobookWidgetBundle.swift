import WidgetKit
import SwiftUI

@main
struct AudiobookWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        PlayPauseControl()
    }
}
