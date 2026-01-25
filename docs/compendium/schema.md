# Compendium Schema

All entries are markdown files with YAML front matter for fast filtering.

Minimal required fields:

```
---
id: ingredient.tomato
type: ingredient
name: Tomato
aliases: [tomatoes]
---
```

Recommended fields by type:

Ingredient:
```
---
id: ingredient.tomato
type: ingredient
name: Tomato
aliases: [tomatoes, roma tomato, beefsteak tomato]
family: solanaceae
region: [americas, global]
season: [summer]
flavor_tags: [sweet, acidic, umami, fresh]
texture_tags: [juicy, fleshy]
techniques: [raw, saute, roast, braise]
pairings: [ingredient.garlic, ingredient.basil]
substitutions:
  best: [ingredient.red-bell-pepper]
  ok: [ingredient.canned-tomato, ingredient.tomato-paste]
  avoid: [ingredient.watermelon]
dietary: [vegan, vegetarian, gluten-free]
related: [ingredient.tomato-paste, ingredient.canned-tomato]
sources: [book.le-guide-culinaire]
---
```

Book:
```
---
id: book.le-guide-culinaire
type: book
name: Le Guide Culinaire
aliases: [Escoffier, Guide Culinaire]
authors: [Auguste Escoffier]
region: [france]
era: [early-20th-century]
themes: [classical-technique, sauces, brigade-system]
---
```

Technique:
```
---
id: technique.saute
type: technique
name: Saute
aliases: [sauteing]
heat_level: [medium-high]
fat_required: true
---
```

Interlinking:
- Use `compendium://<id>` inside body text for tool-friendly links.
- When human-readable links are useful, also include a relative markdown link.
