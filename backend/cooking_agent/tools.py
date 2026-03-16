"""Heard Chef — Firestore-backed tool functions for the ADK agent.

Each tool reads/writes Firestore directly. The active user_id is set
per-request by the FastAPI endpoint before the agent runs.
"""

import asyncio
import re
import uuid
from datetime import datetime, timezone
from typing import Optional

from google.cloud import firestore

# ---------------------------------------------------------------------------
# Firestore client & user context
# ---------------------------------------------------------------------------

_db: Optional[firestore.AsyncClient] = None
_user_id: str = "default"


def _get_db() -> firestore.AsyncClient:
    global _db
    if _db is None:
        _db = firestore.AsyncClient()
    return _db


def set_user_id(uid: str) -> None:
    global _user_id
    _user_id = uid


def _ingredients_col():
    return _get_db().collection("users").document(_user_id).collection("ingredients")


def _recipes_col():
    return _get_db().collection("users").document(_user_id).collection("recipes")


# ---------------------------------------------------------------------------
# Normalization helpers (mirrors Swift Ingredient.normalize)
# ---------------------------------------------------------------------------

_STEM_SUFFIXES = ("ies", "es", "s")


def _normalize(name: str) -> str:
    """Lowercase, strip, and simple stem (matches iOS normalizedName logic)."""
    n = name.strip().lower()
    n = re.sub(r"\s+", " ", n)
    for suffix in _STEM_SUFFIXES:
        if len(n) > len(suffix) + 1 and n.endswith(suffix):
            if suffix == "ies":
                n = n[: -len(suffix)] + "y"
            else:
                n = n[: -len(suffix)]
            break
    return n


def _display_quantity(qty: float, unit: str) -> str:
    if qty == int(qty):
        return f"{int(qty)} {unit}"
    return f"{qty:.2g} {unit}"


# ---------------------------------------------------------------------------
# Async Firestore helpers
# ---------------------------------------------------------------------------

async def _find_ingredient_by_name(name: str):
    """Find a single ingredient doc by normalized name."""
    norm = _normalize(name)
    col = _ingredients_col()
    query = col.where("normalizedName", "==", norm).limit(1)
    docs = [doc async for doc in query.stream()]
    return docs[0] if docs else None


async def _find_recipe_by_name(name: str):
    """Find a single recipe doc by normalized name."""
    norm = _normalize(name)
    col = _recipes_col()
    query = col.where("normalizedName", "==", norm).limit(1)
    docs = [doc async for doc in query.stream()]
    return docs[0] if docs else None


async def _list_all_ingredients() -> list[dict]:
    """Return all ingredient dicts for the current user."""
    col = _ingredients_col()
    return [
        {"id": doc.id, **doc.to_dict()} async for doc in col.stream()
    ]


async def _list_all_recipes() -> list[dict]:
    """Return all recipe dicts for the current user."""
    col = _recipes_col()
    return [
        {"id": doc.id, **doc.to_dict()} async for doc in col.stream()
    ]


# ---------------------------------------------------------------------------
# Tool declarations JSON (for the voice relay setup message)
# ---------------------------------------------------------------------------

# Valid enum values (mirrors Swift enum allValidStrings)
UNITS = [
    "g", "kg", "oz", "lb", "ml", "l", "tsp", "tbsp", "cup", "fl_oz",
    "pinch", "dash", "piece", "whole", "slice", "clove", "bunch", "sprig",
    "can", "bottle", "jar", "bag", "box", "packet", "handful", "splash",
    "some", "to_taste",
]

CATEGORIES = [
    "produce", "protein", "dairy", "grain", "spice", "oil_vinegar",
    "sauce_condiment", "baking", "canned", "frozen", "beverage", "other",
]

LOCATIONS = ["fridge", "freezer", "pantry", "counter"]

DIFFICULTIES = ["easy", "medium", "hard"]

