/// Сборка двустороннего документа из двух проходов камеры.
///
/// Человек снимает сначала все лицевые стороны, потом переворачивает пачку
/// целиком и снимает обороты. От переворота порядок оборотов оказывается
/// обратным: первым снят оборот последнего листа.
public enum DuplexInterleaver {
    public static func interleave(fronts: [Page], backs: [Page]) -> [Page] {
        var combined: [Page] = []
        combined.reserveCapacity(fronts.count + backs.count)

        for (index, front) in fronts.enumerated() {
            combined.append(front)

            let mirrored = fronts.count - 1 - index
            if backs.indices.contains(mirrored) {
                combined.append(backs[mirrored])
            }
        }

        // Оборотов оказалось больше, чем лицевых: человек снял лишнее либо
        // сбился со счёта. Терять кадры нельзя — они дописываются в конец
        // в том порядке, в каком лежали в пачке.
        if backs.count > fronts.count {
            combined.append(contentsOf: backs[fronts.count...].reversed())
        }

        return PageOrdering.renumbered(combined)
    }
}
