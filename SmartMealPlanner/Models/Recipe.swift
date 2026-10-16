//
//  Recipe.swift
//  SmartMealPlanner
//

import Foundation

struct Recipe: Identifiable, Codable {
    let id: UUID
    let name: String
    let cuisine: String
    let ingredients: [RecipeIngredient]
    /// How many people the ingredient amounts are for.
    var servings: Int
    /// Hands-on preparation time in minutes; nil when unknown.
    var prepMinutes: Int?
    /// Cooking time in minutes (0 for no-cook dishes); nil when unknown.
    var cookMinutes: Int?
    var instructions: [String]
    var imageURL: String?
    var youtubeURL: String?
    /// Human-readable citation, e.g. "Ottolenghi Simple — p. 112"
    var cookbookReference: String?
    /// Publisher, bookstore, or recipe permalink.
    var cookbookURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, cuisine, ingredients, servings, prepMinutes, cookMinutes, instructions
        case imageURL, youtubeURL, cookbookReference, cookbookURL
    }

    init(
        id: UUID,
        name: String,
        cuisine: String,
        ingredients: [RecipeIngredient],
        servings: Int = 1,
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        instructions: [String] = [],
        imageURL: String? = nil,
        youtubeURL: String? = nil,
        cookbookReference: String? = nil,
        cookbookURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.cuisine = cuisine
        self.ingredients = ingredients
        self.servings = max(1, servings)
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.instructions = instructions
        self.imageURL = imageURL
        self.youtubeURL = youtubeURL
        self.cookbookReference = cookbookReference
        self.cookbookURL = cookbookURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        cuisine = try c.decode(String.self, forKey: .cuisine)
        ingredients = try c.decode([RecipeIngredient].self, forKey: .ingredients)
        servings = max(1, try c.decodeIfPresent(Int.self, forKey: .servings) ?? 1)
        prepMinutes = try c.decodeIfPresent(Int.self, forKey: .prepMinutes)
        cookMinutes = try c.decodeIfPresent(Int.self, forKey: .cookMinutes)
        instructions = try c.decodeIfPresent([String].self, forKey: .instructions) ?? []
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        youtubeURL = try c.decodeIfPresent(String.self, forKey: .youtubeURL)
        cookbookReference = try c.decodeIfPresent(String.self, forKey: .cookbookReference)
        cookbookURL = try c.decodeIfPresent(String.self, forKey: .cookbookURL)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(cuisine, forKey: .cuisine)
        try c.encode(ingredients, forKey: .ingredients)
        try c.encode(servings, forKey: .servings)
        try c.encodeIfPresent(prepMinutes, forKey: .prepMinutes)
        try c.encodeIfPresent(cookMinutes, forKey: .cookMinutes)
        try c.encode(instructions, forKey: .instructions)
        try c.encodeIfPresent(imageURL, forKey: .imageURL)
        try c.encodeIfPresent(youtubeURL, forKey: .youtubeURL)
        try c.encodeIfPresent(cookbookReference, forKey: .cookbookReference)
        try c.encodeIfPresent(cookbookURL, forKey: .cookbookURL)
    }

    var containsMeat: Bool {
        let meatKeywords = ["chicken", "beef", "pork", "fish", "mutton", "lamb", "seafood", "turkey", "duck", "salmon"]
        return ingredients.contains { row in
            meatKeywords.contains { keyword in
                row.ingredient.name.lowercased().contains(keyword)
            }
        }
    }

    var containsAnimalProducts: Bool {
        containsMeat || containsDairyEggs
    }

    private var containsDairyEggs: Bool {
        let keywords = ["milk", "cheese", "butter", "egg", "yogurt", "cream", "honey", "ghee", "parmesan"]
        return ingredients.contains { row in
            keywords.contains { row.ingredient.name.lowercased().contains($0) }
        }
    }

    var imageURLParsed: URL? {
        guard let imageURL, let u = URL(string: imageURL), u.scheme == "https" || u.scheme == "http" else {
            return nil
        }
        return u
    }

    var youtubeURLParsed: URL? {
        guard let youtubeURL, let u = URL(string: youtubeURL) else { return nil }
        return u
    }

    var cookbookURLParsed: URL? {
        guard let cookbookURL, let u = URL(string: cookbookURL) else { return nil }
        return u
    }

    /// Whether there's a YouTube or cookbook link to show.
    var hasReferenceLinks: Bool {
        youtubeURLParsed != nil || cookbookURLParsed != nil
    }

    /// Approximate kcal for one serving (ingredient calories are per 100 g).
    var estimatedCalories: Double {
        ingredients.reduce(0) { $0 + $1.ingredient.calories * $1.quantity / 100 } / Double(servings)
    }

    /// Prep plus cooking time in minutes, or nil when neither is known.
    var totalMinutes: Int? {
        guard prepMinutes != nil || cookMinutes != nil else { return nil }
        return (prepMinutes ?? 0) + (cookMinutes ?? 0)
    }

    /// "1 h 15 min", "45 min".
    static func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Grams of an ingredient row needed to cook this recipe for `people`.
    func quantity(of row: RecipeIngredient, forPeople people: Int) -> Double {
        row.quantity * Double(max(1, people)) / Double(servings)
    }
}

struct RecipeIngredient: Codable, Identifiable {
    var id: UUID { ingredient.id }
    var ingredient: Ingredient
    /// Grams (nutrition values on `Ingredient` are per 100 g).
    var quantity: Double
}