TOOL_DECLARATIONS_JSON = [
    {
        "name": "add_ingredient",
        "description": "Add an ingredient to the pantry. Merges quantity if one with the same name already exists (matched case-insensitively, singular/plural).",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Ingredient name"},
                "quantity": {"type": "number", "description": "Amount (> 0)"},
                "unit": {"type": "string", "description": "Unit", "enum": UNITS},
                "category": {"type": "string", "description": "Category", "enum": CATEGORIES},
                "location": {"type": "string", "description": "Location", "enum": LOCATIONS},
                "expiryDate": {"type": "string", "description": "YYYY-MM-DD (Optional)"},
                "notes": {"type": "string", "description": "Notes (Optional)"},
            },
            "required": ["name", "quantity", "unit"],
        },
    },
    {
        "name": "remove_ingredient",
        "description": "Remove an ingredient from the pantry, or reduce its quantity. Omit quantity to remove entirely.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Name to remove"},
                "quantity": {"type": "number", "description": "Amount to remove. Omit to remove all."},
            },
            "required": ["name"],
        },
    },
    {
        "name": "update_ingredient",
        "description": "Update properties of an existing pantry ingredient. Only include fields to change.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Current name"},
                "patch": {
                    "type": "object",
                    "description": "Fields to update",
                    "properties": {
                        "name": {"type": "string", "description": "New name"},
                        "quantity": {"type": "number", "description": "New quantity"},
                        "unit": {"type": "string", "description": "New unit", "enum": UNITS},
                        "category": {"type": "string", "description": "New category", "enum": CATEGORIES},
                        "location": {"type": "string", "description": "New location", "enum": LOCATIONS},
                        "expiryDate": {"type": "string", "description": "New expiry (YYYY-MM-DD)"},
                        "notes": {"type": "string", "description": "New notes"},
                    },
                },
            },
            "required": ["name", "patch"],
        },
    },
    {
        "name": "list_ingredients",
        "description": "List all pantry ingredients, optionally filtered by category or location.",
        "parameters": {
            "type": "object",
            "properties": {
                "category": {"type": "string", "description": "Filter category", "enum": CATEGORIES},
                "location": {"type": "string", "description": "Filter location", "enum": LOCATIONS},
            },
            "required": [],
        },
    },
    {
        "name": "search_ingredients",
        "description": "Search pantry ingredients by name (partial match).",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search term"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "get_ingredient",
        "description": "Get full details of a single pantry ingredient by name.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Name to check"},
            },
            "required": ["name"],
        },
    },
    {
        "name": "create_recipe",
        "description": "Create a new recipe. Ingredient names are matched to pantry inventory by normalized name.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Recipe name"},
                "description": {"type": "string", "description": "Brief description of the dish"},
                "notes": {"type": "string", "description": "Freeform notes: variations, tips, pairings, substitutions"},
                "cookingTemperature": {"type": "string", "description": "Cooking temperature, e.g. 350F, 180C, medium-high"},
                "ingredients": {
                    "type": "array",
                    "description": "List of ingredients",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string", "description": "Ingredient name"},
                            "quantity": {"type": "number", "description": "Amount needed"},
                            "unit": {"type": "string", "description": "Unit", "enum": UNITS},
                            "preparation": {"type": "string", "description": "How to prepare, e.g. diced, minced"},
                        },
                        "required": ["name"],
                    },
                },
                "steps": {
                    "type": "array",
                    "description": "Cooking steps in order",
                    "items": {
                        "type": "object",
                        "properties": {
                            "instruction": {"type": "string", "description": "What to do"},
                            "durationMinutes": {"type": "number", "description": "Timer for this step"},
                        },
                        "required": ["instruction"],
                    },
                },
                "prepTime": {"type": "number", "description": "Prep time in minutes"},
                "cookTime": {"type": "number", "description": "Cook time in minutes"},
                "servings": {"type": "number", "description": "Number of servings"},
                "difficulty": {"type": "string", "description": "Difficulty", "enum": DIFFICULTIES},
                "tags": {"type": "array", "description": "Lowercase tags", "items": {"type": "string"}},
            },
            "required": ["name", "ingredients", "steps"],
        },
    },
    {
        "name": "update_recipe",
        "description": "Update an existing recipe. Only provide fields to change. Ingredients and steps replace the full list when provided.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Name of recipe to update"},
                "newName": {"type": "string", "description": "New name"},
                "description": {"type": "string", "description": "New description"},
                "notes": {"type": "string", "description": "New notes. Use empty string to clear."},
                "cookingTemperature": {"type": "string", "description": "New cooking temperature. Use empty string to clear."},
                "ingredients": {
                    "type": "array",
                    "description": "New ingredients (replaces full list)",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string", "description": "Ingredient name"},
                            "quantity": {"type": "number", "description": "Amount needed"},
                            "unit": {"type": "string", "description": "Unit", "enum": UNITS},
                            "preparation": {"type": "string", "description": "How to prepare"},
                        },
                        "required": ["name"],
                    },
                },
                "steps": {
                    "type": "array",
                    "description": "New steps (replaces full list)",
                    "items": {
                        "type": "object",
                        "properties": {
                            "instruction": {"type": "string", "description": "What to do"},
                            "durationMinutes": {"type": "number", "description": "Timer for this step"},
                        },
                        "required": ["instruction"],
                    },
                },
                "prepTime": {"type": "number", "description": "New prep time in minutes"},
                "cookTime": {"type": "number", "description": "New cook time in minutes"},
                "servings": {"type": "number", "description": "New servings"},
                "difficulty": {"type": "string", "description": "New difficulty", "enum": DIFFICULTIES},
                "tags": {"type": "array", "description": "New lowercase tags", "items": {"type": "string"}},
            },
            "required": ["name"],
        },
    },
    {
        "name": "delete_recipe",
        "description": "Permanently delete a recipe by name.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Name to delete"},
            },
            "required": ["name"],
        },
    },
    {
        "name": "get_recipe",
        "description": "Get full recipe details including ingredients, steps, and notes.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Exact recipe name"},
            },
            "required": ["name"],
        },
    },
    {
        "name": "list_recipes",
        "description": "List all saved recipes (name, tags, total time). Optionally filter by tag.",
        "parameters": {
            "type": "object",
            "properties": {
                "tag": {"type": "string", "description": "Filter by tag"},
            },
            "required": [],
        },
    },
    {
        "name": "search_recipes",
        "description": "Search recipes by name or tag (partial match).",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search term"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "suggest_recipes",
        "description": "Suggest recipes that can be made with current pantry inventory, ranked by ingredient match.",
        "parameters": {
            "type": "object",
            "properties": {
                "maxMissingIngredients": {"type": "number", "description": "Max missing (default 3)"},
                "onlyFullyMakeable": {"type": "boolean", "description": "Only complete matches"},
            },
            "required": [],
        },
    },
    {
        "name": "check_recipe_availability",
        "description": "Check if a recipe can be made with current inventory, and list missing items.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Exact recipe name"},
            },
            "required": ["name"],
        },
    },
]


