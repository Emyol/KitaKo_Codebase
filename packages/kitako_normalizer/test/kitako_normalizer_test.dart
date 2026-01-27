import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_normalizer/kitako_normalizer.dart';

void main() {
  late TaglishNormalizer normalizer;

  setUp(() {
    normalizer = const TaglishNormalizer();
  });

  group('TaglishNormalizer', () {
    group('Basic normalization', () {
      test('lowercases text', () {
        expect(normalizer.normalize('HELLO World'), 'hello world');
      });

      test('trims whitespace', () {
        expect(normalizer.normalize('  hello  '), 'hello');
      });

      test('normalizes multiple spaces', () {
        expect(normalizer.normalize('hello    world'), 'hello world');
      });

      test('handles empty string', () {
        expect(normalizer.normalize(''), '');
      });
    });

    group('Dictionary mappings', () {
      test('expands Tagalog abbreviations', () {
        expect(normalizer.normalize('aq'), 'ako');
        expect(normalizer.normalize('kc'), 'kasi');
        expect(normalizer.normalize('lng'), 'lang');
        expect(normalizer.normalize('nmn'), 'naman');
      });

      test('expands multiple abbreviations in sentence', () {
        expect(
          normalizer.normalize('gutom n aq kc d p aq kumain'),
          'gutom na ako kasi hindi pa ako kumain',
        );
      });

      test('expands text speak with numbers', () {
        expect(normalizer.normalize('d2'), 'dito');
        expect(normalizer.normalize('i2'), 'ito');
        expect(normalizer.normalize('bk8'), 'bakit');
      });

      test('expands English shorthand', () {
        expect(normalizer.normalize('gud'), 'good');
        expect(normalizer.normalize('gr8'), 'great');
        expect(normalizer.normalize('bcos'), 'because');
      });

      test('preserves words not in dictionary', () {
        expect(normalizer.normalize('masaya'), 'masaya');
        expect(normalizer.normalize('hello'), 'hello');
      });
    });

    group('Punctuation handling', () {
      test('removes apostrophes', () {
        expect(normalizer.normalize("it's"), 'its');
        expect(normalizer.normalize("don't"), 'dont');
      });

      test('converts hyphens to spaces', () {
        expect(normalizer.normalize('araw-araw'), 'araw araw');
      });

      test('adds space around punctuation', () {
        expect(normalizer.normalize('hello!'), 'hello !');
        // Note: duplicate '!' tokens get deduplicated
        expect(normalizer.normalize('wow!!'), 'wow !');
      });
    });

    group('Repeated character normalization', () {
      test('collapses 3+ repeated characters to 1', () {
        // Python regex (.)\1{2,} matches 3+ of same char
        // "hellooo" has "ooo" (3 o's) → "o", result: "hello"
        expect(normalizer.normalize('hellooo'), 'hello');
        // "niceeee" has "eeee" (4 e's) → "e", result: "nice"
        expect(normalizer.normalize('niceeee'), 'nice');
        // "yaaaay" has "aaaa" (4 a's) → "a", result: "yay"
        expect(normalizer.normalize('yaaaay'), 'yay');
      });

      test('keeps 2 repeated characters as-is', () {
        // "hello" has only 2 l's, stays as "hello"
        expect(normalizer.normalize('hello'), 'hello');
        // "book" has only 2 o's, stays as "book"
        expect(normalizer.normalize('book'), 'book');
        // "mall" has only 2 l's, stays as "mall"
        expect(normalizer.normalize('mall'), 'mall');
      });

      test('handles mixed repeated chars', () {
        // 'hellloooo' has 'lll' (3 l's) → 'l', 'oooo' (4 o's) → 'o' = 'helo'
        expect(normalizer.normalize('hellloooo'), 'helo');
      });
    });

    group('Nag- verb handling', () {
      test('extracts English verb from nag- prefix', () {
        expect(normalizer.normalize('nagshopping'), 'shopping');
        expect(normalizer.normalize('nagcooking'), 'cooking');
        expect(normalizer.normalize('nageating'), 'eating');
      });

      test('handles nag- verbs in context', () {
        expect(
          normalizer.normalize('nagshopping aq kanina'),
          'shopping ako kanina',
        );
      });

      test('preserves pure Tagalog nag- words', () {
        // Words that don't end with English verbs stay as-is
        expect(normalizer.normalize('nagluto'), 'nagluto');
        expect(normalizer.normalize('nagtrabaho'), 'nagtrabaho');
      });
    });

    group('Reduplication handling', () {
      test('preserves allowed reduplication', () {
        expect(normalizer.normalize('araw araw'), 'araw araw');
        expect(normalizer.normalize('dahan dahan'), 'dahan dahan');
        expect(normalizer.normalize('isa isa'), 'isa isa');
        expect(normalizer.normalize('halo halo'), 'halo halo');
      });

      test('removes non-allowed duplicates', () {
        expect(normalizer.normalize('ang ang'), 'ang');
        expect(normalizer.normalize('the the'), 'the');
      });

      test('handles hyphenated reduplication', () {
        // Hyphens become spaces, then reduplication is preserved
        expect(normalizer.normalize('araw-araw'), 'araw araw');
        expect(normalizer.normalize('dahan-dahan'), 'dahan dahan');
      });
    });

    group('Complex sentences', () {
      test('normalizes real Taglish queries', () {
        // Note: duplicate '!' tokens get deduplicated
        expect(
          normalizer.normalize('nagshopping aq sa mall kc sale!!'),
          'shopping ako sa mall kasi sale !',
        );

        expect(
          normalizer.normalize('gutom n aq, kain tayo'),
          'gutom na ako , kain tayo',
        );

        expect(
          normalizer.normalize('dba mlapit lng dto?'),
          'diba malapit lang dito ?',
        );
      });

      test('handles mixed English and Tagalog', () {
        expect(
          normalizer.normalize('lets go n kc late n tayo'),
          'lets go na kasi late na tayo',
        );
      });
    });
  });

  group('Extension method', () {
    test('normalizeTaglish works on strings', () {
      expect('aq'.normalizeTaglish(), 'ako');
      expect('kc lng'.normalizeTaglish(), 'kasi lang');
    });
  });

  group('Tokenizer utilities', () {
    test('tokenize splits on whitespace', () {
      expect(tokenize('hello world'), ['hello', 'world']);
      expect(tokenize('  hello   world  '), ['hello', 'world']);
    });

    test('tokenize handles empty string', () {
      expect(tokenize(''), []);
    });

    test('detokenize joins tokens', () {
      expect(detokenize(['hello', 'world']), 'hello world');
    });

    test('isPunctuation identifies punctuation', () {
      expect(isPunctuation('!'), true);
      expect(isPunctuation('...'), true);
      expect(isPunctuation('hello'), false);
      expect(isPunctuation('hello!'), false);
    });

    test('removePunctuation filters punctuation tokens', () {
      expect(
        removePunctuation(['hello', '!', 'world', '.']),
        ['hello', 'world'],
      );
    });

    test('extractWords gets alphabetic tokens only', () {
      expect(
        extractWords(['hello', '123', 'world', '!']),
        ['hello', 'world'],
      );
    });
  });
}
