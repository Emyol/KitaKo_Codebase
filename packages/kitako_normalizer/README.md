# kitako_normalizer

Taglish text normalizer for the KitaKo image retrieval system. Handles Filipino/Tagalog/English code-switching, abbreviations, and text speak commonly used in Philippine social media and messaging.

## Features

- **Abbreviation expansion**: Converts text speak to full words
  - `aq` → `ako`, `kc` → `kasi`, `lng` → `lang`
  - `d2` → `dito`, `bk8` → `bakit`, `gr8` → `great`

- **Code-switching handling**: Processes Taglish verb patterns
  - `nagshopping` → `shopping`
  - `nagcooking` → `cooking`

- **Reduplication preservation**: Keeps meaningful Filipino duplications
  - `araw-araw` → `araw araw` (daily)
  - `dahan-dahan` → `dahan dahan` (slowly)
  - `halo-halo` → `halo halo` (mixed dessert)

- **Character normalization**:
  - Collapses repeated characters (`hellooo` → `heloo`)
  - Handles punctuation spacing
  - Removes apostrophes, converts hyphens to spaces

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  kitako_normalizer:
    path: ../packages/kitako_normalizer
```

## Usage

### Basic Usage

```dart
import 'package:kitako_normalizer/kitako_normalizer.dart';

final normalizer = TaglishNormalizer();

// Normalize text speak
print(normalizer.normalize('gutom n aq kc d p aq kumain'));
// Output: "gutom na ako kasi hindi pa ako kumain"

// Handle Taglish verbs
print(normalizer.normalize('nagshopping aq sa mall'));
// Output: "shopping ako sa mall"

// Preserve reduplication
print(normalizer.normalize('lakad-lakad tayo'));
// Output: "lakad lakad tayo"
```

### Extension Method

```dart
import 'package:kitako_normalizer/kitako_normalizer.dart';

final normalized = 'kain tayo kc gutom n aq'.normalizeTaglish();
print(normalized); // "kain tayo kasi gutom na ako"
```

### Tokenizer Utilities

```dart
import 'package:kitako_normalizer/kitako_normalizer.dart';

final tokens = tokenize('hello world');
print(tokens); // ['hello', 'world']

print(isPunctuation('!')); // true
print(removePunctuation(['hello', '!', 'world'])); // ['hello', 'world']
```

## Dictionary Coverage

The normalizer includes mappings for:

- **Tagalog function words**: pronouns, particles, conjunctions
- **Common Tagalog content words**: frequently used nouns, adjectives
- **Action verbs**: image-visible activities
- **English shorthand**: common internet abbreviations
- **Numeric substitutions**: leetspeak-style replacements

## Allowed Reduplication

The following reduplicated forms are preserved (not deduplicated):

| Tagalog | English |
|---------|---------|
| araw araw | daily |
| gabi gabi | every night |
| dahan dahan | slowly |
| halo halo | mixed (dessert) |
| sari sari | variety store |
| isa isa | one by one |
| sunod sunod | consecutive |

## Integration with KitaKo

This normalizer is used in the retrieval pipeline:

```
User Query → TaglishNormalizer → EmbeddingService → ANN Search
```

It ensures queries are standardized before embedding generation, improving search accuracy for Taglish text.

## License

MIT License
