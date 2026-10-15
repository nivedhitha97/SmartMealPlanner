//
//  UserPreferences.swift
//  SmartMealPlanner
//

import Foundation

/// How breakfast should appear in the weekly plan (catalog recipes vs simple cereal).
enum BreakfastRecipePreference: String, Codable, CaseIterable, Identifiable {
    /// Use your meal routine to pick breakfast recipes from the catalog.
    case includeRecipes = "includeRecipes"
    /// No cooked breakfast recipe — you eat granola, muesli, or similar; grocery list stays focused on lunch/dinner.
    case granolaMuesliOnly = "granolaMuesliOnly"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .includeRecipes:
            return "Include breakfast recipes"
        case .granolaMuesliOnly:
            return "Granola / muesli only (no cooked recipe)"
        }
    }
}

struct UserPreferences: Codable, Equatable {
    var dietType: String
    var cuisines: [String]
    var dislikes: [String]
    var allergies: [String]
    var budgetWeekly: Double
    /// Area or city used to match regional supermarket offers (e.g. "Amsterdam, NL-North").
    /// Derived from `postcode` when one is set.
    var shoppingRegion: String
    /// Dutch postcode the shopping region is looked up from, e.g. "1012 AB". Empty if not set.
    var postcode: String
    /// When `granolaMuesliOnly`, the planner never assigns a catalog recipe to breakfast.
    var breakfastRecipePreference: BreakfastRecipePreference

    init(
        dietType: String,
        cuisines: [String],
        dislikes: [String],
        allergies: [String],
        budgetWeekly: Double,
        shoppingRegion: String = "",
        postcode: String = "",
        breakfastRecipePreference: BreakfastRecipePreference = .includeRecipes
    ) {
        self.dietType = dietType
        self.cuisines = cuisines
        self.dislikes = dislikes
        self.allergies = allergies
        self.budgetWeekly = budgetWeekly
        self.shoppingRegion = shoppingRegion
        self.postcode = postcode
        self.breakfastRecipePreference = breakfastRecipePreference
    }

    enum CodingKeys: String, CodingKey {
        case dietType, cuisines, dislikes, allergies, budgetWeekly, shoppingRegion, postcode, breakfastRecipePreference
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dietType = try c.decode(String.self, forKey: .dietType)
        cuisines = try c.decodeIfPresent([String].self, forKey: .cuisines) ?? []
        dislikes = try c.decodeIfPresent([String].self, forKey: .dislikes) ?? []
        allergies = try c.decodeIfPresent([String].self, forKey: .allergies) ?? []
        budgetWeekly = try c.decode(Double.self, forKey: .budgetWeekly)
        shoppingRegion = try c.decodeIfPresent(String.self, forKey: .shoppingRegion) ?? ""
        postcode = try c.decodeIfPresent(String.self, forKey: .postcode) ?? ""
        breakfastRecipePreference = try c.decodeIfPresent(BreakfastRecipePreference.self, forKey: .breakfastRecipePreference)
            ?? .includeRecipes
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dietType, forKey: .dietType)
        try c.encode(cuisines, forKey: .cuisines)
        try c.encode(dislikes, forKey: .dislikes)
        try c.encode(allergies, forKey: .allergies)
        try c.encode(budgetWeekly, forKey: .budgetWeekly)
        try c.encode(shoppingRegion, forKey: .shoppingRegion)
        try c.encode(postcode, forKey: .postcode)
        try c.encode(breakfastRecipePreference, forKey: .breakfastRecipePreference)
    }

    static let defaultsKey = "userPreferences"

    static func loadFromUserDefaults() -> UserPreferences? {
        load(from: .standard)
    }

    static func load(from defaults: UserDefaults) -> UserPreferences? {
        guard let data = defaults.data(forKey: defaultsKey),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return nil
        }
        return prefs
    }

    /// Returns false if encoding failed and nothing was written.
    @discardableResult
    func save(to defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.defaultsKey)
        return true
    }
}
