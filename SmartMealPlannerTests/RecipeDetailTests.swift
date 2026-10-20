//
//  RecipeDetailTests.swift
//  SmartMealPlannerTests
//
//  What the Recipe detail screen shows: calorie estimate, links and diet flags.
//

import Foundation
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Recipe detail screen")
struct RecipeDetailTests {

    @Test func caloriesAreEstimatedPer100GramsOfEachIngredient() {
        let recipe = Fixtures.recipe("Omelette", ingredients: [
            (Fixtures.ingredient("Eggs", calories: 150), 120),
            (Fixtures.ingredient("Butter", calories: 700), 10),
        ])

        #expect(abs(recipe.estimatedCalories - (1.2 * 150 + 0.1 * 700)) < 0.0001)
    }

    @Test func recipeWithoutIngredientsHasNoCalorieEstimate() {
        #expect(Fixtures.recipe("Empty").estimatedCalories == 0)
    }

    @Test func referenceButtonsShowWhenAnyLinkIsPresent() {
        #expect(Fixtures.recipe("A", youtubeURL: "https://www.youtube.com/watch?v=abc").hasReferenceLinks)
        #expect(Fixtures.recipe("B", cookbookURL: "https://example.com/book").hasReferenceLinks)
        #expect(!Fixtures.recipe("C").hasReferenceLinks)
    }

    @Test func linksAreParsedIntoURLs() {
        let recipe = Fixtures.recipe("A", youtubeURL: "https://www.youtube.com/watch?v=abc", cookbookURL: "https://example.com/book")

        #expect(recipe.youtubeURLParsed?.host() == "www.youtube.com")
        #expect(recipe.cookbookURLParsed?.absoluteString == "https://example.com/book")
    }

    @Test(arguments: ["https://images.example.com/a.jpg", "http://images.example.com/a.jpg"])
    func webImageURLsAreUsedForThePhoto(url: String) {
        #expect(Fixtures.recipe("A", imageURL: url).imageURLParsed?.absoluteString == url)
    }

    @Test(arguments: [nil, "ftp://example.com/a.jpg", "photo.jpg"] as [String?])
    func nonWebImageURLsFallBackToThePlaceholder(url: String?) {
        #expect(Fixtures.recipe("A", imageURL: url).imageURLParsed == nil)
    }

    @Test(arguments: ["Chicken Breast", "Salmon Fillet", "minced BEEF"])
    func meatIngredientsMarkTheRecipeAsContainingMeat(name: String) {
        let recipe = Fixtures.recipe("A", ingredients: [(Fixtures.ingredient(name), 100)])

        #expect(recipe.containsMeat)
        #expect(recipe.containsAnimalProducts)
    }

    @Test(arguments: ["Feta Cheese", "Eggs", "Greek Yogurt", "Butter"])
    func dairyAndEggsAreAnimalProductsButNotMeat(name: String) {
        let recipe = Fixtures.recipe("A", ingredients: [(Fixtures.ingredient(name), 100)])

        #expect(!recipe.containsMeat)
        #expect(recipe.containsAnimalProducts)
    }

    @Test func plantIngredientsAreNeitherMeatNorAnimalProducts() {
        let recipe = Fixtures.recipe("Dal", ingredients: [
            (Fixtures.ingredient("Red Lentils"), 100),
            (Fixtures.ingredient("Tomato"), 100),
        ])

        #expect(!recipe.containsMeat)
        #expect(!recipe.containsAnimalProducts)
    }

    // MARK: - Times

    @Test func totalTimeIsPrepPlusCookingAndUnknownWhenNeitherIsSet() {
        let quick = Recipe(id: UUID(), name: "Salad", cuisine: "Greek", ingredients: [], prepMinutes: 15, cookMinutes: 0)
        let stew = Recipe(id: UUID(), name: "Stew", cuisine: "Dutch", ingredients: [], prepMinutes: 20, cookMinutes: 95)
        let unknown = Recipe(id: UUID(), name: "Mystery", cuisine: "Dutch", ingredients: [])

        #expect(quick.totalMinutes == 15)
        #expect(stew.totalMinutes == 115)
        #expect(unknown.totalMinutes == nil)
    }

    @Test(arguments: [(5, "5 min"), (60, "1 h"), (115, "1 h 55 min")])
    func durationsReadNaturally(minutes: Int, text: String) {
        #expect(Recipe.durationText(minutes) == text)
    }
}
