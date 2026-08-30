import SwiftUI

/// Compatibility wrapper that maps the stable icon vocabulary onto
/// platform-native SF Symbols.
struct NileMaterialIcon: View {
    enum Kind {
        case add
        case close
        case search
        case edit
        case stats
        case settings
        case keyboardArrowDown
        case pin
        case pinOutlined
    }

    let kind: Kind

    var body: some View {
        Image(systemName: symbolName)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
        .aspectRatio(1, contentMode: .fit)
    }

    private var symbolName: String {
        switch kind {
        case .add:
            "plus"
        case .close:
            "xmark"
        case .search:
            "magnifyingglass"
        case .edit:
            "pencil"
        case .stats:
            "chart.bar.xaxis"
        case .settings:
            "gearshape"
        case .keyboardArrowDown:
            "chevron.down"
        case .pin:
            "pin.fill"
        case .pinOutlined:
            "pin"
        }
    }
}
