import SwiftUI
import TasksCore

extension Band {
    /// The band's colour (SPEC §5), used by the app and the widget.
    var color: Color {
        switch self {
        case .notYet: .gray
        case .dueSoon: .blue
        case .due: Color(red: 0.90, green: 0.70, blue: 0.0) // amber
        case .late: .orange
        case .overdue: .red
        }
    }
}
