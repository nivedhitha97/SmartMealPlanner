//
//  AddOfferView.swift
//  SmartMealPlanner
//
//  Adding a deal from a supermarket's folder (mainly Albert Heijn's Bonus, which apps can't read).
//

import SwiftUI

struct AddOfferView: View {
    let onAdd: (SupermarketOffer) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = OfferDraft()
    @FocusState private var nameFocused: Bool

    /// Ingredients of the saved recipes, so a deal can be linked to one and used by the planner.
    private let ingredients: [String] = Array(Set(RecipeDiscovery.shared.savedRecipes()
        .flatMap { $0.ingredients.map(\.ingredient.name) })).sorted()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Product, e.g. AH Kipfilet", text: $draft.productName)
                        .focused($nameFocused)
                        .accessibilityIdentifier("addDeal.name")
                    Picker("Store", selection: $draft.storeName) {
                        ForEach(ShoppingItemEditor.commonStores.sorted(), id: \.self) { Text($0) }
                    }
                    Picker("Category", selection: $draft.category) {
                        ForEach(OfferDraft.categories, id: \.self) { Text($0) }
                    }
                }
                Section {
                    LabeledContent("Deal price") {
                        TextField("€", value: $draft.offerPrice, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("addDeal.price")
                    }
                    LabeledContent("Normal price") {
                        TextField("Optional", value: $draft.regularPrice, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("addDeal.regularPrice")
                    }
                    LabeledContent("Per") {
                        TextField("item", text: $draft.unitLabel)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Deal, e.g. 1+1 gratis (optional)", text: $draft.dealText)
                    DatePicker("Valid until", selection: $draft.validUntil, in: Date.now..., displayedComponents: .date)
                } footer: {
                    Text("Albert Heijn's Bonus runs Monday to Sunday, so it ends this Sunday unless you change it.")
                }
                Section {
                    Picker("Recipe ingredient", selection: $draft.ingredientName) {
                        Text("None").tag(String?.none)
                        ForEach(ingredients, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                } footer: {
                    Text("Link it to an ingredient and the planner uses this price. Saved only on this phone.")
                }
            }
            .navigationTitle("Add a deal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let offer = draft.offer() { onAdd(offer) }
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                    .accessibilityIdentifier("addDeal.save")
                }
            }
            .onAppear { nameFocused = true }
        }
    }
}

#Preview {
    AddOfferView { _ in }
}