# ---------------------------------------------------------------------------
# Tool dispatch (for voice relay function call handling)
# ---------------------------------------------------------------------------

_TOOL_MAP: dict = {}  # populated at module end


async def execute_tool(name: str, args: dict) -> dict:
    """Execute a tool by name. Returns the result dict."""
    fn = _TOOL_MAP.get(name)
    if fn is None:
        return {"success": False, "error": f"Unknown function: {name}"}
    try:
        return await fn(**args)
    except Exception as e:
        return {"success": False, "error": str(e)}


# ===================================================================
# INVENTORY TOOLS
# ===================================================================


async def add_ingredient(
    name: str,
    quantity: float,
    unit: str,
    category: str = "other",
    location: str = "pantry",
    expiryDate: str | None = None,
    notes: str | None = None,
) -> dict:
    """Add an ingredient to the pantry. Merges quantity if already exists."""
    norm = _normalize(name)
    doc_snap = await _find_ingredient_by_name(name)

    now = datetime.now(timezone.utc)

    if doc_snap is not None:
        # Merge quantity
        data = doc_snap.to_dict()
        new_qty = data.get("quantity", 0) + quantity
        await _ingredients_col().document(doc_snap.id).update({
            "quantity": new_qty,
            "updatedAt": now,
        })
        return {
            "success": True,
            "message": f"Updated {name} - now have {_display_quantity(new_qty, data.get('unit', unit))} in the {data.get('location', location)}",
            "wasCreated": False,
            "ingredient": {
                "name": data.get("name", name),
                "quantity": new_qty,
                "unit": data.get("unit", unit),
                "location": data.get("location", location),
            },
        }

    # Create new
    doc_id = str(uuid.uuid4())
    doc_data = {
        "name": name,
        "normalizedName": norm,
        "quantity": quantity,
        "unit": unit,
        "category": category,
        "location": location,
        "notes": notes,
        "createdAt": now,
        "updatedAt": now,
    }
    if expiryDate:
        doc_data["expiryDate"] = expiryDate

    await _ingredients_col().document(doc_id).set(doc_data)

    return {
        "success": True,
        "message": f"Added {_display_quantity(quantity, unit)} of {name} to the {location}",
        "wasCreated": True,
        "ingredient": {"name": name, "quantity": quantity, "unit": unit, "location": location},
    }


