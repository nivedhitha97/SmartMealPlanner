//
//  RecipeDetailView.swift
//  SmartMealPlanner
//

import SwiftUI

struct RecipeDetailView: View {

    let recipe: Recipe
    /// Ingredient amounts are shown for this many people (from Preferences).
    var people: Int = UserPreferences.savedPeople()
    var slot: MealSlot? = nil

    private let heroHeight: CGFloat = 340

    var body: some View {
        ScrollView {
            VStack(spacing: -28) {
                RecipeImage(url: recipe.imageURLParsed, placeholderKey: recipe.name, iconSize: 56)
                    .frame(height: heroHeight)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 24) {
                    titleBlock
                    referenceLinks
                    ingredientsBlock
                    instructionsBlock
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                        .fill(Color.bgCanvas)
                )
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Sections

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text([recipe.cuisine, slot?.rawValue].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.brandPrimaryDeep)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(Color.brandPrimarySoft, in: Capsule())

            Text(recipe.name)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Color.textPrimary)

            if recipe.totalMinutes != nil {
                timesRow
            }

            HStack(spacing: 16) {
                metaItem("person.2", people == 1 ? "1 person" : "\(people) people")
                metaItem("list.bullet", "\(recipe.ingredients.count) ingredients")
                if recipe.estimatedCalories > 0 {
                    metaItem("flame", "\(Int(recipe.estimatedCalories)) kcal")
                }
            }
        }
    }

    /// Total, prep and cooking time.
    private var timesRow: some View {
        HStack(spacing: 0) {
            timeItem("Total", recipe.totalMinutes, icon: "clock.fill", emphasised: true)
            Divider().frame(height: 32)
            timeItem("Prep", recipe.prepMinutes, icon: "knife")
            Divider().frame(height: 32)
            timeItem("Cook", recipe.cookMinutes, icon: "flame")
        }
        .padding(.vertical, 10)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.borderSubtle))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recipe.times")
    }

    private func timeItem(_ title: String, _ minutes: Int?, icon: String, emphasised: Bool = false) -> some View {
        VStack(spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textSecondary)
            Text(minutes.map { $0 == 0 && title == "Cook" ? "No cooking" : Recipe.durationText($0) } ?? "–")
                .font(.subheadline.weight(emphasised ? .bold : .semibold))
                .foregroundStyle(emphasised ? Color.brandPrimaryDeep : Color.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private func metaItem(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.textSecondary)
            .labelStyle(MetaLabelStyle())
    }

    @ViewBuilder
    private var referenceLinks: some View {
        let hasLinks = recipe.hasReferenceLinks
        VStack(alignment: .leading, spacing: 12) {
            if hasLinks {
                HStack(spacing: 12) {
                    if let yt = recipe.youtubeURLParsed {
                        referenceButton(url: yt, icon: "play.fill", title: "Watch", subtitle: "YouTube", tint: .accentCoral, background: .accentCoralSoft)
                    }
                    if let book = recipe.cookbookURLParsed {
                        referenceButton(url: book, icon: "book", title: "Cookbook", subtitle: "Source link", tint: .brandPrimaryDeep, background: .brandPrimarySoft)
                    }
                }
            }
            if let ref = recipe.cookbookReference, !ref.isEmpty {
                Label(ref, systemImage: "book.closed")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 4)
            }
            if !hasLinks && (recipe.cookbookReference?.isEmpty ?? true) {
                Text("No external links provided for this recipe.")
                    .font(.footnote)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func referenceButton(url: URL, icon: String, title: String, subtitle: String, tint: Color, background: Color) -> some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                IconTile(systemName: icon, tint: tint, background: Color.bgSurface, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var ingredientsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ingredients",
                          subtitle: people == recipe.servings ? nil
                              : "For \(people == 1 ? "1 person" : "\(people) people") (recipe serves \(recipe.servings))")

            if recipe.ingredients.isEmpty {
                Text("No ingredients listed.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.brandPrimary)
                                .frame(width: 8, height: 8)
                            Text(row.ingredient.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(Int(recipe.quantity(of: row, forPeople: people).rounded())) g")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.vertical, 13)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.borderSubtle))
            }
        }
    }

    private var instructionsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Method")
            if recipe.instructions.isEmpty {
                Text("Add step-by-step instructions to this recipe in `recipes.json`.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.footnote.bold())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.brandPrimary, in: Circle())
                        Text(step)
                            .font(.callout)
                            .lineSpacing(4)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                    }
                    .card(padding: 16, radius: 18)
                }
            }
        }
    }
}

private struct MetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: Recipe(
            id: UUID(),
            name: "Herb Omelette",
            cuisine: "French",
            ingredients: [],
            instructions: ["Whisk the eggs with a pinch of salt.", "Melt butter in a pan.", "Cook, fold and serve."],
            imageURL: nil,
            youtubeURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            cookbookReference: "Demo Cookbook p. 1",
            cookbookURL: "https://www.apple.com"
        ), slot: .breakfast)
    }
}
