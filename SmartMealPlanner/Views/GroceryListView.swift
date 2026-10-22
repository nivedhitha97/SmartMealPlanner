//
//  GroceryListView.swift
//  SmartMealPlanner
//
//  The shopping list: the plan's groceries plus offers and items the user added, grouped by store with
//  totals, filterable, and editable.
//

import SwiftUI

struct GroceryListView: View {

    @EnvironmentObject private var shopping: ShoppingListStore
    @Environment(\.openTab) private var openTab

    @State private var filter: ShoppingListFilter = .all
    /// The item being edited, or a new blank one when adding.
    @State private var editing: EditorTarget?

    private var list: ShoppingList { shopping.list }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenHeader(eyebrow: "\(list.itemCount) items", title: "Grocery list") {
                        headerButtons
                    }
                    if list.items.isEmpty {
                        emptyState
                    } else {
                        totalsCard
                        filters
                        let groups = list.groups(for: filter)
                        ForEach(groups) { group in
                            storeSection(group)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { target in
                ShoppingItemEditor(target: target, knownStores: list.stores) { result in
                    switch result {
                    case .save(let item) where target.isNew:
                        shopping.change { $0.addManual(name: item.name, storeName: item.storeName,
                                                       price: item.price, quantity: item.quantity) }
                    case .save(let item):
                        shopping.change { $0.update(item) }
                    case .delete:
                        shopping.change { $0.remove([target.item.id]) }
                    }
                }
            }
            .onChange(of: list.filters) {
                if !list.filters.contains(filter) { filter = .all }  // its last item was removed
            }
        }
    }

    // MARK: - Header

