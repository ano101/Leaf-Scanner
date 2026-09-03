import Testing
@testable import Leaf

@Suite("Порядок страниц")
struct PageOrderingTests {
    @Test("перенос страницы вперёд оставляет нумерацию подряд")
    func moveForwardKeepsNumbersConsecutive() {
        let pages = PageFactory.pages(count: 4)
        let moved = PageOrdering.move(pages, from: 0, to: 2)

        #expect(moved.count == 4)
        #expect(moved.map(\.order) == [0, 1, 2, 3])
        #expect(moved[2].id == pages[0].id)
    }

    @Test("перенос страницы назад ставит её на указанное место")
    func moveBackwardPlacesPageAtTarget() {
        let pages = PageFactory.pages(count: 4)
        let moved = PageOrdering.move(pages, from: 3, to: 1)

        #expect(moved.count == 4)
        #expect(moved[1].id == pages[3].id)
        #expect(moved.map(\.order) == [0, 1, 2, 3])
    }

    @Test("перенос за пределы списка ничего не меняет и не роняет процесс")
    func moveOutOfRangeLeavesListUntouched() {
        let pages = PageFactory.pages(count: 3)

        #expect(PageOrdering.move(pages, from: 7, to: 0).map(\.id) == pages.map(\.id))
        #expect(PageOrdering.move(pages, from: 0, to: 9).map(\.id) == pages.map(\.id))
        #expect(PageOrdering.move([], from: 0, to: 0).isEmpty)
    }

    @Test("перенумерация чинит разрывы в порядке")
    func renumberingClosesGaps() {
        let pages = [PageFactory.page(order: 5), PageFactory.page(order: 9)]
        #expect(PageOrdering.renumbered(pages).map(\.order) == [0, 1])
    }

    @Test("сортировка расставляет страницы по возрастанию порядка")
    func sortingOrdersAscending() {
        let first = PageFactory.page(order: 2)
        let second = PageFactory.page(order: 0)
        let sorted = PageOrdering.sorted([first, second])

        #expect(sorted.count == 2)
        #expect(sorted.first?.id == second.id)
    }
}

@Suite("Поворот страницы")
struct RotationTests {
    @Test("четыре поворота направо возвращают исходное положение")
    func fourRightTurnsReturnToStart() {
        var rotation = Rotation.none
        for _ in 0..<4 { rotation = rotation.turnedRight() }
        #expect(rotation == .none)
    }

    @Test("поворот налево обратен повороту направо")
    func leftTurnUndoesRightTurn() {
        #expect(Rotation.none.turnedRight().turnedLeft() == .none)
        #expect(Rotation.upsideDown.turnedLeft().turnedRight() == .upsideDown)
    }

    @Test("боковые повороты меняют стороны местами, прямые — нет")
    func sideTurnsSwapDimensions() {
        #expect(Rotation.right.swapsDimensions)
        #expect(Rotation.left.swapsDimensions)
        #expect(Rotation.none.swapsDimensions == false)
        #expect(Rotation.upsideDown.swapsDimensions == false)
    }
}