async def remove_ingredient(
    name: str,
    quantity: float | None = None,
) -> dict:
    """Remove an ingredient or reduce its quantity."""
    doc_snap = await _find_ingredient_by_name(name)
    if doc_snap is None:
        return {"success": False, "error": f"'{name}' not found in inventory"}

    data = doc_snap.to_dict()
    ref = _ingredients_col().document(doc_snap.id)

    if quantity is not None:
        new_qty = data.get("quantity", 0) - quantity
        if new_qty <= 0:
            await ref.delete()
            return {"success": True, "message": f"Removed all {data['name']} from inventory"}

        await ref.update({"quantity": new_qty, "updatedAt": datetime.now(timezone.utc)})
        return {
            "success": True,
            "message": f"Removed {quantity} {data.get('unit', '')} of {data['name']}. {_display_quantity(new_qty, data.get('unit', ''))} remaining.",
            "remaining": new_qty,
        }

    ingredient_name = data["name"]
    await ref.delete()
    return {"success": True, "message": f"Removed {ingredient_name} from inventory"}


async def update_ingredient(
    name: str,
    patch: dict,
) -> dict:
    """Update properties of an existing ingredient."""
    doc_snap = await _find_ingredient_by_name(name)
    if doc_snap is None:
        return {"success": False, "error": f"'{name}' not found in inventory"}

    if not patch:
        return {"success": False, "error": "No changes specified"}

    updates: dict = {"updatedAt": datetime.now(timezone.utc)}

    if "name" in patch:
        updates["name"] = patch["name"]
        updates["normalizedName"] = _normalize(patch["name"])
    for field in ("quantity", "unit", "category", "location", "expiryDate", "notes"):
        if field in patch:
            updates[field] = patch[field]

    ref = _ingredients_col().document(doc_snap.id)
    await ref.update(updates)

    updated = {**doc_snap.to_dict(), **updates}
    return {
        "success": True,
        "message": f"Updated {updated.get('name', name)}",
        "ingredient": {
            "name": updated.get("name", name),
            "quantity": updated.get("quantity"),
            "unit": updated.get("unit"),
            "location": updated.get("location"),
        },
    }


async def list_ingredients(
    category: str | None = None,
    location: str | None = None,
) -> dict:
    """List all pantry ingredients, optionally filtered."""
    col = _ingredients_col()
    query = col

    if category:
        query = query.where("category", "==", category)
    if location:
        query = query.where("location", "==", location)

    docs = [doc.to_dict() async for doc in query.stream()]

    if not docs:
        parts = ["No ingredients"]
        if category:
            parts.append(f"in {category}")
        if location:
            parts.append(f"in the {location}")
        return {"success": True, "message": " ".join(parts), "count": 0, "items": []}

    items = [f"{d['name']}: {_display_quantity(d.get('quantity', 0), d.get('unit', ''))}" for d in docs]
    msg_parts = [f"{len(docs)} item{'s' if len(docs) != 1 else ''}"]
    if location:
        msg_parts.append(f"in the {location}")
    if category:
        msg_parts.append(f"({category})")

    return {"success": True, "message": " ".join(msg_parts), "count": len(docs), "items": items}


