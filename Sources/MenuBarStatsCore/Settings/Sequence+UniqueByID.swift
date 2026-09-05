import Foundation

extension Sequence where Element: Identifiable, Element.ID: Hashable & Comparable {
    /// Keeps the first element for each id and returns them in ascending id order.
    ///
    /// Persisted settings use this to drop duplicate identities and keep status items in permanent identity order.
    func uniquedByID() -> [Element] {
        var seen: Set<Element.ID> = []
        return filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
    }
}
