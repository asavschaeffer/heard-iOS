# Gemini Tools

This is the voice-optimized toolset used by the Gemini agent. The tools are verb-first, non-overlapping, and purpose-specific to reduce selection latency.

## Tool Set

### Inventory (6)
- `add_ingredient`
- `remove_ingredient`
- `update_ingredient`
- `get_ingredient`
- `list_ingredients`
- `search_ingredients`

### Recipes (6)
- `create_recipe`
- `update_recipe`
- `delete_recipe`
- `get_recipe` (full recipe with ingredients + steps)
- `list_recipes`
- `search_recipes`

### Cross-domain (2)
- `suggest_recipes`
- `check_recipe_availability`

## `update_ingredient` Patch Schema

`update_ingredient` uses a nested `patch` object so the intent is clear and fields are scoped to updates only.

```json
{
  "name": "update_ingredient",
  "description": "Update properties of an existing ingredient in inventory. Only include fields you want to change.",
  "parameters": {
    "type": "object",
    "properties": {
      "name": { "type": "string", "description": "Current name of the ingredient to update" },
      "patch": {
        "type": "object",
        "description": "Fields to update",
        "properties": {
          "name": { "type": "string", "description": "New name" },
          "quantity": { "type": "number", "description": "New quantity" },
          "unit": { "type": "string", "description": "Unit" },
          "expiryDate": { "type": "string", "description": "ISO-8601 date" },
          "location": { "type": "string", "description": "Storage location" },
          "category": { "type": "string", "description": "Category" },
          "notes": { "type": "string", "description": "Notes" }
        }
      }
    },
    "required": ["name", "patch"]
  }
}
```

## Notes on `get_recipe`

`get_recipe` always returns ingredients and steps together so the assistant can answer interleaved questions like "how much butter?" and "what's next?" without extra round-trips.