async def search_ingredients(query: str) -> dict:
    """Search ingredients by name (partial match via normalized prefix)."""
    all_ings = await _list_all_ingredients()
    q_lower = query.lower()
    results = [d for d in all_ings if q_lower in d.get("normalizedName", "").lower() or q_lower in d.get("name", "").lower()]

    if not results:
        return {"success": True, "message": f"No ingredients matching '{query}'", "count": 0, "results": []}

    items = [{"name": d["name"], "quantity": _display_quantity(d.get("quantity", 0), d.get("unit", "")), "location": d.get("location", "")} for d in results]
    return {
        "success": True,
        "message": f"Found {len(results)} matching ingredient{'s' if len(results) != 1 else ''}",
        "count": len(results),
        "results": items,
    }


async def get_ingredient(name: str) -> dict:
    """Get full details of a single ingredient."""
    doc_snap = await _find_ingredient_by_name(name)
    if doc_snap is None:
        return {"success": True, "message": f"No '{name}' in inventory", "found": False}

    d = doc_snap.to_dict()
    qty_str = _display_quantity(d.get("quantity", 0), d.get("unit", ""))

    data = {
        "success": True,
        "found": True,
        "name": d["name"],
        "quantity": d.get("quantity"),
        "unit": d.get("unit"),
        "displayQuantity": qty_str,
        "location": d.get("location", ""),
        "category": d.get("category", ""),
    }

    expiry = d.get("expiryDate")
    if expiry:
        data["expiryDate"] = expiry

    return {**data, "message": f"You have {qty_str} of {d['name']} in the {d.get('location', 'pantry')}"}


# ===================================================================
# RECIPE TOOLS
# ===================================================================


async def create_recipe(
    name: str,
    ingredients: list[dict],
    steps: list[dict],
    description: str | None = None,
    notes: str | None = None,
    cookingTemperature: str | None = None,
    prepTime: int | None = None,
    cookTime: int | None = None,
    servings: int | None = None,
    difficulty: str = "medium",
    tags: list[str] | None = None,
) -> dict:
    """Create a new recipe."""
    existing = await _find_recipe_by_name(name)
    if existing is not None:
        return {"success": False, "error": f"A recipe named '{name}' already exists"}

    if not ingredients:
        return {"success": False, "error": "No valid ingredients provided"}
    if not steps:
        return {"success": False, "error": "No valid steps provided"}

    # Normalize ingredients
    recipe_ingredients = []
    for ing in ingredients:
        if isinstance(ing, str):
            recipe_ingredients.append({"name": ing, "normalizedName": _normalize(ing)})
            continue
        ri = {"name": ing.get("name", ""), "normalizedName": _normalize(ing.get("name", ""))}
        if "quantity" in ing:
            ri["quantity"] = ing["quantity"]
        if "unit" in ing:
            ri["unit"] = ing["unit"]
        if "preparation" in ing:
            ri["preparation"] = ing["preparation"]
        recipe_ingredients.append(ri)

    # Normalize steps
    recipe_steps = []
    for i, step in enumerate(steps):
        if isinstance(step, str):
            recipe_steps.append({"instruction": step, "orderIndex": i})
            continue
        rs = {"instruction": step.get("instruction", ""), "orderIndex": i}
        if "durationMinutes" in step:
            rs["durationMinutes"] = step["durationMinutes"]
        recipe_steps.append(rs)

    now = datetime.now(timezone.utc)
    doc_id = str(uuid.uuid4())
    doc_data = {
        "name": name,
        "normalizedName": _normalize(name),
        "description": description,
        "notes": notes,
        "cookingTemperature": cookingTemperature,
        "ingredients": recipe_ingredients,
        "steps": recipe_steps,
        "prepTime": prepTime,
        "cookTime": cookTime,
        "servings": servings,
        "difficulty": difficulty,
        "tags": tags or [],
        "source": "ai_drafted",
        "createdAt": now,
        "updatedAt": now,
    }

    await _recipes_col().document(doc_id).set(doc_data)

    return {
        "success": True,
        "message": f"Created recipe '{name}' with {len(recipe_ingredients)} ingredients and {len(recipe_steps)} steps",
        "name": name,
        "ingredientCount": len(recipe_ingredients),
        "stepCount": len(recipe_steps),
    }