    private var headerButtons: some View {
        HStack(spacing: 8) {
            if list.items.contains(where: \.isChecked) {
                Menu {
                    Button(role: .destructive) {
                        withAnimation { shopping.change { $0.removeChecked() } }
                    } label: {
                        Label("Remove ticked items", systemImage: "checkmark.circle.badge.xmark")
                    }
                } label: {
                    IconCircle(systemName: "ellipsis", tint: .textPrimary, background: .bgSurface, size: 40)
                }
                .accessibilityLabel("More")
            }
            if let text = list.shareText(for: filter) {
                ShareLink(item: text, subject: Text("Grocery list"), preview: SharePreview("Grocery list")) {
                    IconCircle(systemName: "square.and.arrow.up", tint: .textPrimary, background: .bgSurface, size: 40)
                }
                .accessibilityLabel("Share list")
                .accessibilityIdentifier("list.share")
            }
            // An empty list has its own "Add item" button, so the + only shows once there are items.
            if !list.items.isEmpty {
                Button {
                    editing = .new
                } label: {
                    IconCircle(systemName: "plus", tint: .white, background: .brandPrimary, size: 40)
                }
                .accessibilityLabel("Add item")
                .accessibilityIdentifier("list.addItem")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            IconCircle(systemName: "cart", tint: .brandPrimary, background: .brandPrimarySoft, size: 64)
            Text("Your list is empty")
                .font(.cardTitle)
                .foregroundStyle(Color.textPrimary)
            Text("Generate a weekly plan, tap + on an offer, or add your own items.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 10) {
                Button("Browse offers") { openTab(.offers) }
                    .buttonStyle(.secondary)
                Button("Add item") { editing = .new }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("list.addItem")  // the header's + takes over once there are items
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Totals and filters

    /// The total for the current filter, what's left to buy, and (for everything) a subtotal per store.
    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(filter == .all ? "Total" : "Total · \(filter.title)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(list.total(for: filter).euros)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("list.total")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Left to buy")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(list.remaining(for: filter).euros)
                        .font(.headline)
                        .foregroundStyle(Color.brandPrimaryDeep)
                        .contentTransition(.numericText())
                }
            }
            let groups = list.groups(for: filter)
            if groups.count > 1 {
                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        HStack {
                            // One column for every badge width (and none, for Any store), so the names line up.
                            ZStack(alignment: .leading) {
                                if group.store != ShoppingList.anyStore {
                                    StoreBadge(store: group.store, size: 18)
                                }
                            }
                            .frame(width: StoreBadge.columnWidth(size: 18), alignment: .leading)
                            Text(group.store)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(group.items.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(group.total.euros)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { RowDivider() }
            }
        }
        .card(padding: 18, radius: 22)
        .animation(.snappy, value: list)
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(list.filters, id: \.self) { option in
                    if case .store(let store) = option, store != ShoppingList.anyStore {
                        StoreChip(store: store, isSelected: filter == option) {
                            withAnimation(.snappy) { filter = option }
                        }
                    } else {
                        Chip(title: option.title, isSelected: filter == option) {
                            withAnimation(.snappy) { filter = option }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeFade()
        .padding(.horizontal, -24)
        .accessibilityIdentifier("list.filters")
    }

    // MARK: - Items

    private func storeSection(_ group: StoreGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if group.store != ShoppingList.anyStore {
                    StoreBadge(store: group.store, size: 18)
                }
                Text(group.store.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(group.total.euros)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    ShoppingItemRow(item: item) {
                        withAnimation(.snappy(duration: 0.2)) { shopping.change { $0.toggleChecked(item.id) } }
                    } onEdit: {
                        editing = .existing(item)
                    }
                    .contextMenu {
                        Button { editing = .existing(item) } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) {
                            withAnimation { shopping.change { $0.remove([item.id]) } }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.borderSubtle))
        }
    }
}

// MARK: - Row

private struct ShoppingItemRow: View {
    let item: ShoppingListItem
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var detail: String {
        var parts: [String] = []
        if let amount = item.amountText { parts.append(amount) }
        if let deal = item.dealText { parts.append(deal) }
        parts.append(item.source == .plan ? "From your plan" : "Added")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(item.isChecked ? Color.clear : Color.borderSubtle, lineWidth: 1.5)
                        .background(Circle().fill(item.isChecked ? Color.brandPrimary : Color.clear))
                    if item.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isChecked ? "Ticked off: \(item.name)" : "Tick off \(item.name)")
            .accessibilityIdentifier("list.check.\(item.name)")

            Button(action: onEdit) {
                HStack(spacing: 12) {
                    if let imageURL = item.imageURL {
                        AsyncImage(url: imageURL) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Color.bgMuted
                        }
                        .frame(width: 36, height: 36)
                        .padding(2)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .opacity(item.isChecked ? 0.5 : 1)
                        .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                            .strikethrough(item.isChecked)
                            .foregroundStyle(item.isChecked ? Color.textTertiary : Color.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.price == nil ? "–" : item.lineTotal.euros)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(item.isChecked ? Color.textTertiary : Color.textPrimary)
                        if item.quantity > 1 {
                            Text("\(item.quantity) × \((item.price ?? 0).euros)")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Edit")
            .accessibilityIdentifier("list.item.\(item.name)")
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Editor

enum EditorTarget: Identifiable {
    case new
    case existing(ShoppingListItem)

    var id: UUID {
        if case .existing(let item) = self { return item.id }
        return Self.newID
    }

    var isNew: Bool { if case .new = self { true } else { false } }

    var item: ShoppingListItem {
        if case .existing(let item) = self { return item }
        return ShoppingListItem(id: Self.newID, name: "", source: .manual)
    }

    private static let newID = UUID()
}

/// Add or edit an item: name, store, price per item and quantity. Existing items can also be deleted.
struct ShoppingItemEditor: View {
    enum Result {
        case save(ShoppingListItem)
        case delete
    }

    /// Supermarkets offered in the store picker besides those already on the list.
    static let commonStores = ["Albert Heijn", "Jumbo", "Lidl", "Plus", "Dirk", "Aldi", "DekaMarkt", "Hoogvliet",
                               "Poiesz", "Spar", "Vomar"]

    let target: EditorTarget
    let knownStores: [String]
    let onDone: (Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var item: ShoppingListItem
    @FocusState private var nameFocused: Bool

    init(target: EditorTarget, knownStores: [String], onDone: @escaping (Result) -> Void) {
        self.target = target
        self.knownStores = knownStores
        self.onDone = onDone
        _item = State(initialValue: target.item)
    }

    private var storeOptions: [String] {
        Array(Set(knownStores + Self.commonStores + [item.storeName].compactMap { $0 }))
            .filter { $0 != ShoppingList.anyStore }
            .sorted()
    }

    private var canSave: Bool {
        !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $item.name)
                        .focused($nameFocused)
                        .accessibilityIdentifier("editor.name")
                    Picker("Store", selection: $item.storeName) {
                        Text(ShoppingList.anyStore).tag(String?.none)
                        ForEach(storeOptions, id: \.self) { store in
                            Text(store).tag(Optional(store))
                        }
                    }
                }
                Section {
                    LabeledContent("Price per item") {
                        TextField("Optional", value: $item.price, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editor.price")
                    }
                    Stepper(value: $item.quantity, in: 1...99) {
                        LabeledContent("Quantity", value: "\(item.quantity)")
                    }
                    .accessibilityIdentifier("editor.quantity")
                    if item.price != nil {
                        LabeledContent("Line total", value: item.lineTotal.euros)
                    }
                } footer: {
                    if item.source == .plan {
                        Text("From your weekly plan. A new plan replaces these items; items you added stay.")
                    }
                }
                if !target.isNew {
                    Section {
                        Button("Delete item", role: .destructive) {
                            onDone(.delete)
                            dismiss()
                        }
                        .accessibilityIdentifier("editor.delete")
                    }
                }
            }
            .navigationTitle(target.isNew ? "Add item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(target.isNew ? "Add" : "Save") {
                        onDone(.save(item))
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("editor.save")
                }
            }
            .onAppear { if target.isNew { nameFocused = true } }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    GroceryListView()
        .environmentObject(ShoppingListStore())
}
