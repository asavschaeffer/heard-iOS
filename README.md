# Heard, Chef

A voice-first iOS cooking assistant that helps you manage your kitchen inventory and recipes using natural conversation. Built with SwiftUI, SwiftData, and Google's Gemini 2.0 Flash Live API.

> **"Heard, chef!"** - The classic kitchen acknowledgment, now powering your personal sous chef.

## Features

### Voice Assistant

- **Natural conversation** - Talk to your kitchen assistant like you would a real sous chef
- **Real-time voice streaming** - Bidirectional audio with Gemini 2.0 Flash Live API
- **Function calling** - Voice commands execute real actions (add ingredients, create recipes, etc.)
- **Visual feedback** - Animated waveform shows listening/speaking states

### Inventory Management

- **Track ingredients** - Name, quantity, unit, category, and storage location
- **Expiry tracking** - Visual indicators for expired and expiring-soon items
- **Smart organization** - Group by location (fridge, freezer, pantry, counter) or category
- **Quick add** - Common ingredients with pre-filled categories
- **Photo scanning** - Capture receipts or groceries to bulk-add items (via Gemini Vision)

### Recipe Management

- **Full recipe storage** - Ingredients, steps, prep/cook time, servings, tags
- **"What can I make?"** - Filter recipes by what you have in inventory
- **Ingredient matching** - See which recipes you can make and what's missing
- **Cooking mode** - Distraction-free step-by-step view for while you cook
- **AI-drafted recipes** - Ask the voice assistant to create recipes for you

## Requirements

- **Xcode 15.0+**
- **iOS 17.0+**
- **Google Gemini API key** (for voice features)

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/yourusername/heard-chef.git
cd heard-chef
```

### 2. Create the Xcode project

Since this repository contains Swift source files only (no `.xcodeproj`), you'll need to create the Xcode project:

1. Open Xcode → File → New → Project
2. Select **iOS → App**
3. Configure:
   - Product Name: `HeardChef`
   - Organization Identifier: `com.yourname`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **SwiftData**
4. Save the project in this repository folder
5. Delete the auto-generated `ContentView.swift` and `HeardChefApp.swift`
6. Add all files from `HeardChef/` folder to the project:
   - Right-click project → Add Files to "HeardChef"
   - Select all `.swift` files, ensure "Copy items if needed" is unchecked
   - Ensure "Create groups" is selected

### 3. Configure the Gemini API key

Get your API key from [Google AI Studio](https://aistudio.google.com/app/apikey).

**Option A: Info.plist (Recommended for development)**

Add to your `Info.plist`:

```xml
<key>GEMINI_API_KEY</key>
<string>your-api-key-here</string>
```

**Option B: Environment variable**

In Xcode: Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables

- Name: `GEMINI_API_KEY`
- Value: `your-api-key-here`

**Option C: Xcode build configuration**

For better security, use `.xcconfig` files:

1. Create `Secrets.xcconfig`:
   ```
   GEMINI_API_KEY = your-api-key-here
   ```
2. Add to `.gitignore`:
   ```
   Secrets.xcconfig
   ```
3. Reference in Info.plist:
   ```xml
   <key>GEMINI_API_KEY</key>
   <string>$(GEMINI_API_KEY)</string>
   ```

### 4. Configure permissions

Add to `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Heard, Chef needs microphone access to listen to your voice commands.</string>

<key>NSCameraUsageDescription</key>
<string>Heard, Chef uses the camera to scan receipts and identify groceries.</string>
```

### 5. Build and run

Select your target device/simulator and press ⌘R.

## Project Structure

```
HeardChef/
├── HeardChefApp.swift              # App entry point, SwiftData container setup
│
├── Models/
│   ├── Ingredient.swift            # SwiftData model for inventory items
│   ├── Recipe.swift                # SwiftData model for recipes
│   └── GeminiTools.swift           # Function declarations for Gemini API
│
├── Views/
│   ├── MainTabView.swift           # Root tab navigation
│   │
│   ├── Voice/
│   │   ├── VoiceView.swift         # Main voice interface UI
│   │   └── VoiceViewModel.swift    # Audio capture, Gemini connection logic
│   │
│   ├── Inventory/
│   │   ├── InventoryView.swift     # Inventory list with grouping/search
│   │   └── AddInventoryView.swift  # Manual ingredient entry form
│   │
│   └── Recipes/
│       ├── RecipesView.swift       # Recipe list with availability filtering
│       ├── RecipeDetailView.swift  # Full recipe view + cooking mode
│       └── RecipeEditView.swift    # Create/edit recipe form
│
├── Services/
│   ├── GeminiService.swift         # Gemini Live API WebSocket client
│   └── CameraService.swift         # AVFoundation camera capture
│
└── Resources/
    └── Assets.xcassets             # (Add via Xcode)