async def update_recipe(
    name: str,
    newName: str | None = None,
    description: str | None = None,
    notes: str | None = None,
    cookingTemperature: str | None = None,
    ingredients: list[dict] | None = None,
    steps: list[dict] | None = None,
    prepTime: int | None = None,
    cookTime: int | None = None,
    servings: int | None = None,
    difficulty: str | None = None,
    tags: list[str] | None = None,
) -> dict:
    """Update an existing recipe."""
    doc_snap = await _find_recipe_by_name(name)
    if doc_snap is None:
        return {"success": False, "error": f"Recipe '{name}' not found"}

    updates: dict = {"updatedAt": datetime.now(timezone.utc)}
    changed_fields = []

    if newName is not None:
        updates["name"] = newName
        updates["normalizedName"] = _normalize(newName)
        changed_fields.append("name")
    if description is not None:
        updates["description"] = description
        changed_fields.append("description")
    if notes is not None:
        updates["notes"] = notes if notes else None
        changed_fields.append("notes")
    if cookingTemperature is not None:
        updates["cookingTemperature"] = cookingTemperature if cookingTemperature else None
        changed_fields.append("cookingTemperature")
    if prepTime is not None:
        updates["prepTime"] = prepTime
        changed_fields.append("prepTime")
    if cookTime is not None:
        updates["cookTime"] = cookTime
        changed_fields.append("cookTime")
    if servings is not None:
        updates["servings"] = servings
        changed_fields.append("servings")
    if difficulty is not None:
        updates["difficulty"] = difficulty
        changed_fields.append("difficulty")
    if tags is not None:
        updates["tags"] = tags
        changed_fields.append("tags")

    if ingredients is not None:
        recipe_ingredients = []
        for ing in ingredients:
            ri = {"name": ing.get("name", ""), "normalizedName": _normalize(ing.get("name", ""))}
            if "quantity" in ing:
                ri["quantity"] = ing["quantity"]
            if "unit" in ing:
                ri["unit"] = ing["unit"]
            if "preparation" in ing:
                ri["preparation"] = ing["preparation"]
            recipe_ingredients.append(ri)
        updates["ingredients"] = recipe_ingredients
        changed_fields.append("ingredients")

    if steps is not None:
        recipe_steps = []
        for i, step in enumerate(steps):
            if isinstance(step, str):
                recipe_steps.append({"instruction": step, "orderIndex": i})
            else:
                rs = {"instruction": step.get("instruction", ""), "orderIndex": i}
                if "durationMinutes" in step:
                    rs["durationMinutes"] = step["durationMinutes"]
                recipe_steps.append(rs)
        updates["steps"] = recipe_steps
        changed_fields.append("steps")

    ref = _recipes_col().document(doc_snap.id)
    await ref.update(updates)

    final_name = updates.get("name", doc_snap.to_dict().get("name", name))
    return {
        "success": True,
        "message": f"Updated recipe '{final_name}'",
        "updatedFields": changed_fields,
    }


async def delete_recipe(name: str) -> dict:
    """Permanently delete a recipe."""
    doc_snap = await _find_recipe_by_name(name)
    if doc_snap is None:
        return {"success": False, "error": f"Recipe '{name}' not found"}

    recipe_name = doc_snap.to_dict().get("name", name)
    await _recipes_col().document(doc_snap.id).delete()
    return {"success": True, "message": f"Deleted recipe '{recipe_name}'"}


