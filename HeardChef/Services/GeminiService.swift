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
    func geminiService(_ service: GeminiService, didExecuteFunctionCall name: String, result: FunctionResult)
    func geminiServiceDidStartResponse(_ service: GeminiService)
    func geminiServiceDidEndResponse(_ service: GeminiService)
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
    private var isStreamingResponse = false
    private let supportsFileAttachments = false

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

        sendSetupMessage()
        receiveMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        isStreamingResponse = false
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

        IMPORTANT GUIDELINES:
        - Be conversational, friendly, and concise like a helpful sous chef
        - When adding items, confirm what you added
        - When listing items, be brief - don't read every detail unless asked
        - When suggesting recipes, mention how many ingredients are available
        - If a function call fails, explain the error simply
        - If you're unsure what the user wants, ask for clarification

        \(Ingredient.schemaDescription)

        \(Recipe.schemaDescription)
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

    // MARK: - Text & Image Sending (Multimodal)

    /// Send a text message to the active session.
    func sendText(_ text: String) {
        guard isConnected else { return }

        let message: [String: Any] = [
            "client_content": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ],
                "turn_complete": true
            ]
        ]

        sendJSON(message)
    }

    /// Send an image to the active session (e.g. for vision tasks).
    /// Use client_content so the image is tied to a user turn.
    func sendPhoto(_ imageData: Data) {
        guard isConnected else { return }

        let base64Image = imageData.base64EncodedString()

        let message: [String: Any] = [
            "client_content": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            [
                                "inline_data": [
                                    "mime_type": "image/jpeg",
                                    "data": base64Image
                                ]
                            ]
                        ]
                    ]
                ],
                "turn_complete": true
            ]
        ]

        sendJSON(message)
    }

    /// Send text + image together as one multimodal user turn.
    func sendTextWithPhoto(_ text: String, imageData: Data) {
        guard isConnected else { return }

        let base64Image = imageData.base64EncodedString()

        let message: [String: Any] = [
            "client_content": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text],
                            [
                                "inline_data": [
                                    "mime_type": "image/jpeg",
                                    "data": base64Image
                                ]
                            ]
                        ]
                    ]
                ],
                "turn_complete": true
            ]
        ]

        sendJSON(message)
    }

    // MARK: - Video Streaming

    /// Send a JPEG video frame over the Live API realtime input.
    /// Uses image/jpeg per Google Live API examples.
    func sendVideoFrame(_ imageData: Data) {
        guard isConnected else { return }

        let base64Image = imageData.base64EncodedString()
        let message: [String: Any] = [
            "realtime_input": [
                "media_chunks": [
                    [
                        "mime_type": "image/jpeg",
                        "data": base64Image
                    ]
                ]
            ]
        ]

        sendJSON(message)
    }

    // MARK: - File Attachments (Stub)

    func sendVideoAttachment(url: URL, utType: String?) {
        guard isConnected else { return }
        guard supportsFileAttachments else { return }
        // TODO: Upload video attachment when Gemini supports it.
        _ = (url, utType)
    }

    func sendDocumentAttachment(url: URL, utType: String?) {
        guard isConnected else { return }
        guard supportsFileAttachments else { return }
        // TODO: Upload document attachment when Gemini supports it.
        _ = (url, utType)
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocketTask?.receive { result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessage()

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
        if json["setupComplete"] != nil {
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
        guard let modelTurn = content["modelTurn"] as? [String: Any],
              let parts = modelTurn["parts"] as? [[String: Any]] else {
            return
        }
        
        let isComplete = content["turnComplete"] as? Bool ?? false
        if !isStreamingResponse {
            isStreamingResponse = true
            delegate?.geminiServiceDidStartResponse(self)
        }

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

        if isComplete {
            isStreamingResponse = false
            delegate?.geminiServiceDidEndResponse(self)
        }
    }

    // MARK: - Function Calling

    private func handleToolCall(_ toolCall: [String: Any]) {
        guard let functionCalls = toolCall["functionCalls"] as? [[String: Any]] else { return }

        for rawCall in functionCalls {
            guard let id = rawCall["id"] as? String,
                  let name = rawCall["name"] as? String,
                  let args = rawCall["args"] as? [String: Any] else {
                continue
            }

            let call = FunctionCall(id: id, name: name, arguments: args)

            // Validate the call
            if let validationError = GeminiTools.validate(call: call) {
                let result = FunctionResult.error(id: id, name: name, message: validationError)
                sendFunctionResponse(result)
                delegate?.geminiService(self, didExecuteFunctionCall: name, result: result)
                continue
            }

            // Execute the function
            let result = executeFunction(call)
            sendFunctionResponse(result)
            delegate?.geminiService(self, didExecuteFunctionCall: name, result: result)
        }
    }

    private func sendFunctionResponse(_ result: FunctionResult) {
        let response: [String: Any] = [
            "toolResponse": [
                "functionResponses": [result.toAPIFormat()]
            ]
        ]
        sendJSON(response)
    }

    private func executeFunction(_ call: FunctionCall) -> FunctionResult {
        switch call.name {
        // Inventory functions
        case "add_ingredient":
            return inventoryAdd(call)
        case "remove_ingredient":
            return inventoryRemove(call)
        case "update_ingredient":
            return inventoryUpdate(call)
        case "list_ingredients":
            return inventoryList(call)
        case "search_ingredients":
            return inventorySearch(call)
        case "get_ingredient":
            return inventoryCheck(call)
        // Recipe functions
        case "create_recipe":
            return recipeCreate(call)
        case "update_recipe":
            return recipeUpdate(call) // Added
        case "delete_recipe":
            return recipeDelete(call)
        case "get_recipe":
            return recipeGet(call)
        case "list_recipes":
            return recipeList(call)
        case "search_recipes":
            return recipeSearch(call)
        case "suggest_recipes":
            return recipeSuggest(call)
        case "check_recipe_availability":
            return recipeCheckAvailability(call)
        default:
            return .error(id: call.id, name: call.name, message: "Unknown function: \(call.name)")
        }
    }

    // MARK: - Inventory Functions

    private func inventoryAdd(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing ingredient name")
        }
        guard let quantity = call.double("quantity"), quantity > 0 else {
            return .error(id: call.id, name: call.name, message: "Quantity must be greater than 0")
        }
        guard let unitStr = call.string("unit"),
              let unit = Unit.parse(unitStr) else {
            return .error(id: call.id, name: call.name, message: "Invalid unit. Valid units: \(Unit.allValidStrings.joined(separator: ", "))")
        }

        let category = call.string("category").flatMap { IngredientCategory.parse($0) } ?? .other
        let location = call.string("location").flatMap { StorageLocation.parse($0) } ?? .pantry
        let expiryDate = call.date("expiryDate")
        let notes = call.string("notes")

        let (ingredient, wasCreated) = Ingredient.findOrCreate(
            name: name,
            quantity: quantity,
            unit: unit,
            category: category,
            location: location,
            expiryDate: expiryDate,
            notes: notes,
            mergeQuantity: true,
            in: modelContext
        )

        let message = wasCreated
            ? "Added \(ingredient.displayQuantity) of \(ingredient.name) to the \(ingredient.location.displayName)"
            : "Updated \(ingredient.name) - now have \(ingredient.displayQuantity) in the \(ingredient.location.displayName)"

        return .success(
            id: call.id,
            name: call.name,
            message: message,
            data: [
                "wasCreated": wasCreated,
                "ingredient": [
                    "name": ingredient.name,
                    "quantity": ingredient.quantity,
                    "unit": ingredient.unitRaw,
                    "location": ingredient.locationRaw
                ]
            ]
        )
    }

    private func inventoryRemove(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing ingredient name")
        }

        guard let ingredient = Ingredient.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "'\(name)' not found in inventory")
        }

        if let quantity = call.double("quantity") {
            let removed = ingredient.removeQuantity(quantity)

            if ingredient.quantity <= 0 {
                modelContext.delete(ingredient)
                return .success(
                    id: call.id,
                    name: call.name,
                    message: "Removed all \(ingredient.name) from inventory"
                )
            }

            return .success(
                id: call.id,
                name: call.name,
                message: "Removed \(removed) \(ingredient.unitRaw) of \(ingredient.name). \(ingredient.displayQuantity) remaining.",
                data: ["remaining": ingredient.quantity]
            )
        }

        let ingredientName = ingredient.name
        modelContext.delete(ingredient)
        return .success(
            id: call.id,
            name: call.name,
            message: "Removed \(ingredientName) from inventory"
        )
    }

    private func inventoryUpdate(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing ingredient name")
        }

        guard let patch = call.arguments["patch"] as? [String: Any] else {
            return .error(id: call.id, name: call.name, message: "Missing update patch")
        }

        guard let ingredient = Ingredient.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "'\(name)' not found in inventory")
        }

        var params = IngredientUpdateParams()
        if let newName = patch["name"] as? String { params.name = newName }
        if let quantity = parseDouble(patch["quantity"]) { params.quantity = quantity }
        if let unitStr = patch["unit"] as? String { params.unit = unitStr }
        if let categoryStr = patch["category"] as? String { params.category = categoryStr }
        if let locationStr = patch["location"] as? String { params.location = locationStr }
        if let expiryDate = parseDate(patch["expiryDate"]) { params.expiryDate = expiryDate }
        if let notes = patch["notes"] as? String { params.notes = notes }

        let hasChanges = params.name != nil
            || params.quantity != nil
            || params.unit != nil
            || params.category != nil
            || params.location != nil
            || params.expiryDate != nil
            || params.notes != nil

        if !hasChanges {
            return .error(id: call.id, name: call.name, message: "No changes specified")
        }

        ingredient.update(with: params)

        return .success(
            id: call.id,
            name: call.name,
            message: "Updated \(ingredient.name)",
            data: [
                "ingredient": [
                    "name": ingredient.name,
                    "quantity": ingredient.quantity,
                    "unit": ingredient.unitRaw,
                    "location": ingredient.locationRaw
                ]
            ]
        )
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: string) { return date }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        return dateFormatter.date(from: string)
    }

    private func inventoryList(_ call: FunctionCall) -> FunctionResult {
        let category = call.string("category").flatMap { IngredientCategory.parse($0) }
        let location = call.string("location").flatMap { StorageLocation.parse($0) }

        let ingredients = Ingredient.list(category: category, location: location, in: modelContext)

        if ingredients.isEmpty {
            var message = "No ingredients"
            if let cat = category { message += " in \(cat.displayName)" }
            if let loc = location { message += " in the \(loc.displayName)" }
            return .success(id: call.id, name: call.name, message: message, data: ["count": 0, "items": []])
        }

        let items = ingredients.map { "\($0.name): \($0.displayQuantity)" }
        var message = "\(ingredients.count) item\(ingredients.count == 1 ? "" : "s")"
        if let loc = location { message += " in the \(loc.displayName)" }
        if let cat = category { message += " (\(cat.displayName))" }

        return .success(
            id: call.id,
            name: call.name,
            message: message,
            data: ["count": ingredients.count, "items": items]
        )
    }

    private func inventorySearch(_ call: FunctionCall) -> FunctionResult {
        guard let query = call.string("query") else {
            return .error(id: call.id, name: call.name, message: "Missing search query")
        }

        let results = Ingredient.search(query: query, in: modelContext)
        if results.isEmpty {
            return .success(
                id: call.id,
                name: call.name,
                message: "No ingredients matching '\(query)'",
                data: ["count": 0, "results": []]
            )
        }

        let items = results.map { [
            "name": $0.name,
            "quantity": $0.displayQuantity,
            "location": $0.location.displayName
        ] }

        return .success(
            id: call.id,
            name: call.name,
            message: "Found \(results.count) matching ingredient\(results.count == 1 ? "" : "s")",
            data: ["count": results.count, "results": items]
        )
    }

    private func inventoryCheck(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing ingredient name")
        }

        guard let ingredient = Ingredient.find(named: name, in: modelContext) else {
            return .success(
                id: call.id,
                name: call.name,
                message: "No '\(name)' in inventory",
                data: ["found": false]
            )
        }

        var data: [String: Any] = [
            "found": true,
            "name": ingredient.name,
            "quantity": ingredient.quantity,
            "unit": ingredient.unitRaw,
            "displayQuantity": ingredient.displayQuantity,
            "location": ingredient.location.displayName,
            "category": ingredient.category.displayName
        ]

        if let days = ingredient.daysUntilExpiry {
            data["daysUntilExpiry"] = days
            data["isExpired"] = ingredient.isExpired
            data["isExpiringSoon"] = ingredient.isExpiringSoon
        }

        let expiryInfo: String
        if ingredient.isExpired {
            expiryInfo = " (EXPIRED)"
        } else if ingredient.isExpiringSoon {
            expiryInfo = " (expiring soon)"
        } else {
            expiryInfo = ""
        }

        return .success(
            id: call.id,
            name: call.name,
            message: "You have \(ingredient.displayQuantity) of \(ingredient.name) in the \(ingredient.location.displayName)\(expiryInfo)",
            data: data
        )
    }

    // MARK: - Recipe Functions

    private func recipeCreate(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        // Parse ingredients from JSON string
        guard let ingredientsJSON = call.string("ingredients"),
              let ingredientsData = ingredientsJSON.data(using: .utf8),
              let ingredientsArray = try? JSONSerialization.jsonObject(with: ingredientsData) as? [[String: Any]] else {
            return .error(id: call.id, name: call.name, message: "Invalid ingredients format - expected JSON array")
        }

        let recipeIngredients = ingredientsArray.compactMap { RecipeIngredient.fromArguments($0) }
        if recipeIngredients.isEmpty {
            return .error(id: call.id, name: call.name, message: "No valid ingredients provided")
        }

        // Parse steps from JSON string
        guard let stepsJSON = call.string("steps"),
              let stepsData = stepsJSON.data(using: .utf8),
              let stepsArray = try? JSONSerialization.jsonObject(with: stepsData) as? [Any] else {
            return .error(id: call.id, name: call.name, message: "Invalid steps format - expected JSON array")
        }

        var recipeSteps: [RecipeStep] = []
        for (index, stepItem) in stepsArray.enumerated() {
            if let stepStr = stepItem as? String {
                recipeSteps.append(RecipeStep(instruction: stepStr, orderIndex: index))
            } else if let stepDict = stepItem as? [String: Any],
                      let step = RecipeStep.fromArguments(stepDict, index: index) {
                recipeSteps.append(step)
            }
        }

        if recipeSteps.isEmpty {
            return .error(id: call.id, name: call.name, message: "No valid steps provided")
        }

        // Parse optional parameters
        let description = call.string("description")
        let prepTime = call.int("prepTime")
        let cookTime = call.int("cookTime")
        let servings = call.int("servings")
        let difficulty = call.string("difficulty").flatMap { RecipeDifficulty.parse($0) } ?? .medium

        var tags: [String] = []
        if let tagsJSON = call.string("tags"),
           let tagsData = tagsJSON.data(using: .utf8),
           let tagsArray = try? JSONSerialization.jsonObject(with: tagsData) as? [String] {
            tags = tagsArray
        }

        // Check if recipe already exists
        if Recipe.find(named: name, in: modelContext) != nil {
            return .error(id: call.id, name: call.name, message: "A recipe named '\(name)' already exists")
        }

        // Create the recipe
        let recipe = Recipe(
            name: name,
            description: description,
            ingredients: recipeIngredients,
            steps: recipeSteps,
            prepTime: prepTime,
            cookTime: cookTime,
            servings: servings,
            tags: tags,
            difficulty: difficulty,
            source: .aiDrafted
        )

        modelContext.insert(recipe)

        return .success(
            id: call.id,
            name: call.name,
            message: "Created recipe '\(recipe.name)' with \(recipeIngredients.count) ingredients and \(recipeSteps.count) steps",
            data: [
                "name": recipe.name,
                "ingredientCount": recipeIngredients.count,
                "stepCount": recipeSteps.count
            ]
        )
    }

    private func recipeUpdate(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        guard let recipe = Recipe.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "Recipe '\(name)' not found")
        }

        var changes: [String: Any] = [:]

        // Update simple fields
        if let newName = call.string("newName") { changes["name"] = newName }
        if let description = call.string("description") { changes["description"] = description }
        if let prepTime = call.int("prepTime") { changes["prepTime"] = prepTime }
        if let cookTime = call.int("cookTime") { changes["cookTime"] = cookTime }
        if let servings = call.int("servings") { changes["servings"] = servings }
        if let difficulty = call.string("difficulty") { changes["difficulty"] = difficulty }

        // Update tags
        if let tagsJSON = call.string("tags"),
           let tagsData = tagsJSON.data(using: .utf8),
           let tagsArray = try? JSONSerialization.jsonObject(with: tagsData) as? [String] {
            changes["tags"] = tagsArray
        }

        // Update ingredients (Full Replace)
        if let ingredientsJSON = call.string("ingredients"),
           let ingredientsData = ingredientsJSON.data(using: .utf8),
           let ingredientsArray = try? JSONSerialization.jsonObject(with: ingredientsData) as? [[String: Any]] {
            let oldIngredients = recipe.ingredients
            let newIngredients = ingredientsArray.compactMap { RecipeIngredient.fromArguments($0) }
            recipe.ingredients = newIngredients // SwiftData relationship update
            for ingredient in oldIngredients {
                modelContext.delete(ingredient)
            }
            changes["ingredients"] = "\(newIngredients.count) items"
        }

        // Update steps (Full Replace)
        if let stepsJSON = call.string("steps"),
           let stepsData = stepsJSON.data(using: .utf8),
           let stepsArray = try? JSONSerialization.jsonObject(with: stepsData) as? [Any] {
            let oldSteps = recipe.steps
            var newSteps: [RecipeStep] = []
            for (index, stepItem) in stepsArray.enumerated() {
                if let stepStr = stepItem as? String {
                    newSteps.append(RecipeStep(instruction: stepStr, orderIndex: index))
                } else if let stepDict = stepItem as? [String: Any],
                          let step = RecipeStep.fromArguments(stepDict, index: index) {
                    newSteps.append(step)
                }
            }
            recipe.steps = newSteps // SwiftData relationship update
            for step in oldSteps {
                modelContext.delete(step)
            }
            changes["steps"] = "\(newSteps.count) steps"
        }

        recipe.update(from: changes)

        return .success(
            id: call.id,
            name: call.name,
            message: "Updated recipe '\(recipe.name)'",
            data: ["updatedFields": Array(changes.keys)]
        )
    }

    private func recipeList(_ call: FunctionCall) -> FunctionResult {
        let tag = call.string("tag")
        let recipes = Recipe.list(tag: tag, in: modelContext)

        if recipes.isEmpty {
            let message = tag != nil ? "No recipes with tag '\(tag!)'" : "No recipes saved yet"
            return .success(id: call.id, name: call.name, message: message, data: ["count": 0, "recipes": []])
        }

        let inventory = Ingredient.list(in: modelContext)
        let recipeList = recipes.map { recipe -> [String: Any] in
            let canMake = recipe.canMake(with: inventory)
            let missing = recipe.missingIngredients(from: inventory).count
            return [
                "name": recipe.name,
                "description": recipe.descriptionText ?? "",
                "canMake": canMake,
                "missingCount": missing,
                "totalTime": recipe.formattedTotalTime ?? "Unknown",
                "difficulty": recipe.difficulty.displayName
            ]
        }

        return .success(
            id: call.id,
            name: call.name,
            message: "\(recipes.count) recipe\(recipes.count == 1 ? "" : "s") found",
            data: ["count": recipes.count, "recipes": recipeList]
        )
    }

    private func recipeSearch(_ call: FunctionCall) -> FunctionResult {
        guard let query = call.string("query") else {
            return .error(id: call.id, name: call.name, message: "Missing search query")
        }

        let results = Recipe.search(query: query, in: modelContext)

        if results.isEmpty {
            return .success(
                id: call.id,
                name: call.name,
                message: "No recipes matching '\(query)'",
                data: ["count": 0, "results": []]
            )
        }

        let inventory = Ingredient.list(in: modelContext)
        let recipeList = results.map { recipe -> [String: Any] in
            [
                "name": recipe.name,
                "canMake": recipe.canMake(with: inventory),
                "missingCount": recipe.missingIngredients(from: inventory).count
            ]
        }

        return .success(
            id: call.id,
            name: call.name,
            message: "Found \(results.count) recipe\(results.count == 1 ? "" : "s") matching '\(query)'",
            data: ["count": results.count, "results": recipeList]
        )
    }

    private func recipeSuggest(_ call: FunctionCall) -> FunctionResult {
        let inventory = Ingredient.list(in: modelContext)

        if inventory.isEmpty {
            return .success(
                id: call.id,
                name: call.name,
                message: "No ingredients in inventory. Add some ingredients first!",
                data: ["count": 0, "suggestions": []]
            )
        }

        let maxMissing = call.int("maxMissingIngredients") ?? 3
        let onlyFullyMakeable = call.bool("onlyFullyMakeable") ?? false

        var suggestions = Recipe.suggestFromInventory(
            inventory: inventory,
            maxMissingIngredients: maxMissing,
            in: modelContext
        )

        if onlyFullyMakeable {
            suggestions = suggestions.filter { $0.missing.isEmpty }
        }

        if suggestions.isEmpty {
            let message = onlyFullyMakeable
                ? "No recipes can be made with current inventory"
                : "No recipes found with \(maxMissing) or fewer missing ingredients"
            return .success(id: call.id, name: call.name, message: message, data: ["count": 0, "suggestions": []])
        }

        let suggestionList = suggestions.map { suggestion -> [String: Any] in
            [
                "name": suggestion.recipe.name,
                "matchPercentage": Int(suggestion.matchPercentage * 100),
                "missingIngredients": suggestion.missing.map { $0.name },
                "totalTime": suggestion.recipe.formattedTotalTime ?? "Unknown"
            ]
        }

        let fullyMakeableCount = suggestions.filter { $0.missing.isEmpty }.count

        return .success(
            id: call.id,
            name: call.name,
            message: "\(suggestions.count) recipe\(suggestions.count == 1 ? "" : "s") available. \(fullyMakeableCount) can be made right now.",
            data: ["count": suggestions.count, "fullyMakeable": fullyMakeableCount, "suggestions": suggestionList]
        )
    }

    private func recipeGet(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        guard let recipe = Recipe.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "Recipe '\(name)' not found")
        }

        let inventory = Ingredient.list(in: modelContext)
        let missing = recipe.missingIngredients(from: inventory)

        let ingredientList = recipe.ingredients.map { ing -> [String: Any] in
            var dict: [String: Any] = ["name": ing.name, "displayText": ing.displayText]
            if let qty = ing.quantity { dict["quantity"] = qty }
            if let unit = ing.unit { dict["unit"] = unit.displayName }
            if let prep = ing.preparation { dict["preparation"] = prep }
            dict["available"] = !missing.contains { $0.normalizedName == ing.normalizedName }
            return dict
        }

        let stepList = recipe.orderedSteps.map { step -> [String: Any] in
            var dict: [String: Any] = ["instruction": step.instruction, "index": step.orderIndex]
            if let duration = step.durationMinutes { dict["durationMinutes"] = duration }
            return dict
        }

        return .success(
            id: call.id,
            name: call.name,
            message: "Found recipe '\(recipe.name)'",
            data: [
                "name": recipe.name,
                "description": recipe.descriptionText ?? "",
                "ingredients": ingredientList,
                "steps": stepList,
                "missingCount": missing.count,
                "canMake": missing.isEmpty,
                "totalTime": recipe.formattedTotalTime ?? "Unknown",
                "difficulty": recipe.difficulty.displayName,
                "tags": recipe.tags
            ]
        )
    }

    private func recipeCheckAvailability(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        guard let recipe = Recipe.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "Recipe '\(name)' not found")
        }

        let inventory = Ingredient.list(in: modelContext)
        let missing = recipe.missingIngredients(from: inventory)

        let missingList = missing.map { ingredient -> [String: Any] in
            ["name": ingredient.name, "displayText": ingredient.displayText]
        }

        let canMake = missing.isEmpty
        let message = canMake
            ? "You can make '\(recipe.name)' with current inventory"
            : "Missing \(missing.count) item\(missing.count == 1 ? "" : "s") for '\(recipe.name)'"

        return .success(
            id: call.id,
            name: call.name,
            message: message,
            data: [
                "name": recipe.name,
                "canMake": canMake,
                "missingCount": missing.count,
                "missing": missingList
            ]
        )
    }

    private func recipeDelete(_ call: FunctionCall) -> FunctionResult {
        guard let name = call.string("name") else {
            return .error(id: call.id, name: call.name, message: "Missing recipe name")
        }

        guard let recipe = Recipe.find(named: name, in: modelContext) else {
            return .error(id: call.id, name: call.name, message: "Recipe '\(name)' not found")
        }

        let recipeName = recipe.name
        modelContext.delete(recipe)

        return .success(
            id: call.id,
            name: call.name,
            message: "Deleted recipe '\(recipeName)'"
        )
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
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        // Connection opened
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            self.isConnected = false
            self.isStreamingResponse = false
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
            return "Gemini API key not configured. Add GEMINI_API_KEY to Info.plist or environment."
        case .invalidURL:
            return "Invalid API URL"
        case .connectionFailed:
            return "Failed to connect to Gemini"
        }
    }
}
