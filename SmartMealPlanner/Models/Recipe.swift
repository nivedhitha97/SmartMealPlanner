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
    var instructions: [String]
    var imageURL: String?
    var youtubeURL: String?
    /// Human-readable citation, e.g. "Ottolenghi Simple — p. 112"
    var cookbookReference: String?
    /// Publisher, bookstore, or recipe permalink.
    var cookbookURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, cuisine, ingredients, instructions
        case imageURL, youtubeURL, cookbookReference, cookbookURL
    }

    init(
        id: UUID,
        name: String,
        cuisine: String,
        ingredients: [RecipeIngredient],
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
        ingredients.reduce(0) { $0 + $1.ingredient.calories * $1.quantity / 100 }
    }
}

struct RecipeIngredient: Codable, Identifiable {
    var id: UUID { ingredient.id }
    var ingredient: Ingredient
    /// Grams (nutrition values on `Ingredient` are per 100 g).
    var quantity: Double
}
