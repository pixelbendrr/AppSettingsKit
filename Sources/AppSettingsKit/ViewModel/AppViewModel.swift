import Foundation
import RoutingHelpers
import SwiftUI
import Parsing
import IdentifiedCollections
import CasePaths

public enum Tab {
    case one, inventory, three
}


public struct Item: Equatable, Identifiable {
    public let id = UUID()
    public var name: String
    public var color: Color?
    public var status: Status

    public init(
        name: String,
        color: Item.Color? = nil,
        status: Item.Status)
    {
        self.name = name
        self.color = color
        self.status = status
    }

    public enum Status: Equatable {
        case inStock(quantity: Int)
        case outOfStock(isOnBackOrder: Bool)

        public var isInStock: Bool {
            guard case .inStock = self else { return false }
            return true
        }
    }

    public struct Color: Equatable, Hashable {
        public var name: String
        public var red: CGFloat = 0
        public var green: CGFloat = 0
        public var blue: CGFloat = 0

        public init(
            name: String,
            red: CGFloat = 0,
            green: CGFloat = 0,
            blue: CGFloat = 0)
        {
            self.name = name
            self.red = red
            self.green = green
            self.blue = blue
        }

        public static var defaults: [Self] = [
            .red,
            .green,
            .blue,
            .black,
            .yellow,
            .white,
        ]

        public static let red = Self(name: "Red", red: 1)
        public static let green = Self(name: "Green", green: 1)
        public static let blue = Self(name: "Blue", blue: 1)
        public static let black = Self(name: "Black")
        public static let yellow = Self(name: "Yellow", red: 1, green: 1)
        public static let white = Self(name: "White", red: 1, green: 1, blue: 1)

        public var swiftUIColor: SwiftUI.Color {
            .init(red: self.red, green: self.green, blue: self.blue)
        }
    }
}

extension Item {
     public func duplicate() -> Self {
        .init(name: self.name, color: self.color, status: self.status)
    }
}

public enum InventoryRoute {
    case add(Item, ItemRoute? = nil)
}

public enum ItemRoute {
    case colorPicker
}

let item = QueryItem("name").orElse(Always(""))
    .take(QueryItem("quantity", Int.parser()).orElse(Always(1)))
    .map { name, quantity in
        Item(name: String(name), status: .inStock(quantity: quantity))
    }

public enum ItemRowRoute {
    case delete
    case duplicate
    case edit
}

public let itemRowDeepLinker = PathComponent("edit")
    .skip(PathEnd())
    .map { _ in ItemRowRoute.edit }
    .orElse(
        PathComponent("delete")
            .skip(PathEnd())
            .map { _ in .delete }
    )
    .orElse(
        PathComponent("duplicate")
            .skip(PathEnd())
            .map { _ in .duplicate }
    )

public let inventoryDeepLinker = PathEnd()
    .map { InventoryRoute?.none }
    .orElse(
        PathComponent("add")
            .skip(PathEnd())
            .take(item)
            .map { .add($0) }
    )
    .orElse(
        PathComponent("add")
            .skip(PathComponent("colorPicker"))
            .skip(PathEnd())
            .take(item)
            .map { .add($0, .colorPicker) }
    )

enum AppRoute {
    case one
    case inventory(InventoryRoute?)
    case three
}

let deepLinker = PathComponent("one")
    .skip(PathEnd())
    .map { AppRoute.one }
    .orElse(
        PathComponent("inventory")
            .take(inventoryDeepLinker)
            .map(AppRoute.inventory)
    )
    .orElse(
        PathComponent("three")
            .skip(PathEnd())
            .map { .three }
    )

public class ItemRowViewModel: Hashable, Identifiable, ObservableObject {
    @Published public var item: Item
    @Published public var route: Route?
    @Published var isSaving = false

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.item.id)
    }

    public static func == (lhs: ItemRowViewModel, rhs: ItemRowViewModel) -> Bool {
        lhs.item.id == rhs.item.id
    }

    public enum Route: Equatable {
        case deleteAlert
        case duplicate(ItemViewModel)
        case edit(ItemViewModel)

        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.deleteAlert, .deleteAlert):
                return true
            case let (.duplicate(lhs), .duplicate(rhs)):
                return lhs === rhs
            case let (.edit(lhs), .edit(rhs)):
                return lhs === rhs
            case (.deleteAlert, _), (.duplicate, _), (.edit, _):
                return false
            }
        }
    }

    public var onDelete: () -> Void = {}
    public var onDuplicate: (Item) -> Void = { _ in }

    public var id: Item.ID { self.item.id }

    public init(
        item: Item
    ) {
        self.item = item
    }

    public func deleteButtonTapped() {
        self.route = .deleteAlert
    }

    func deleteConfirmationButtonTapped() {
        self.onDelete()
        self.route = nil
    }

    public func setEditNavigation(isActive: Bool) {
        self.route = isActive ? .edit(.init(item: self.item)) : nil
    }

     func edit(item: Item) {
        self.isSaving = true

        Task { @MainActor in
            try await Task.sleep(nanoseconds: NSEC_PER_SEC)

            self.isSaving = false
            self.item = item
            self.route = nil
        }
    }

    public func cancelButtonTapped() {
        self.route = nil
    }

    public func duplicateButtonTapped() {
        self.route = .duplicate(.init(item: self.item.duplicate()))
    }

     func duplicate(item: Item) {
        self.onDuplicate(item)
        self.route = nil
    }
}