```

## Architecture

### Data Layer

**SwiftData** handles all local persistence:

- `Ingredient` - Kitchen inventory items with quantity, unit, category, location, expiry
- `Recipe` - Recipes with ingredients (stored as JSON), steps, timing, tags

Data is stored locally in SQLite (via SwiftData). No cloud sync in current version.

### Voice Layer

**Gemini 2.0 Flash Live API** provides:

- Bidirectional WebSocket streaming for real-time voice conversation
- Audio input: PCM 16-bit, 16kHz from device microphone
- Audio output: PCM audio streamed back for text-to-speech
- Function calling: Gemini can invoke local CRUD operations mid-conversation

### Function Calling

The voice assistant can execute these functions:

| Function           | Description                               |
| ------------------ | ----------------------------------------- |
| `inventory_add`    | Add ingredient to inventory               |
| `inventory_remove` | Remove or reduce ingredient quantity      |
| `inventory_update` | Update ingredient properties              |
| `inventory_list`   | List ingredients (optional filter)        |
| `inventory_search` | Search ingredients by name                |
| `inventory_check`  | Check if specific ingredient exists       |
| `recipe_create`    | Create a new recipe                       |
| `recipe_update`    | Update existing recipe                    |
| `recipe_delete`    | Delete a recipe                           |
| `recipe_list`      | List recipes (optional tag filter)        |
| `recipe_search`    | Search recipes by name/ingredient         |
| `recipe_suggest`   | Get recipe suggestions based on inventory |
| `parse_receipt`    | Extract items from receipt photo          |
| `parse_groceries`  | Identify items in grocery photo           |

### UI Layer

**SwiftUI** with iOS 17+ features:

- `@Observable` / `@StateObject` for view models
- `@Query` for reactive SwiftData fetches
- `@Bindable` for two-way model binding
- Native components: `NavigationStack`, `TabView`, `Form`, `List`

## Usage

### Voice Commands

Tap the microphone button and speak naturally:

> "Add two pounds of chicken to the fridge"

> "Do I have any eggs?"

> "What can I make for dinner?"

> "Create a recipe for pasta carbonara"

> "Remove the milk, it's expired"

> "What's in my pantry?"

The assistant will acknowledge with "Heard, chef!" and execute the action.

### Manual Entry

1. Go to **Inventory** tab
2. Tap **+** to add ingredients manually
3. Use **Quick Add** buttons for common items
4. Tap any ingredient to edit details

### Recipe Management

1. Go to **Recipes** tab
2. Tap **+** to create a recipe
3. Add ingredients and steps
4. Use tags for organization
5. Toggle **"Can Make"** to filter by available ingredients

### Cooking Mode

1. Open any recipe
2. Tap the **play button** in the toolbar
3. Navigate steps with left/right arrows
4. Progress dots show your position

## Gemini API Notes

### Live API

This app uses the **Gemini 2.0 Flash Live API** (experimental) for real-time voice conversation. This is different from the standard REST API:

- WebSocket connection at `wss://generativelanguage.googleapis.com/ws/...`
- Bidirectional streaming (audio in, audio + function calls out)
- Session-based with setup message containing system prompt and tools

### Audio Format

- **Input**: PCM 16-bit signed integer, 16kHz, mono
- **Output**: PCM audio (same format) for playback

### Rate Limits

Check [Google AI Studio](https://aistudio.google.com/) for current rate limits. The Live API may have different limits than the standard API.

## Customization

### Voice

Change the assistant's voice in `GeminiService.swift`:

```swift
"voice_name": "Aoede"  // Options: Aoede, Charon, Fenrir, Kore, Puck
```

### Categories & Locations

Modify enums in `Ingredient.swift`:

```swift
enum IngredientCategory: String, Codable, CaseIterable {
    case produce, dairy, meat, seafood, pantry, frozen, condiments, beverages, other
}

enum StorageLocation: String, Codable, CaseIterable {
    case fridge, freezer, pantry, counter
}
```

### System Prompt

Customize the assistant's personality in `GeminiService.swift`:

```swift
private var systemPrompt: String {
    """
    You are a helpful cooking assistant...
    """
}
```

## Known Limitations

- **No cloud sync** - Data is local only
- **Live API experimental** - Gemini Live API may change
- **iOS only** - No macOS/watchOS support
- **English only** - No localization yet
- **No offline mode** - Voice features require internet

## Future Ideas

- [ ] Cloud sync with iCloud or Supabase
- [ ] Meal planning calendar
- [ ] Shopping list generation
- [ ] Nutritional information
- [ ] Recipe import from URLs
- [ ] Apple Watch companion (timer controls)
- [ ] Siri Shortcuts integration
- [ ] Widget for expiring ingredients

## Troubleshooting

### "Gemini API key not configured"

Ensure your API key is set in Info.plist or environment variables. See [Setup](#3-configure-the-gemini-api-key).

### Voice not working

1. Check microphone permissions in Settings → HeardChef
2. Ensure internet connection
3. Verify API key is valid at [Google AI Studio](https://aistudio.google.com/)

### Camera not showing

Check camera permissions in Settings → HeardChef → Camera.

### SwiftData errors

Try deleting the app and reinstalling to reset the database.

## License

This project is licensed under the **GNU Affero General Public License v3 (AGPL-3.0) with Commons Clause**.

- **Commercial use is prohibited** - See Commons Clause restriction
- **Derivative works must be open-source** - Any modifications must be shared under AGPL-3.0
- **Network provision** - If used as a service, source code must be made available to users

See [LICENSE](LICENSE) for full details.

## Acknowledgments

- [Google Gemini API](https://ai.google.dev/) for the AI capabilities
- The phrase "Heard, chef!" from professional kitchen culture
