/// KitaKo Taglish Normalizer Package
///
/// Provides text normalization for Filipino/Tagalog/Taglish queries
/// in the KitaKo image retrieval system.
///
/// ## Features
///
/// - **Abbreviation expansion**: Converts text speak to full words
///   (e.g., "aq" → "ako", "kc" → "kasi")
/// - **Code-switching handling**: Processes Taglish patterns
///   (e.g., "nagshopping" → "shopping")
/// - **Reduplication preservation**: Keeps meaningful duplications
///   (e.g., "araw-araw", "dahan-dahan")
/// - **Character normalization**: Collapses repeated characters,
///   handles punctuation spacing
///
/// ## Usage
///
/// ```dart
/// import 'package:kitako_normalizer/kitako_normalizer.dart';
///
/// // Using the normalizer directly
/// final normalizer = TaglishNormalizer();
/// final result = normalizer.normalize('ngshopping aq sa mall!!');
/// print(result); // "shopping ako sa mall !"
///
/// // Using the extension method
/// final normalized = 'kain tayo kc gutom n aq'.normalizeTaglish();
/// print(normalized); // "kain tayo kasi gutom na ako"
/// ```
library kitako_normalizer;

export 'src/normalizer.dart';
export 'src/rules.dart';
export 'src/tokenizer.dart';
