//
//  IngredientPrice.swift
//  SmartMealPlanner
//

import Foundation

/// Current supermarket price for a recipe ingredient, from the live grocery feed.
struct IngredientPrice: Codable, Hashable {
    /// Matches `Ingredient.name` in the recipes (e.g. "Chicken Breast").
    let ingredientName: String
    /// Typical price per 100 g: the median of each store's cheapest matching product.
    let pricePer100g: Double
    let cheapestStore: String
    let cheapestProduct: String
    let cheapestPrice: Double
    let cheapestSize: String
    let cheapestPricePer100g: Double
    let storeCount: Int
    let productCount: Int
}