async def get_recipe(name: str) -> dict:
    """Get full recipe details."""
    doc_snap = await _find_recipe_by_name(name)
    if doc_snap is None:
        return {"success": False, "error": f"Recipe '{name}' not found"}

    r = doc_snap.to_dict()
    inventory = await _list_all_ingredients()
    inv_names = {_normalize(i.get("name", "")) for i in inventory}

    ingredients_list = []
    for ing in r.get("ingredients", []):
        item = {"name": ing["name"]}
        if "quantity" in ing and ing["quantity"] is not None:
            item["quantity"] = ing["quantity"]
        if "unit" in ing and ing["unit"] is not None:
            item["unit"] = ing["unit"]
        if "preparation" in ing:
            item["preparation"] = ing["preparation"]
        item["available"] = _normalize(ing.get("name", "")) in inv_names
        ingredients_list.append(item)

    steps_list = sorted(r.get("steps", []), key=lambda s: s.get("orderIndex", 0))
    missing = [i for i in ingredients_list if not i.get("available")]

    total_time = None
    pt = r.get("prepTime")
    ct = r.get("cookTime")
    if pt and ct:
        total_time = f"{pt + ct} min"
    elif pt:
        total_time = f"{pt} min prep"
    elif ct:
        total_time = f"{ct} min cook"

    return {
        "success": True,
        "message": f"Found recipe '{r['name']}'",
        "name": r["name"],
        "description": r.get("description", ""),
        "notes": r.get("notes", ""),
        "cookingTemperature": r.get("cookingTemperature", ""),
        "ingredients": ingredients_list,
        "steps": steps_list,
        "missingCount": len(missing),
        "canMake": len(missing) == 0,
        "totalTime": total_time or "Unknown",
        "difficulty": r.get("difficulty", "medium"),
        "tags": r.get("tags", []),
    }


async def list_recipes(tag: str | None = None) -> dict:
    """List all saved recipes."""
    all_recipes = await _list_all_recipes()

    if tag:
        all_recipes = [r for r in all_recipes if tag.lower() in [t.lower() for t in r.get("tags", [])]]

    if not all_recipes:
        msg = f"No recipes with tag '{tag}'" if tag else "No recipes saved yet"
        return {"success": True, "message": msg, "count": 0, "recipes": []}

    inventory = await _list_all_ingredients()
    inv_names = {_normalize(i.get("name", "")) for i in inventory}

    recipe_list = []
    for r in all_recipes:
        r_ings = r.get("ingredients", [])
        missing = [i for i in r_ings if _normalize(i.get("name", "")) not in inv_names]

        pt = r.get("prepTime")
        ct = r.get("cookTime")
        total = f"{(pt or 0) + (ct or 0)} min" if (pt or ct) else "Unknown"

        recipe_list.append({
            "name": r["name"],
            "description": r.get("description", ""),
            "cookingTemperature": r.get("cookingTemperature", ""),
            "canMake": len(missing) == 0,
            "missingCount": len(missing),
            "totalTime": total,
            "difficulty": r.get("difficulty", "medium"),
        })

    return {
        "success": True,
        "message": f"{len(all_recipes)} recipe{'s' if len(all_recipes) != 1 else ''} found",
        "count": len(all_recipes),
        "recipes": recipe_list,
    }


async def search_recipes(query: str) -> dict:
    """Search recipes by name or tag."""
    all_recipes = await _list_all_recipes()
    q = query.lower()

    results = [
        r for r in all_recipes
        if q in r.get("name", "").lower()
        or q in r.get("normalizedName", "").lower()
        or any(q in t.lower() for t in r.get("tags", []))
    ]

    if not results:
        return {"success": True, "message": f"No recipes matching '{query}'", "count": 0, "results": []}

    inventory = await _list_all_ingredients()
    inv_names = {_normalize(i.get("name", "")) for i in inventory}

    recipe_list = []
    for r in results:
        r_ings = r.get("ingredients", [])
        missing = [i for i in r_ings if _normalize(i.get("name", "")) not in inv_names]
        recipe_list.append({
            "name": r["name"],
            "canMake": len(missing) == 0,
            "missingCount": len(missing),
        })

    return {
        "success": True,
        "message": f"Found {len(results)} recipe{'s' if len(results) != 1 else ''} matching '{query}'",
        "count": len(results),
        "results": recipe_list,
    }