public class ItemViewModel: Identifiable, ObservableObject {
    @Published public var item: Item
    @Published public var nameIsDuplicate = false
    @Published public var newColors: [Item.Color] = []
    @Published public var route: Route?

    public var id: Item.ID { self.item.id }

    public enum Route {
        case colorPicker
    }

    public init(item: Item, route: Route? = nil) {
        self.item = item
        self.route = route

        Task { @MainActor in
            for await item in self.$item.values {
                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 300)
                self.nameIsDuplicate = item.name == "Keyboard"
            }
        }
    }

    @MainActor
    public func loadColors() async {
        try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 500)
        self.newColors = [
            .init(name: "Pink", red: 1, green: 0.7, blue: 0.7),
        ]
    }

    public func setColorPickerNavigation(isActive: Bool) {
        self.route = isActive ? .colorPicker : nil
    }
}

public class InventoryViewModel: ObservableObject {
    @Published public var inventory: IdentifiedArrayOf<ItemRowViewModel>
    @Published public var route: Route?
 
    public enum Route: Equatable {
        case add(ItemViewModel)
        case row(id: ItemRowViewModel.ID, route: ItemRowViewModel.Route)

        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.add(lhs), .add(rhs)):
                return lhs === rhs
            case let (.row(lhsId, lhsRoute), .row(rhsId, rhsRoute)):
                return lhsId == rhsId && lhsRoute == rhsRoute
            case (.add, .row), (.row, .add):
                return false
            }
        }
    }

    public init(
        inventory: IdentifiedArrayOf<ItemRowViewModel> = [],
        route: Route? = nil
    ) {
        self.inventory = []
        self.route = route

        for itemRowViewModel in inventory {
            self.bind(itemRowViewModel: itemRowViewModel)
        }
    }

    private func bind(itemRowViewModel: ItemRowViewModel) {
        print("bind id", itemRowViewModel.id)

        itemRowViewModel.onDelete = { [weak self, item = itemRowViewModel.item] in
            withAnimation {
                self?.delete(item: item)
            }
        }
        itemRowViewModel.onDuplicate = { [weak self] item in
            withAnimation {
                self?.add(item: item)
            }
        }
        itemRowViewModel.$route
            .map { [id = itemRowViewModel.id] route in
                route.map { Route.row(id: id, route: $0) }
            }
            .removeDuplicates()
            .dropFirst()
            .assign(to: &self.$route)
        self.$route
            .map { [id = itemRowViewModel.id] route in
                guard
                    case let .row(id: routeRowId, route: route) = route,
                    routeRowId == id
                else { return nil }
                return route
            }
            .removeDuplicates()
            .assign(to: &itemRowViewModel.$route)
        self.inventory.append(itemRowViewModel)
    }

    public func delete(item: Item) {
        withAnimation {
            _ = self.inventory.remove(id: item.id)
        }
    }

    public func add(item: Item) {
        withAnimation {
            self.bind(itemRowViewModel: .init(item: item))
            self.route = nil
        }
    }

    public func addButtonTapped() {
        self.route = .add(
            .init(
                item: .init(name: "", color: nil, status: .inStock(quantity: 1))
            )
        )

        Task { @MainActor in
            try await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
            try (/Route.add).modify(&self.route) {
                $0.item.name = "Bluetooth Keyboard"
            }
        }
    }

    public func cancelButtonTapped() {
        self.route = nil
    }
}

public class AppViewModel: ObservableObject {
    @Published var inventoryViewModel: InventoryViewModel
    @Published var selectedTab: Tab

    public init(
        inventoryViewModel: InventoryViewModel = .init(),
        selectedTab: Tab = .one
    ) {
        self.inventoryViewModel = inventoryViewModel
        self.selectedTab = selectedTab
    }

    public func open(url: URL) {
        var request = DeepLinkRequest(url: url)
        if let route = deepLinker.parse(&request) {
            switch route {
            case .one:
                self.selectedTab = .one

            case let .inventory(inventoryRoute):
                self.selectedTab = .inventory
//                self.inventoryViewModel.navigate(to: inventoryRoute)

            case .three:
                self.selectedTab = .three
            }
        }
    }
}

