# Lookup Helper

This doc describes how tools should retrieve compendium entries.

Strategy:
1) Search `index.json` by facets (type, name, aliases, tags).
2) Select matching `id` and resolve its `path`.
3) Read the markdown file and extract specific sections.
4) Use `compendium://<id>` links for related entries.

Example: Find tomato substitutions
- Query `index.json` for `ingredient` with name/alias matching "tomato".
- Read `docs/compendium/ingredients/tomato.md`.
- Use `## Substitutions` and optionally follow related links.

Example: Find books for classical technique
- Query `index.json` for `type=book` and themes containing
  `classical-technique` or `sauces`.
- Read the matching book entries for details.
