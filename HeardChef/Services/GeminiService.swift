import Foundation
import SwiftData

// MARK: - Delegate Protocol

@MainActor
protocol GeminiServiceDelegate: AnyObject {
    func geminiServiceDidConnect(_ service: GeminiService)
    func geminiServiceDidDisconnect(_ service: GeminiService)
    func geminiService(_ service: GeminiService, didReceiveError error: Error)
    func geminiService(_ service: GeminiService, didReceiveTranscript transcript: String, isFinal: Bool)
    func geminiService(_ service: GeminiService, didReceiveResponse text: String)
    func geminiService(_ service: GeminiService, didReceiveAudio data: Data)
    func geminiService(_ service: GeminiService, didExecuteFunctionCall name: String, result: String)
}

// MARK: - Gemini Service

@MainActor
class GeminiService: NSObject {

    // MARK: - Properties

    weak var delegate: GeminiServiceDelegate?

    private let modelContext: ModelContext
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false

    // API Configuration
    private let apiKey: String
    private let model = "gemini-2.0-flash-exp"
    private let baseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Get API key from environment or Info.plist
        self.apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
            ?? ""

        super.init()
    }

    // MARK: - Connection

    func connect() {
        guard !apiKey.isEmpty else {
            delegate?.geminiService(self, didReceiveError: GeminiError.missingAPIKey)
            return
        }

        let urlString = "\(baseURL)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            delegate?.geminiService(self, didReceiveError: GeminiError.invalidURL)
            return
        }

        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        // Send setup message
        sendSetupMessage()

        // Start receiving messages
        receiveMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
    }

    // MARK: - Setup Message

    private func sendSetupMessage() {
        let setupMessage: [String: Any] = [
            "setup": [
                "model": "models/\(model)",
                "generation_config": [
                    "response_modalities": ["AUDIO"],
                    "speech_config": [
                        "voice_config": [
                            "prebuilt_voice_config": [
                                "voice_name": "Aoede"
                            ]
                        ]
                    ]
                ],
                "system_instruction": [
                    "parts": [
                        ["text": systemPrompt]
                    ]
                ],
                "tools": [
                    ["function_declarations": GeminiTools.toAPIFormat()]
                ]
            ]
        ]

        sendJSON(setupMessage)
    }

    private var systemPrompt: String {
        """
        You are a helpful cooking assistant for the app "Heard, Chef" - named after the classic kitchen acknowledgment. When users give you a command, you can respond with "Heard, chef!" to acknowledge.

        You help users manage their kitchen inventory and recipes through voice commands.

        You can:
        - Add, remove, and update ingredients in the user's inventory
        - Create, edit, and search recipes
        - Suggest recipes based on available ingredients
        - Parse receipts and grocery photos to add items to inventory

        Be conversational, friendly, and concise like a helpful sous chef. When users ask you to do something with their inventory or recipes, use the appropriate function calls.

        When listing items, be brief. Don't read out every detail unless asked.
        When adding items, confirm what you added with enthusiasm.
        When suggesting recipes, consider what ingredients the user has available.
        """
    }

    // MARK: - Audio Streaming

    func sendAudio(data: Data) {
        guard isConnected else { return }

        let base64Audio = data.base64EncodedString()

        let message: [String: Any] = [
            "realtime_input": [
                "media_chunks": [
                    [
                        "mime_type": "audio/pcm;rate=16000",
                        "data": base64Audio
                    ]
                ]
            ]
        ]

        sendJSON(message)
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessage() // Continue receiving

                case .failure(let error):
                    self.delegate?.geminiService(self, didReceiveError: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleTextMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Handle setup complete
        if let setupComplete = json["setupComplete"] as? [String: Any] {
            isConnected = true
            delegate?.geminiServiceDidConnect(self)
            return
        }

        // Handle server content
        if let serverContent = json["serverContent"] as? [String: Any] {
            handleServerContent(serverContent)
            return
        }

        // Handle tool call
        if let toolCall = json["toolCall"] as? [String: Any] {
            handleToolCall(toolCall)
            return
        }
    }

    private func handleServerContent(_ content: [String: Any]) {
        // Handle model turn
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {

            for part in parts {
                // Text response
                if let text = part["text"] as? String {
                    delegate?.geminiService(self, didReceiveResponse: text)
                }

                // Audio response
                if let inlineData = part["inlineData"] as? [String: Any],
                   let base64Data = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: base64Data) {
                    delegate?.geminiService(self, didReceiveAudio: audioData)
                }

                // Transcript
                if let transcript = part["transcript"] as? String {
                    let isFinal = content["turnComplete"] as? Bool ?? false
                    delegate?.geminiService(self, didReceiveTranscript: transcript, isFinal: isFinal)
                }
            }
        }
    }

    // MARK: - Tool/Function Calling

    private func handleToolCall(_ toolCall: [String: Any]) {
        guard let functionCalls = toolCall["functionCalls"] as? [[String: Any]] else { return }

        for call in functionCalls {
            guard let id = call["id"] as? String,
                  let name = call["name"] as? String,
                  let args = call["args"] as? [String: Any] else {
                continue
            }

            // Execute the function and get result
            let result = executeFunction(name: name, args: args)

            // Send function response back
            let response: [String: Any] = [
                "toolResponse": [
                    "functionResponses": [
                        [
                            "id": id,
                            "name": name,
                            "response": result
                        ]
                    ]
                ]
            ]

            sendJSON(response)
            delegate?.geminiService(self, didExecuteFunctionCall: name, result: String(describing: result))
        }
    }

    private func executeFunction(name: String, args: [String: Any]) -> [String: Any] {
        switch name {
        // Inventory functions
        case "inventory_add":
            return inventoryAdd(args: args)
        case "inventory_remove":
            return inventoryRemove(args: args)
        case "inventory_update":
            return inventoryUpdate(args: args)
        case "inventory_list":
            return inventoryList(args: args)
        case "inventory_search":
            return inventorySearch(args: args)
        case "inventory_check":
            return inventoryCheck(args: args)

        // Recipe functions
        case "recipe_create":
            return recipeCreate(args: args)
        case "recipe_update":
            return recipeUpdate(args: args)
        case "recipe_delete":
            return recipeDelete(args: args)
        case "recipe_list":
            return recipeList(args: args)
        case "recipe_search":
            return recipeSearch(args: args)
        case "recipe_suggest":
            return recipeSuggest(args: args)

        default:
            return ["error": "Unknown function: \(name)"]
        }
    }

    // MARK: - Inventory Functions

    private func inventoryAdd(args: [String: Any]) -> [String: Any] {
        guard let name = args["name"] as? String,
              let quantity = args["quantity"] as? Double,
              let unit = args["unit"] as? String else {
            return ["error": "Missing required parameters"]
        }

        let category = (args["category"] as? String).flatMap { IngredientCategory(rawValue: $0) } ?? .other
        let location = (args["location"] as? String).flatMap { StorageLocation(rawValue: $0) } ?? .pantry
        let expiryDate: Date? = (args["expiry"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

        let ingredient = Ingredient(
            name: name,
            quantity: quantity,
            unit: unit,
            category: category,
            location: location,
            expiryDate: expiryDate
        )

        modelContext.insert(ingredient)

        return ["success": true, "message": "Added \(quantity) \(unit) of \(name) to \(location.rawValue)"]
    }

    private func inventoryRemove(args: [String: Any]) -> [String: Any] {
        guard let name = args["name"] as? String else {
            return ["error": "Missing ingredient name"]
        }

        let descriptor = FetchDescriptor<Ingredient>(predicate: #Predicate { $0.name.localizedStandardContains(name) })

        guard let ingredients = try? modelContext.fetch(descriptor),
              let ingredient = ingredients.first else {
            return ["error": "Ingredient '\(name)' not found"]
        }

        if let quantityToRemove = args["quantity"] as? Double {
            ingredient.quantity -= quantityToRemove
            if ingredient.quantity <= 0 {
                modelContext.delete(ingredient)
                return ["success": true, "message": "Removed all \(name) from inventory"]
            }
            ingredient.updatedAt = Date()
            return ["success": true, "message": "Reduced \(name) by \(quantityToRemove). Remaining: \(ingredient.quantity) \(ingredient.unit)"]
        } else {
            modelContext.delete(ingredient)
            return ["success": true, "message": "Removed \(name) from inventory"]
        }
    }

    private func inventoryUpdate(args: [String: Any]) -> [String: Any] {
        guard let name = args["name"] as? String else {
            return ["error": "Missing ingredient name"]
        }

        let descriptor = FetchDescriptor<Ingredient>(predicate: #Predicate { $0.name.localizedStandardContains(name) })

        guard let ingredients = try? modelContext.fetch(descriptor),
              let ingredient = ingredients.first else {
            return ["error": "Ingredient '\(name)' not found"]
        }

        if let newName = args["newName"] as? String {
            ingredient.name = newName
        }
        if let quantity = args["quantity"] as? Double {
            ingredient.quantity = quantity
        }
        if let unit = args["unit"] as? String {
            ingredient.unit = unit
        }
        if let categoryStr = args["category"] as? String,
           let category = IngredientCategory(rawValue: categoryStr) {
            ingredient.category = category
        }
        if let locationStr = args["location"] as? String,
           let location = StorageLocation(rawValue: locationStr) {
            ingredient.location = location
        }
        if let expiryStr = args["expiry"] as? String {
            ingredient.expiryDate = ISO8601DateFormatter().date(from: expiryStr)
        }

        ingredient.updatedAt = Date()

        return ["success": true, "message": "Updated \(ingredient.name)"]
    }

    private func inventoryList(args: [String: Any]) -> [String: Any] {
        var descriptor = FetchDescriptor<Ingredient>(sortBy: [SortDescriptor(\Ingredient.name)])

        if let categoryStr = args["category"] as? String {
            descriptor.predicate = #Predicate { $0.categoryRaw == categoryStr }
        } else if let locationStr = args["location"] as? String {
            descriptor.predicate = #Predicate { $0.locationRaw == locationStr }
        }

        guard let ingredients = try? modelContext.fetch(descriptor) else {
            return ["error": "Failed to fetch inventory"]
        }

        let items = ingredients.map { "\($0.name): \($0.displayQuantity)" }

        return ["count": ingredients.count, "items": items]
    }

    private func inventorySearch(args: [String: Any]) -> [String: Any] {
        guard let query = args["query"] as? String else {
            return ["error": "Missing search query"]
        }

        let descriptor = FetchDescriptor<Ingredient>(predicate: #Predicate { $0.name.localizedStandardContains(query) })

        guard let ingredients = try? modelContext.fetch(descriptor) else {
            return ["error": "Search failed"]
        }

        let items = ingredients.map { ["name": $0.name, "quantity": $0.displayQuantity, "location": $0.location.rawValue] }

        return ["count": ingredients.count, "results": items]
    }

    private func inventoryCheck(args: [String: Any]) -> [String: Any] {
        guard let name = args["name"] as? String else {
            return ["error": "Missing ingredient name"]
        }

        let descriptor = FetchDescriptor<Ingredient>(predicate: #Predicate { $0.name.localizedStandardContains(name) })

        guard let ingredients = try? modelContext.fetch(descriptor) else {
            return ["found": false]
        }

        if let ingredient = ingredients.first {
            return [
                "found": true,
                "name": ingredient.name,
                "quantity": ingredient.quantity,
                "unit": ingredient.unit,
                "location": ingredient.location.rawValue
            ]
        }

        return ["found": false]
    }

    // MARK: - Recipe Functions

    private func recipeCreate(args: [String: Any]) -> [String: Any] {
        guard let name = args["name"] as? String,
              let ingredientsJSON = args["ingredients"] as? String,
              let stepsJSON = args["steps"] as? String else {
            return ["error": "Missing required parameters"]
        }

        guard let ingredientsData = ingredientsJSON.data(using: .utf8),
              let stepsData = stepsJSON.data(using: .utf8),
              let ingredients = try? JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData),
              let steps = try? JSONDecoder().decode([String].self, from: stepsData) else {
            return ["error": "Invalid ingredients or steps format"]
        }

        let recipe = Recipe(
            name: name,
            description: args["description"] as? String,
            ingredients: ingredients,
            steps: steps,
            prepTime: args["prepTime"] as? Int,
            cookTime: args["cookTime"] as? Int,
            servings: args["servings"] as? Int,
            tags: parseJSONArray(args["tags"] as? String) ?? [],
            source: .aiDrafted
        )

        modelContext.insert(recipe)

        return ["success": true, "message": "Created recipe '\(name)'", "id": recipe.id.uuidString]
    }

    private func recipeUpdate(args: [String: Any]) -> [String: Any] {
        guard let idString = args["id"] as? String,
              let id = UUID(uuidString: idString) else {
            return ["error": "Invalid recipe ID"]
        }

        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })

        guard let recipes = try? modelContext.fetch(descriptor),
              let recipe = recipes.first else {
            return ["error": "Recipe not found"]
        }

        if let name = args["name"] as? String {
            recipe.name = name
        }
        if let description = args["description"] as? String {
            recipe.descriptionText = description
        }
        if let ingredientsJSON = args["ingredients"] as? String,
           let ingredientsData = ingredientsJSON.data(using: .utf8),
           let ingredients = try? JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData) {
            recipe.ingredients = ingredients
        }
        if let stepsJSON = args["steps"] as? String,
           let stepsData = stepsJSON.data(using: .utf8),
           let steps = try? JSONDecoder().decode([String].self, from: stepsData) {
            recipe.steps = steps
        }
        if let prepTime = args["prepTime"] as? Int {
            recipe.prepTime = prepTime
        }
        if let cookTime = args["cookTime"] as? Int {
            recipe.cookTime = cookTime
        }
        if let servings = args["servings"] as? Int {
            recipe.servings = servings
        }
        if let tagsJSON = args["tags"] as? String,
           let tags = parseJSONArray(tagsJSON) {
            recipe.tags = tags
        }

        recipe.updatedAt = Date()

        return ["success": true, "message": "Updated recipe '\(recipe.name)'"]
    }

    private func recipeDelete(args: [String: Any]) -> [String: Any] {
        guard let idString = args["id"] as? String,
              let id = UUID(uuidString: idString) else {
            return ["error": "Invalid recipe ID"]
        }

        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })

        guard let recipes = try? modelContext.fetch(descriptor),
              let recipe = recipes.first else {
            return ["error": "Recipe not found"]
        }

        let name = recipe.name
        modelContext.delete(recipe)

        return ["success": true, "message": "Deleted recipe '\(name)'"]
    }

    private func recipeList(args: [String: Any]) -> [String: Any] {
        let descriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\Recipe.name)])

        guard let recipes = try? modelContext.fetch(descriptor) else {
            return ["error": "Failed to fetch recipes"]
        }

        var filteredRecipes = recipes

        if let tagsJSON = args["tags"] as? String,
           let tags = parseJSONArray(tagsJSON) {
            filteredRecipes = recipes.filter { recipe in
                tags.allSatisfy { tag in recipe.tags.contains(tag) }
            }
        }

        let items = filteredRecipes.map { [
            "id": $0.id.uuidString,
            "name": $0.name,
            "totalTime": $0.formattedTotalTime ?? "N/A"
        ] }

        return ["count": filteredRecipes.count, "recipes": items]
    }

    private func recipeSearch(args: [String: Any]) -> [String: Any] {
        guard let query = args["query"] as? String else {
            return ["error": "Missing search query"]
        }

        let descriptor = FetchDescriptor<Recipe>()

        guard let recipes = try? modelContext.fetch(descriptor) else {
            return ["error": "Search failed"]
        }

        let filtered = recipes.filter { recipe in
            recipe.name.localizedCaseInsensitiveContains(query) ||
            recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }

        let items = filtered.map { ["id": $0.id.uuidString, "name": $0.name] }

        return ["count": filtered.count, "results": items]
    }

    private func recipeSuggest(args: [String: Any]) -> [String: Any] {
        let useInventory = args["useInventory"] as? Bool ?? true

        let recipeDescriptor = FetchDescriptor<Recipe>()
        let inventoryDescriptor = FetchDescriptor<Ingredient>()

        guard let recipes = try? modelContext.fetch(recipeDescriptor),
              let inventory = try? modelContext.fetch(inventoryDescriptor) else {
            return ["error": "Failed to fetch data"]
        }

        var suggestions: [[String: Any]] = []

        for recipe in recipes {
            let canMake = recipe.canMake(with: inventory)
            let missing = recipe.missingIngredients(from: inventory)

            if useInventory && !canMake {
                continue
            }

            suggestions.append([
                "id": recipe.id.uuidString,
                "name": recipe.name,
                "canMake": canMake,
                "missingCount": missing.count,
                "totalTime": recipe.formattedTotalTime ?? "N/A"
            ])
        }

        // Sort by canMake first, then by missing count
        suggestions.sort { a, b in
            let aCanMake = a["canMake"] as? Bool ?? false
            let bCanMake = b["canMake"] as? Bool ?? false
            if aCanMake != bCanMake { return aCanMake }
            return (a["missingCount"] as? Int ?? 0) < (b["missingCount"] as? Int ?? 0)
        }

        return ["count": suggestions.count, "suggestions": Array(suggestions.prefix(5))]
    }

    // MARK: - Helpers

    private func sendJSON(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(string)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    private func parseJSONArray(_ json: String?) -> [String]? {
        guard let json = json,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return array
    }
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // Connection opened, setup message will be sent
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.isConnected = false
            self.delegate?.geminiServiceDidDisconnect(self)
        }
    }
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .connectionFailed:
            return "Failed to connect to Gemini"
        }
    }
}
