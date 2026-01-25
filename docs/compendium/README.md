# Compendium Gastronomique

This folder is a culinary wiki designed to be hypersearchable by LLM tool calls.
Each concept lives in its own markdown file with strict front matter facets so
tools can filter and retrieve with high precision before reading long content.

Core rules:
- One file per concept: ingredient, technique, book, cuisine, recipe, glossary.
- Stable IDs like `ingredient.tomato` or `book.le-guide-culinaire`.
- Interlinks use the ID format `compendium://<id>` inside body text.
- Consistent section headings across entries for predictable extraction.

Suggested sections for ingredient entries:
- `## Flavor Profile`
- `## History`
- `## Rules`
- `## When to Break`
- `## Pairings`
- `## Substitutions`
- `## Notes`

Suggested sections for book entries:
- `## Overview`
- `## Themes`
- `## Best For`
- `## Notes`

See `schema.md` for canonical front matter and `index.json` for the facet index.