async def suggest_recipes(
    maxMissingIngredients: int = 3,
    onlyFullyMakeable: bool = False,
) -> dict:
    """Suggest recipes based on current inventory."""
    inventory = await _list_all_ingredients()
    if not inventory:
        return {
            "success": True,
            "message": "No ingredients in inventory. Add some ingredients first!",
            "count": 0,
            "suggestions": [],
        }

    inv_names = {_normalize(i.get("name", "")) for i in inventory}
    all_recipes = await _list_all_recipes()

    suggestions = []
    for r in all_recipes:
        r_ings = r.get("ingredients", [])
        if not r_ings:
            continue
        missing = [i for i in r_ings if _normalize(i.get("name", "")) not in inv_names]
        match_pct = (len(r_ings) - len(missing)) / len(r_ings) if r_ings else 0

        if len(missing) > maxMissingIngredients:
            continue
        if onlyFullyMakeable and missing:
            continue

        pt = r.get("prepTime")
        ct = r.get("cookTime")
        total = f"{(pt or 0) + (ct or 0)} min" if (pt or ct) else "Unknown"

        suggestions.append({
            "name": r["name"],
            "matchPercentage": int(match_pct * 100),
            "missingIngredients": [m.get("name", "") for m in missing],
            "totalTime": total,
        })

    # Sort by match percentage descending
    suggestions.sort(key=lambda s: s["matchPercentage"], reverse=True)

    fully_makeable = sum(1 for s in suggestions if not s["missingIngredients"])

    if not suggestions:
        msg = (
            "No recipes can be made with current inventory"
            if onlyFullyMakeable
            else f"No recipes found with {maxMissingIngredients} or fewer missing ingredients"
        )
        return {"success": True, "message": msg, "count": 0, "suggestions": []}

    return {
        "success": True,
        "message": f"{len(suggestions)} recipe{'s' if len(suggestions) != 1 else ''} available. {fully_makeable} can be made right now.",
        "count": len(suggestions),
        "fullyMakeable": fully_makeable,
        "suggestions": suggestions,
    }


async def check_recipe_availability(name: str) -> dict:
    """Check if a recipe can be made with current inventory."""
    doc_snap = await _find_recipe_by_name(name)
    if doc_snap is None:
        return {"success": False, "error": f"Recipe '{name}' not found"}

    r = doc_snap.to_dict()
    inventory = await _list_all_ingredients()
    inv_names = {_normalize(i.get("name", "")) for i in inventory}

    r_ings = r.get("ingredients", [])
    missing = [i for i in r_ings if _normalize(i.get("name", "")) not in inv_names]
    can_make = len(missing) == 0

    msg = (
        f"You can make '{r['name']}' with current inventory"
        if can_make
        else f"Missing {len(missing)} item{'s' if len(missing) != 1 else ''} for '{r['name']}'"
    )

    return {
        "success": True,
        "message": msg,
        "name": r["name"],
        "canMake": can_make,
        "missingCount": len(missing),
        "missing": [{"name": m.get("name", "")} for m in missing],
    }


# ---------------------------------------------------------------------------
# Register tool dispatch map
# ---------------------------------------------------------------------------

_TOOL_MAP = {
    "add_ingredient": add_ingredient,
    "remove_ingredient": remove_ingredient,
    "update_ingredient": update_ingredient,
    "list_ingredients": list_ingredients,
    "search_ingredients": search_ingredients,
    "get_ingredient": get_ingredient,
    "create_recipe": create_recipe,
    "update_recipe": update_recipe,
    "delete_recipe": delete_recipe,
    "get_recipe": get_recipe,
    "list_recipes": list_recipes,
    "search_recipes": search_recipes,
    "suggest_recipes": suggest_recipes,
    "check_recipe_availability": check_recipe_availability,
}
