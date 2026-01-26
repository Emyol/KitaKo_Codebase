/// KitaKo Error Types
///
/// Defines custom exceptions for the KitaKo packages.

/// Base exception for KitaKo errors
class KitakoException implements Exception {
  final String message;
  final dynamic cause;

  const KitakoException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'KitakoException: $message (caused by: $cause)';
    }
    return 'KitakoException: $message';
  }
}

/// Exception thrown when a model fails to load
class ModelLoadException extends KitakoException {
  const ModelLoadException(super.message, [super.cause]);
}

/// Exception thrown when inference fails
class InferenceException extends KitakoException {
  const InferenceException(super.message, [super.cause]);
}

/// Exception thrown when ANN index operations fail
class AnnIndexException extends KitakoException {
  const AnnIndexException(super.message, [super.cause]);
}

/// Exception thrown when search fails
class SearchException extends KitakoException {
  const SearchException(super.message, [super.cause]);
}

/// Exception thrown when asset loading fails
class AssetLoadException extends KitakoException {
  const AssetLoadException(super.message, [super.cause]);
}

/// Exception thrown when tokenization fails
class TokenizationException extends KitakoException {
  const TokenizationException(super.message, [super.cause]);
}

/// Exception thrown when image preprocessing fails
class PreprocessingException extends KitakoException {
  const PreprocessingException(super.message, [super.cause]);
}
