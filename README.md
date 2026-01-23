# Heard, Chef

![Status](https://img.shields.io/badge/status-in%20development-yellow)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![Xcode](https://img.shields.io/badge/xcode-15%2B-blue)

> **"Heard, chef!"** - this AI definitely will not say "you're absolutely right!"

<div align="center">
  <img src="assets/app-icon-template.png" alt="Heard, Chef" width="35%">
</div>

## Overview

"Heard, Chef" is a native iOS cooking assistant designed to leverage existing AI with long-term personalized memory. It combines an iMessage-style chat interface with a powerful, interruptible voice mode, allowing you to manage inventory, plan meals, and get real-time cooking feedback without washing your hands.

Under the hood, it is engineered for **model independence**, using a custom "Brain Protocol" that decouples the user experience from the underlying AI, ensuring the app remains fast, private, and adaptable.

## The Experience

### 💬 Conversational Core

The app is built around a familiar, **iMessage-esque chat interface**.

- **Natural Texting:** Text your chef just like a friend. "Do I have enough eggs for a quiche?" or "Remind me to buy basil."
- **Media Rich:** Snap photos directly in the chat flow to ask questions or log items.
- **Live Tool Chips:** Watch the AI "think" and work. When you ask to check the pantry, you'll see a background chip pop up: `Checking Inventory...` followed by `Found: 6 Eggs`.

### 🎙️ Live Voice Mode

Tap the microphone for a hands-free experience designed for active cooking. "How can I make sure this sauce won't break?", "What else could I add to this stir fry?"

- **The 40% Modal:** Voice mode slides up a non-intrusive sheet covering the bottom 40% of the screen.
- **Chef Avatar:** A dedicated, animated avatar provides visual feedback, reacting to your voice and the AI's processing state.
- **Background Context:** The chat window and tool chips remain visible behind the modal, so you can visually confirm that the AI successfully added "Paprika" to your list even while it keeps talking.

### 📷 Visual Intelligence

Use the camera to bridge the physical and digital kitchen.

- **Receipt Scanning:** Snap a photo of a grocery receipt. The AI parses the items, normalizes quantities (e.g., "2 lbs" instead of "bag"), and adds them to your inventory.
- **Cooking Feedback:** Unsure if your onions are caramelized enough? Snap a photo and ask, "Is this ready?" for instant visual analysis.

### Data Memory Layer

What sets this apart from Grok or ChatGPT voice mode is you don't have to orchestrate custom files storing your information

- **allergy information prompt injection** The LLM will always adjust recipes for your personal situation
- **find, save, edit, and share recipes** The recipebook can be referenced while shopping or cooking or sent between users
- **easy shopping list** never forget what you had already at home while youre at the store.

## Technical Architecture

This project is architected for longevity and flexibility, avoiding vendor lock-in through strict abstraction layers.

### 1. The "Brain" Protocol

The app does not communicate directly with any specific AI provider. Instead, it interacts with a strictly typed `ChefIntelligence` protocol.

- **Swappable Backend:** Allows the app to switch between **Gemini 2.0 Flash** (Cloud) for complex reasoning and potential future **Local Models** (e.g., Llama/Mistral via MLX) for offline privacy.
- **Audio Specs:** The pipeline handles **PCM 16-bit, 16kHz** audio for low-latency streaming.

### 2. Precision Context Management (Tool-First)

To minimize latency and costs, "Heard, Chef" uses **Active Tool Calling**. Instead of dumping your entire inventory into the prompt, the AI calls specific tools to retrieve data on demand.

**Available Tools:**

| Domain         | Function                      | Description                                 |
| -------------- | ----------------------------- | ------------------------------------------- |
| **Inventory**  | `add_ingredient`              | Add items with quantity normalization       |
|                | `remove_ingredient`           | Decrement stock or remove items             |
|                | `update_ingredient`           | Patch ingredient fields                     |
|                | `get_ingredient`              | Check details for one ingredient            |
|                | `list_ingredients`            | List items with optional filters            |
|                | `search_ingredients`          | Fuzzy name search                           |
| **Recipes**    | `create_recipe`               | Create a new recipe                         |
|                | `update_recipe`               | Update recipe fields                        |
|                | `delete_recipe`               | Remove a recipe                             |
|                | `get_recipe`                  | Full recipe with ingredients and steps      |
|                | `list_recipes`                | Browse recipes by tag                       |
|                | `search_recipes`              | Search by name or tag                       |
| **Cross-Tool** | `suggest_recipes`             | Recipes matching current inventory          |
|                | `check_recipe_availability`   | Missing list for a specific recipe          |

### 3. The "Fuzzy-to-Strict" Bridge

LLMs speak in approximations; databases need precision.

- **Ingestion:** User says "I bought a bunch of cilantro."
- **Normalization:** The engine maps "bunch" to a standard unit (e.g., `count: 1`) and categorizes it under `.produce`.
- **Persistence:** Only validated, strictly-typed data is saved to **SwiftData** (SQLite), ensuring sorting and filtering always work.

## Setup & Requirements

- **Xcode 15.0+**
- **iOS 17.0+**
- **API Key:** Google Gemini API Key (multimodal live access).

### 1. Clone & Project Creation

```bash
git clone https://github.com/yourusername/heard-chef.git
cd heard-chef

```

_Note: If the `.xcodeproj` file is not tracked, create a new iOS App in Xcode, select "SwiftData" for storage, and drag the `HeardChef/` folder into the project navigator._

### 2. API Key Configuration

This project uses `.xcconfig` files to secure secrets.

1. Create `Secrets.xcconfig` in the root directory.
2. Add your key:

```properties
GEMINI_API_KEY = your_actual_key_here

```

_(For Gemini Live, ensure you are using a key with access to the `gemini-2.0-flash-exp` model)_

### 3. Configuration & Customization

- **Voice Persona:** You can change the voice in `GeminiService.swift`. Supported voices include: `Aoede`, `Charon`, `Fenrir`, `Kore`, and `Puck`.
- **System Prompt:** Customize the chef's personality (e.g., "Gordon Ramsay mode" vs "Grandma mode") in `ChefIntelligence.swift`.

## Roadmap

- [x] **Phase 1: Foundation** - UX Prototypes, SwiftData Schema, "Brain Protocol" Definition.
- [ ] **Phase 2: Core Intelligence (in progress)** - Implement Gemini Live streaming and Tool Definitions.
- [ ] **Phase 3: Visual Polish** - Implement the Avatar animations and Modal transitions.
- [ ] **Phase 4: Local Fallback** - Integrate on-device model for offline inventory checks.

## Short-Term Todo

~~1. Data Models - Ingredient, Recipe (SwiftData schema, relationships, validation)~~
~~2. [Gemini Tools](docs/gemini-tools.md) - Function declarations (schema accuracy, error handling)~~
~~3. Gemini Service - WebSocket connection, audio streaming, function execution~~
4. Voice UI - Waveform, transcript, states, accessibility
5. Inventory UI - List, grouping, search, edit flow, expiry handling
6. Recipe UI - Cards, detail view, cooking mode, edit form
7. Camera - Capture flow, Gemini Vision integration, confirmation UI

## Specs

- `docs/gemini-tools.md` - Drill-down toolset and Gemini tool architecture


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

## License

**GNU Affero General Public License v3.0 with Commons Clause**

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

**Commons Clause**
The Software is provided to you by the Licensor under the License, as amended by the "Commons Clause". You may not sell the Software. "Selling" means practicing any or all of the rights granted to you under the License to provide to third parties, for a fee or other consideration (including without limitation fees for hosting or consulting/ support services related to the Software), a product or service whose value derives, entirely or substantially, from the functionality of the Software.

## Acknowledgments

- [Google Gemini API](https://ai.google.dev/) for the underlying intelligence.
- Chef Rah Shabazz - a maverick.
