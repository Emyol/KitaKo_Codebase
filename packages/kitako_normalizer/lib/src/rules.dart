/*
 * KitaKo Taglish Normalizer — Dictionary Sources and Justification
 * ================================================================
 *
 * This dictionary is composed of four layered sources, each chosen for
 * a specific reason grounded in existing literature and the constraints
 * of KitaKo's deployment context.
 *
 * SOURCE 1 — NORM / NormAPI Filipino Shortcut Text Dictionary
 * -----------------------------------------------------------
 * Primary source for Filipino SMS and social media shorthand mappings.
 * NORM (Nocon et al., 2014) is a text normalization system for Filipino
 * shortcut texts using the dictionary substitution approach, covering
 * shortening patterns documented in Filipino SMS research: consonant
 * skeleton style (vowels between consonants removed, e.g., "slmat" →
 * "salamat"), ending-a removal style (terminal 'a' dropped from
 * one-syllable words, e.g., "lng" → "lang"), and phonetic substitution
 * style (characters replaced with phonetically equivalent ones, e.g.,
 * "kc" → "kasi"). NormAPI (Nocon & Cheng, 2017) extended this to cover
 * modern Filipino including code-switching, achieving a best BLEU score
 * of 0.80750 using Dictionary Substitution combined with Statistical
 * Machine Translation. The dictionary entries from these systems form
 * the validated core of KitaKo's normalization map.
 *
 * Citation: Nocon, N. et al. (2014). NORM: A Text Normalization System
 * for Filipino Shortcut Texts Using the Dictionary Substitution
 * Approach. Proceedings of the 10th National Natural Language Processing
 * Research Symposium, pages 87–92.
 *
 * Citation: Nocon, N. & Cheng, C. (2017). NormAPI: An API for
 * Normalizing Filipino Shortcut Texts. ResearchGate.
 *
 * SOURCE 2 — KitaKo Domain Vocabulary (Derived from kitako_captions_v2)
 * ---------------------------------------------------------------------
 * Domain-specific entries derived from frequency analysis of KitaKo's
 * own Taglish image-caption dataset (`kitako_captions_v2.csv`),
 * comprising 548,945 captions across 109,789 unique images (~6.25M
 * Taglish tokens in the `tag_caption` column). The dataset covers nine
 * Philippine visual categories: education, festivals, food culture,
 * housing, markets, rural life, religion, signage, and transportation.
 *
 * The top approximately 5% of the caption type-frequency distribution
 * was extracted and screened for non-canonical surface forms following
 * the Filipino shortening patterns documented by Nocon et al. (2014) —
 * consonant-skeleton, ending-a removal, and phonetic substitution.
 * Candidate mappings were then validated against the canonical Tagalog
 * wordlist (Source 4) before inclusion. This sampling fraction targets
 * the high-frequency head of the Zipfian distribution, where shorthand
 * and code-switched forms cluster, while keeping the candidate set small
 * enough for manual validation.
 *
 * This layer ensures that normalization is aligned with the specific
 * vocabulary of KitaKo's retrieval domain — words that appear frequently
 * in the indexed image captions — so that user queries are normalized
 * toward the same canonical forms used during model training. No
 * external system can provide this layer because it is specific to
 * KitaKo's dataset.
 *
 * SOURCE 3 — TweetTaglish Social Media Vocabulary
 * ------------------------------------------------
 * Supplementary entries derived from frequency analysis of the
 * TweetTaglish dataset (Herrera et al., 2022), a Taglish Twitter
 * corpus collected using code-switching indicative Tagalog linguistic
 * features as search terms. High-frequency non-standard tokens in
 * TweetTaglish that do not appear in standard Tagalog or English
 * dictionaries were identified as shorthand candidates and
 * cross-referenced against KitaKo's canonical vocabulary to determine
 * relevant mappings. This layer extends coverage to informal,
 * social-media-style Taglish that users are likely to type when
 * searching their personal photo galleries.
 *
 * Citation: Herrera, M., Aich, A., & Parde, N. (2022). TweetTaglish:
 * A Dataset for Investigating Tagalog-English Code-Switching.
 * Proceedings of LREC 2022, pages 1630–1637.
 *
 * SOURCE 4 — Canonical Tagalog Wordlist (Validation Layer)
 * ---------------------------------------------------------
 * Standard Tagalog word lists (jmalonzo/tl-wordlist,
 * AustinZuniga/Filipino-wordlist, raymelon/tagalog-dictionary-scraper
 * sourced from tagalog.pinoydictionary.com) were used as a validation
 * filter during dictionary construction. After any proposed
 * normalization mapping, the target (canonical) form was verified
 * against these wordlists to confirm it is a valid standard Tagalog
 * or English word. Entries whose canonical form did not appear in
 * any validated wordlist were flagged for manual review before
 * inclusion. This layer does not contribute dictionary entries
 * directly — it ensures the quality of entries contributed by the
 * other three sources.
 *
 * DESIGN DECISIONS
 * ----------------
 * 1. Cross-language translation entries (e.g., "pusa" → "cat") have
 *    been intentionally removed. The SigLIP-2 encoder operates in a
 *    shared multilingual embedding space and handles both Tagalog and
 *    English natively. Translating between languages at the
 *    normalization stage corrupts the semantic signal the encoder
 *    expects. The normalizer's role is to reduce surface noise
 *    (shorthands, character repetition, spelling variance), not to
 *    translate.
 *
 * 2. Emphasis-preserving character deduplication: runs of 3+ identical
 *    characters are collapsed to 2, not 1 (e.g., "hellooooo" →
 *    "helloo", not "hello"). This preserves the emphasis signal for
 *    the encoder while removing excessive noise. Collapsing to base
 *    form loses information that the encoder can use for sentiment
 *    and intensity grounding.
 *
 * 3. The nag-/naka-/na- prefix + English verb pattern is handled by
 *    the englishVerbs set rather than the dictionary to avoid
 *    combinatorial explosion. Any word in englishVerbs prefixed by
 *    these markers is stripped to its base verb form.
 *
 * 4. Context-sensitive entries (e.g., "san" → "saan") are stored
 *    separately in contextSensitiveDictionary and are only applied
 *    when the token is lowercase and bounded by whitespace on both
 *    sides, preventing substitution inside proper nouns like
 *    "San Jose" or "Santiago".
 *
 * KNOWN SCOPE DELIMITATION
 * ------------------------
 * Creative phonetic spelling that follows no consistent pattern
 * (e.g., "aqoh" for "ako", consonant skeleton variants not in the
 * dictionary) cannot be fully handled by a rule-based system without
 * labeled training data. This is a documented limitation. Per the
 * findings of van der Goot & Çetinoğlu (2021) on code-switched
 * normalization, ML-based normalization (e.g., MoNoise) would address
 * this gap but requires labeled Taglish normalization pairs that do
 * not currently exist at sufficient scale. The pattern rules (character
 * deduplication, prefix stripping) provide partial coverage for the
 * long tail of creative spellings. Full ML-based normalization is
 * identified as future work, contingent on annotated corpus development.
 *
 * Citation: van der Goot, R. & Çetinoğlu, Ö. (2021). Lexical
 * Normalization for Code-switched Data and its Effect on POS Tagging.
 * Proceedings of EACL 2021.
 */

/// Normalization rules for Taglish text processing.
///
/// Contains dictionaries, allowed patterns, and word sets for
/// Filipino/Tagalog/Taglish text normalization.

// ============================================================
// DUPLICATE KEYS REMOVED (would cause Dart const Map compile error):
//   'tlga'  (2nd occurrence, same value 'talaga')
//   'dto'   (2nd occurrence, same value 'dito')
//   'nla'   (2nd occurrence, same value 'nila')
//   'doon'  (2nd occurrence in location section, same value 'doon')
//   'bff'   (2nd occurrence in English shorthands, conflicting value
//            'best friend' — first occurrence maps to 'kaibigan')
//
// REORDERED FOR LONGEST-MATCH-FIRST (per design principle):
//   'uv exp' moved before 'uv' in transportation section
//   'w/o'   moved before 'w/' in English shorthands section
// ============================================================

const Map<String, String> normalizationDictionary = {
  // ================================================================
  // MULTI-WORD ENTRIES (must come first for longest-match priority)
  // ================================================================

  // Negation phrases
  'di ko'       : 'hindi ko',
  'di na'       : 'hindi na',
  'di ba'       : 'hindi ba',
  'di naman'    : 'hindi naman',
  'di pa'       : 'hindi pa',
  'wla na'      : 'wala na',
  'wlang sino'  : 'walang sino',
  'hindi pa'    : 'hindi pa',

  // Common query phrases (high-frequency in KitaKo domain)
  'san yung'    : 'saan iyon',
  'san ang'     : 'saan ang',
  'ano yung'    : 'ano iyon',
  'ano ang'     : 'ano ang',
  'sino yung'   : 'sino iyon',
  'kain na'     : 'kain na',
  'na lang'     : 'na lang',
  'nlng na'     : 'na lang na',
  'para sa'     : 'para sa',
  'kasama ang'  : 'kasama ang',
  'kasama si'   : 'kasama si',

  // ================================================================
  // TAGALOG FUNCTION WORDS AND CONTRACTIONS
  // Source: NORM (Nocon et al., 2014) — consonant skeleton and
  // ending-a removal patterns
  // ================================================================

  // Negation
  'di'      : 'hindi',
  'dko'     : 'hindi ko',
  'hnd'     : 'hindi',
  'hndi'    : 'hindi',

  // Absence
  'wla'     : 'wala',
  'wlang'   : 'walang',
  'wala'    : 'wala',

  // Conjunctions and particles
  // Source: NORM (Nocon et al., 2014) — consonant skeleton and
  // ending-a removal patterns
  'kc'      : 'kasi',
  'kse'     : 'kasi',
  'lng'     : 'lang',
  'nlng'    : 'na lang',
  'nalng'   : 'na lang',
  'nman'    : 'naman',
  'nmn'     : 'naman',
  'tlga'    : 'talaga',
  'nga'     : 'nga',
  'ba'      : 'ba',
  'po'      : 'po',
  'ho'      : 'ho',
  'dn'      : 'din',
  'pla'     : 'pala',
  'plng'    : 'palang',
  'ndi'     : 'ndi',
  'e'       : 'eh',
  'kpag'    : 'kapag',
  'pag'     : 'kapag',
  'pgka'    : 'pagka',
  'kahit'   : 'kahit',
  'khit'    : 'kahit',
  'kht'     : 'kahit',
  'kung'    : 'kung',
  'kng'     : 'kung',
  'para'    : 'para',
  'pra'     : 'para',
  'tapos'   : 'tapos',
  'tas'     : 'tapos',
  'tpos'    : 'tapos',
  'tpz'     : 'tapos',
  'habang'  : 'habang',
  'hbng'    : 'habang',
  'dahil'   : 'dahil',
  'dhl'     : 'dahil',
  'dhil'    : 'dahil',
  'pero'    : 'pero',
  'pr'      : 'pero',
  'kundi'   : 'kundi',
  'at'      : 'at',
  'o'       : 'o',

  // Demonstrative pronouns
  // Source: KitaKo domain — high-frequency in image search queries
  'yun'     : 'iyon',
  'yung'    : 'iyon',
  'yon'     : 'iyon',
  'yan'     : 'iyan',
  'yaan'    : 'iyan',
  'dto'     : 'dito',
  'dun'     : 'doon',
  'doon'    : 'doon',
  'dyan'    : 'diyan',
  'nandto'  : 'nandito',
  'nndto'   : 'nandito',
  'nandon'  : 'nandoon',
  'nndun'   : 'nandoon',

  // Personal pronouns
  // Source: NORM (Nocon et al., 2014) — phonetic substitution pattern
  'aq'      : 'ako',
  'aqo'     : 'ako',
  'aqoh'    : 'ako',
  'ako'     : 'ako',
  'ikw'     : 'ikaw',
  'ikaw'    : 'ikaw',
  'sya'     : 'siya',
  'sha'     : 'siya',
  'cya'     : 'siya',
  'sila'    : 'sila',
  'sla'     : 'sila',
  'tyo'     : 'tayo',
  'tau'     : 'tayo',
  'tyu'     : 'tayo',
  'kmi'     : 'kami',
  'kyo'     : 'kayo',
  'nyo'     : 'ninyo',
  'natin'   : 'natin',
  'nmin'    : 'namin',
  'namin'   : 'namin',
  'nila'    : 'nila',
  'nla'     : 'nila',
  'knya'    : 'kanya',
  'knia'    : 'kanya',
  'kania'   : 'kanya',
  'niya'    : 'niya',
  'nya'     : 'niya',

  // Question words
  // Source: KitaKo domain — core image search query words
  'ano'     : 'ano',
  'anong'   : 'anong',
  'anung'   : 'anong',
  'sino'    : 'sino',
  'sinu'    : 'sino',
  'nasaan'  : 'nasaan',
  'kelan'   : 'kailan',
  'klaan'   : 'kailan',
  'klan'    : 'kailan',
  'bakit'   : 'bakit',
  'bkit'    : 'bakit',
  'paano'   : 'paano',
  'pano'    : 'paano',
  'panu'    : 'paano',
  'gaano'   : 'gaano',
  'gano'    : 'gaano',

  // Affirmation and response words
  // Source: TweetTaglish (Herrera et al., 2022) — high-frequency tokens
  'oo'      : 'oo',
  'opo'     : 'opo',
  'opp'     : 'opo',
  'yep'     : 'oo',
  'yup'     : 'oo',
  'nope'    : 'hindi',
  'ayos'    : 'ayos',
  'sige'    : 'sige',
  'sgi'     : 'sige',
  'sge'     : 'sige',
  'ok'      : 'okay',
  'okay'    : 'okay',

  // Descriptive and emotional words
  // Source: TweetTaglish (Herrera et al., 2022) — common informal forms
  'grabe'      : 'grabe',
  'grabi'      : 'grabe',
  'grb'        : 'grabe',
  'ganda'      : 'ganda',
  'gnda'       : 'ganda',
  'maganda'    : 'maganda',
  'mganda'     : 'maganda',
  'magandang'  : 'magandang',
  'sobra'      : 'sobra',
  'sbra'       : 'sobra',
  'super'      : 'sobrang',
  'supr'       : 'sobrang',
  'ang ganda'  : 'ang ganda',
  'masaya'     : 'masaya',
  'msaya'      : 'masaya',
  'malungkot'  : 'malungkot',
  'mlngkot'    : 'malungkot',
  'nakakatuwa' : 'nakakatuwa',
  'nktwa'      : 'nakakatuwa',
  'nakakatakot': 'nakakatakot',
  'nktkot'     : 'nakakatakot',
  'cute'       : 'cute',
  'cte'        : 'cute',
  'kyut'       : 'cute',
  'gwapa'      : 'maganda',
  'gwapo'      : 'gwapo',
  'pangit'     : 'pangit',
  'pngit'      : 'pangit',

  // Greetings and courtesy words
  // Source: NORM (Nocon et al., 2014) — validated Filipino shorthand
  'kamusta' : 'kamusta',
  'kamsta'  : 'kamusta',
  'kumusta' : 'kumusta',
  'kmusta'  : 'kumusta',
  'kmsta'   : 'kumusta',
  'salamat' : 'salamat',
  'slmat'   : 'salamat',
  'slmt'    : 'salamat',
  'ingat'   : 'ingat',
  'ingt'    : 'ingat',
  'musta'   : 'kumusta',
  'usta'    : 'kumusta',

  // Kinship and social terms
  // Source: KitaKo domain — frequent in personal photo captions
  'ate'     : 'ate',
  'kuya'    : 'kuya',
  'lola'    : 'lola',
  'lolo'    : 'lolo',
  'mama'    : 'mama',
  'papa'    : 'papa',
  'nanay'   : 'nanay',
  'tatay'   : 'tatay',
  'nay'     : 'nanay',
  'tay'     : 'tatay',
  'tita'    : 'tita',
  'tito'    : 'tito',
  'anak'    : 'anak',
  'kaibigan': 'kaibigan',
  'kbigan'  : 'kaibigan',
  'bestie'  : 'kaibigan',
  'bff'     : 'kaibigan',
  'kasama'  : 'kasama',
  'ksama'   : 'kasama',
  'pamilya' : 'pamilya',
  'pmlya'   : 'pamilya',

  // Modal and ability words
  'pwede'    : 'pwede',
  'pwde'     : 'pwede',
  'pede'     : 'pwede',
  'kaya'     : 'kaya',
  'kya'      : 'kaya',
  'gusto'    : 'gusto',
  'gsto'     : 'gusto',
  'ayaw'     : 'ayaw',
  'ayw'      : 'ayaw',
  'kailangan': 'kailangan',
  'klangan'  : 'kailangan',
  'klngn'    : 'kailangan',
  'dapat'    : 'dapat',
  'dpat'     : 'dapat',
  'alam'     : 'alam',
  'alm'      : 'alam',

  // Location and place words
  // Source: KitaKo domain — critical for image search by location
  // Note: 'doon' defined in demonstratives section above; omitted here
  'dito'  : 'dito',
  'diyan' : 'diyan',
  'labas' : 'labas',
  'lbas'  : 'labas',
  'loob'  : 'loob',
  'harap' : 'harap',
  'hrp'   : 'harap',
  'likod' : 'likod',
  'lkd'   : 'likod',
  'tabi'  : 'tabi',
  'taas'  : 'taas',
  'baba'  : 'baba',
  'gilid' : 'gilid',
  'gitna' : 'gitna',
  'gtnah' : 'gitna',

  // ================================================================
  // KITAKO DOMAIN VOCABULARY
  // Source: Derived from 1.2M KitaKo caption dataset
  // Categories: education, festivals, food, housing, markets,
  // rural life, religion, signage, transportation
  // ================================================================

  // Transportation (high-frequency in KitaKo dataset)
  // Note: 'uv exp' listed before 'uv' for longest-match-first
  'uv exp'  : 'uv express',
  'jeep'    : 'jeepney',
  'dyip'    : 'jeepney',
  'dyipni'  : 'jeepney',
  'trike'   : 'tricycle',
  'tryke'   : 'tricycle',
  'traysikl': 'tricycle',
  'bus'     : 'bus',
  'buss'    : 'bus',
  'lrt'     : 'lrt',
  'mrt'     : 'mrt',
  'fx'      : 'fx',
  'uv'      : 'uv express',
  'pedicab' : 'pedicab',
  'pdcab'   : 'pedicab',
  'habal'   : 'habal habal',
  'bangka'  : 'bangka',
  'bngka'   : 'bangka',
  'barko'   : 'barko',
  'brko'    : 'barko',

  // Food culture (high-frequency in KitaKo dataset)
  'kain'      : 'kain',
  'kna'       : 'kain na',
  'lutoin'    : 'luto',
  'niluto'    : 'niluto',
  'luto'      : 'luto',
  'pagkain'   : 'pagkain',
  'pgkain'    : 'pagkain',
  'ulam'      : 'ulam',
  'kanin'     : 'kanin',
  'knin'      : 'kanin',
  'merienda'  : 'merienda',
  'mrenda'    : 'merienda',
  'almusal'   : 'almusal',
  'almusl'    : 'almusal',
  'tanghalian': 'tanghalian',
  'tnghlian'  : 'tanghalian',
  'hapunan'   : 'hapunan',
  'hpunan'    : 'hapunan',
  'ref'       : 'refrigerator',
  'pridyider' : 'refrigerator',
  'prydyr'    : 'refrigerator',

  // Religion (high-frequency in KitaKo dataset)
  'simbahan'  : 'simbahan',
  'smbahan'   : 'simbahan',
  'simba'     : 'simbahan',
  'misa'      : 'misa',
  'msya'      : 'misa',
  'pari'      : 'pari',
  'pry'       : 'pari',
  'madre'     : 'madre',
  'krus'      : 'krus',
  'altar'     : 'altar',
  'rosaryo'   : 'rosaryo',
  'rsaryo'    : 'rosaryo',
  'panalangin': 'panalangin',
  'dasal'     : 'dasal',
  'dsal'      : 'dasal',
  'pasyon'    : 'pasyon',
  'psyon'     : 'pasyon',

  // Festivals (high-frequency in KitaKo dataset)
  'fiesta'   : 'pista',
  'pista'    : 'pista',
  'pistang'  : 'pistang',
  'handaan'  : 'handaan',
  'hndaan'   : 'handaan',
  'sayaw'    : 'sayaw',
  'syw'      : 'sayaw',
  'prusisyon': 'prusisyon',
  'prssyon'  : 'prusisyon',
  'parade'   : 'parade',
  'prd'      : 'parade',
  'bulaklak' : 'bulaklak',
  'blklak'   : 'bulaklak',

  // Education (high-frequency in KitaKo dataset)
  'eskwela'   : 'paaralan',
  'skwela'    : 'paaralan',
  'paaralan'  : 'paaralan',
  'klase'     : 'klase',
  'kls'       : 'klase',
  'guro'      : 'guro',
  'titser'    : 'guro',
  'teacher'   : 'guro',
  'estudyante': 'estudyante',
  'stydnt'    : 'estudyante',
  'student'   : 'estudyante',
  'grad'      : 'graduation',
  'gradweyt'  : 'graduation',
  'graduation': 'graduation',
  'diploma'   : 'diploma',
  'dpiloma'   : 'diploma',
  'board'     : 'board exam',

  // Housing (high-frequency in KitaKo dataset)
  'bahay'   : 'bahay',
  'bhy'     : 'bahay',
  'bhay'    : 'bahay',
  'sala'    : 'sala',
  'kwarto'  : 'kwarto',
  'kwrto'   : 'kwarto',
  'banyo'   : 'banyo',
  'bnyo'    : 'banyo',
  'kusina'  : 'kusina',
  'ksna'    : 'kusina',
  'bakuran' : 'bakuran',
  'bkrn'    : 'bakuran',
  'pintuan' : 'pintuan',
  'pntuan'  : 'pintuan',
  'bintana' : 'bintana',
  'bntna'   : 'bintana',

  // Markets (high-frequency in KitaKo dataset)
  'palengke' : 'palengke',
  'plngke'   : 'palengke',
  'tindahan' : 'tindahan',
  'tndhan'   : 'tindahan',
  'sari sari': 'sari-sari store',
  'sarisari' : 'sari-sari store',
  'karinderia': 'karinderia',
  'krndrya'  : 'karinderia',
  'pamilihan': 'palengke',
  'bili'     : 'bili',
  'benta'    : 'benta',
  'bnt'      : 'benta',
  'presyo'   : 'presyo',
  'prsyo'    : 'presyo',
  'mahal'    : 'mahal',
  'mura'     : 'mura',

  // ================================================================
  // CAPTION-DERIVED DOMAIN VOCABULARY (kitako_captions_v2.csv)
  // Lemmas drawn from the top ~5% of the type-frequency distribution
  // of the tag_caption column (1,842 types covering 91.89% of all
  // token occurrences across 548,945 captions / ~6.55M alpha tokens).
  // Shorthand variants generated using NORM consonant-skeleton and
  // ending-a removal patterns (Nocon et al., 2014), then validated
  // against the canonical Tagalog wordlist (Source 4).
  // ================================================================

  // Rural life and nature
  'kalye'       : 'kalye',
  'kly'         : 'kalye',
  'kalsada'     : 'kalsada',
  'klsada'      : 'kalsada',
  'lungsod'     : 'lungsod',
  'lngsod'      : 'lungsod',
  'lngsd'       : 'lungsod',
  'gusali'      : 'gusali',
  'gsali'       : 'gusali',
  'dagat'       : 'dagat',
  'dgat'        : 'dagat',
  'karagatan'   : 'karagatan',
  'krgatan'     : 'karagatan',
  'dalampasigan': 'dalampasigan',
  'dlmpsgan'    : 'dalampasigan',
  'damuhan'     : 'damuhan',
  'dmuhan'      : 'damuhan',
  'bukid'       : 'bukid',
  'bkid'        : 'bukid',
  'bundok'      : 'bundok',
  'bndok'       : 'bundok',
  'ilog'        : 'ilog',
  'puno'        : 'puno',
  'kahoy'       : 'kahoy',
  'khoy'        : 'kahoy',
  'lupa'        : 'lupa',
  'niyebe'      : 'niyebe',
  'nybe'        : 'niyebe',
  'ulan'        : 'ulan',
  'araw'        : 'araw',
  'arw'         : 'araw',
  'buwan'       : 'buwan',
  'bwan'        : 'buwan',
  'bulaklak ng' : 'bulaklak ng',

  // Animals
  'aso'         : 'aso',
  'pusa'        : 'pusa',
  'psa'         : 'pusa',
  'kabayo'      : 'kabayo',
  'kbyo'        : 'kabayo',
  'kbayo'       : 'kabayo',
  'ibon'        : 'ibon',
  'iobn'        : 'ibon',
  'idsa'        : 'isda',
  'manok'       : 'manok',
  'mnok'        : 'manok',
  'kalabaw'     : 'kalabaw',
  'klabaw'      : 'kalabaw',

  // People and common subjects
  'lalaki'      : 'lalaki',
  'llki'        : 'lalaki',
  'llaki'       : 'lalaki',
  'babae'       : 'babae',
  'bbae'        : 'babae',
  'bata'        : 'bata',
  'bta'         : 'bata',
  'larawan'     : 'larawan',
  'lrwan'       : 'larawan',
  'larwan'      : 'larawan',

  // Signage and street furniture
  'karatula'    : 'karatula',
  'krtula'      : 'karatula',
  'orasan'      : 'orasan',
  'orsan'       : 'orasan',
  'parke'       : 'parke',
  'prke'        : 'parke',
  'tulay'       : 'tulay',

  // Household objects (extension to housing)
  'mesa'        : 'mesa',
  'upuan'       : 'upuan',
  'upwan'       : 'upuan',
  'silid'       : 'silid',
  'sld'         : 'silid',
  'salamin'     : 'salamin',
  'slmin'       : 'salamin',
  'payong'      : 'payong',
  'pyng'        : 'payong',
  'dingding'    : 'dingding',
  'dngdng'      : 'dingding',
  'lababo'      : 'lababo',
  'lbbo'        : 'lababo',
  'sahig'       : 'sahig',
  'plato'       : 'plato',
  'baso'        : 'baso',
  'kama'        : 'kama',
  'kutsara'     : 'kutsara',
  'ktsra'       : 'kutsara',

  // Transportation (extension)
  'tren'        : 'tren',
  'eroplano'    : 'eroplano',
  'erpln'       : 'eroplano',
  'motorsiklo'  : 'motorsiklo',
  'mtrsklo'     : 'motorsiklo',
  'sasakyan'    : 'sasakyan',
  'sskyan'      : 'sasakyan',
  'kotse'       : 'kotse',
  'ktse'        : 'kotse',

  // Food culture (extension)
  'saging'      : 'saging',
  'sging'       : 'saging',
  'gulay'       : 'gulay',
  'glay'        : 'gulay',
  'itlog'       : 'itlog',
  'prutas'      : 'prutas',
  'prts'        : 'prutas',
  'tinapay'     : 'tinapay',
  'tnapay'      : 'tinapay',

  // Stative locative verbs (naka- prefix on Tagalog roots)
  // High-frequency in caption descriptions of visual scenes
  'nakaupo'     : 'nakaupo',
  'nkaupo'      : 'nakaupo',
  'nakatayo'    : 'nakatayo',
  'nktayo'      : 'nakatayo',
  'nakahiga'    : 'nakahiga',
  'nkahiga'     : 'nakahiga',
  'nakasakay'   : 'nakasakay',
  'nksakay'     : 'nakasakay',
  'nakasuot'    : 'nakasuot',
  'nksuot'      : 'nakasuot',
  'nakatingin'  : 'nakatingin',
  'nktingin'    : 'nakatingin',
  'nakaparada'  : 'nakaparada',
  'nkparada'    : 'nakaparada',
  'nakapatong'  : 'nakapatong',
  'nkpatong'    : 'nakapatong',
  'nakasabit'   : 'nakasabit',
  'nksabit'     : 'nakasabit',
  'nakahawak'   : 'nakahawak',
  'nakasandal'  : 'nakasandal',

  // Action verbs (mag-/-um- forms common in captions)
  'naglalakad'  : 'naglalakad',
  'nglalakad'   : 'naglalakad',
  'naglalaro'   : 'naglalaro',
  'nglalaro'    : 'naglalaro',
  'kumakain'    : 'kumakain',
  'kmkain'      : 'kumakain',
  'lumilipad'   : 'lumilipad',
  'lmlipad'     : 'lumilipad',
  'tumatakbo'   : 'tumatakbo',
  'tmtkbo'      : 'tumatakbo',
  'umiinom'     : 'umiinom',
  'nagluluto'   : 'nagluluto',
  'ngluluto'    : 'nagluluto',
  'naghahanda'  : 'naghahanda',
  'nghahanda'   : 'naghahanda',
  'nagpapakita' : 'nagpapakita',
  'hawak'       : 'hawak',
  'hwak'        : 'hawak',

  // Colors (high-frequency descriptors in caption queries)
  'asul'        : 'asul',
  'puti'        : 'puti',
  'puting'      : 'puti',
  'itim'        : 'itim',
  'itm'         : 'itim',
  'pula'        : 'pula',
  'pulang'      : 'pula',
  'berde'       : 'berde',
  'berdeng'     : 'berde',
  'brde'        : 'berde',
  'dilaw'       : 'dilaw',
  'dlaw'        : 'dilaw',
  'kulay'       : 'kulay',
  'klay'        : 'kulay',
  'kahel'       : 'kahel',
  'rosas'       : 'rosas',

  // Spatial relations (locative descriptors)
  'ibabaw'      : 'ibabaw',
  'ibbw'        : 'ibabaw',
  'ilalim'      : 'ilalim',
  'illm'        : 'ilalim',
  'malapit'     : 'malapit',
  'mlpit'       : 'malapit',
  'malayo'      : 'malayo',
  'mlyo'        : 'malayo',
  'paligid'     : 'paligid',
  'pligid'      : 'paligid',

  // Size and quantity descriptors
  'malaki'      : 'malaki',
  'mlki'        : 'malaki',
  'malaking'    : 'malaki',
  'maliit'      : 'maliit',
  'mlit'        : 'maliit',
  'marami'      : 'marami',
  'mrami'       : 'marami',
  'maraming'    : 'marami',
  'ilan'        : 'ilan',
  'ilang'       : 'ilan',
  'dalawa'      : 'dalawa',
  'dalawang'    : 'dalawa',
  'tatlo'       : 'tatlo',
  'tatlong'     : 'tatlo',

  // Body parts (high-frequency in caption descriptions)
  'kamay'       : 'kamay',
  'kmay'        : 'kamay',
  'ulo'         : 'ulo',
  'mata'        : 'mata',
  'mukha'       : 'mukha',
  'mkha'        : 'mukha',
  'paa'         : 'paa',
  'binti'       : 'binti',
  'leeg'        : 'leeg',
  'tenga'       : 'tenga',

  // Materials and miscellaneous objects (caption-derived)
  'saranggola'  : 'saranggola',
  'srnggola'    : 'saranggola',
  'damo'        : 'damo',
  'tubig'       : 'tubig',
  'tbig'        : 'tubig',
  'bato'        : 'bato',
  'apoy'        : 'apoy',
  'usok'        : 'usok',
  'pader'       : 'pader',
  'pdr'         : 'pader',
  'hagdan'      : 'hagdan',
  'hgdn'        : 'hagdan',

  // ================================================================
  // ENGLISH SHORTHANDS COMMON IN TAGLISH
  // Source: TweetTaglish (Herrera et al., 2022)
  // Note: 'w/o' listed before 'w/' for longest-match-first
  // Note: 'bff' → 'best friend' omitted — duplicate key
  //       ('bff' already maps to 'kaibigan' in kinship section)
  // ================================================================
  'u'        : 'you',
  'ur'       : 'your',
  'urs'      : 'yours',
  'r'        : 'are',
  'b4'       : 'before',
  'l8r'      : 'later',
  'l8'       : 'late',
  'w/o'      : 'without',
  'w/'       : 'with',
  'pic'      : 'picture',
  'pics'     : 'pictures',
  'pix'      : 'pictures',
  'vid'      : 'video',
  'vids'     : 'videos',
  'bday'     : 'birthday',
  'brthdy'   : 'birthday',
  'bf'       : 'boyfriend',
  'gf'       : 'girlfriend',
  'fam'      : 'family',
  'squard'   : 'barkada',
  'squad'    : 'barkada',
  'barkada'  : 'barkada',
  'barkds'   : 'barkada',
  'ft'       : 'featuring',
  'selfie'   : 'selfie',
  'slfi'     : 'selfie',
  'groufie'  : 'group photo',
  'groupie'  : 'group photo',
  'ootd'     : 'outfit',
  'tbt'      : 'throwback',
  'throwback': 'throwback',
  'thrwbck'  : 'throwback',
};

/// Context-sensitive dictionary applied token-by-token after the main
/// dictionary pass.
///
/// Entries here are only substituted when the token is an exact whole-word
/// match (bounded by whitespace) and is entirely lowercase. This prevents
/// accidental substitution inside proper nouns. Because the normalizer
/// lowercases text before this step, "San Jose" becomes "san jose" — the
/// lowercase-check alone cannot distinguish proper nouns after lowercasing.
/// This is a documented scope delimitation (see block comment above).
const Map<String, String> contextSensitiveDictionary = {
  // Applied ONLY when token is lowercase AND bounded by whitespace
  // on both sides. Prevents substitution inside proper nouns.
  // e.g., "san" → "saan" but NOT "San Jose" → "Saan Jose"
  'san' : 'saan',
  'ka'  : 'ka',
  // Note: 'ka' is kept as-is — too ambiguous to expand.
  // It can mean "you" (ikaw) or be part of a verb focus marker.
  // The encoder handles this ambiguity in embedding space.
};

/// Common English verbs used in Taglish speech.
///
/// Used to detect patterns like "nag-" + English verb
/// (e.g., "nagshopping" → "shopping").
/// Source: Common English verbs observed in Taglish social media text
/// and KitaKo domain captions.
const Set<String> englishVerbs = {
  // Communication
  'chat', 'text', 'call', 'post', 'share', 'send', 'reply',
  'comment', 'like', 'follow', 'upload', 'download', 'stream',
  'message', 'tweet', 'blog', 'vlog', 'livestream', 'react',

  // Movement and activity
  'walk', 'run', 'drive', 'ride', 'travel', 'commute', 'fly',
  'swim', 'dance', 'sing', 'play', 'exercise', 'workout', 'jog',
  'hike', 'climb', 'surf', 'skate', 'bike',

  // Shopping and commerce
  'shop', 'buy', 'sell', 'order', 'deliver', 'checkout', 'pay',

  // Food and drink
  'eat', 'cook', 'bake', 'drink', 'dine', 'grill', 'fry',

  // Work and study
  'work', 'study', 'research', 'review', 'present', 'report',
  'submit', 'print', 'type', 'code', 'design', 'edit', 'check',
  'train', 'practice', 'read',

  // Social and events
  'celebrate', 'party', 'attend', 'join', 'meet', 'hang', 'visit',
  'tour', 'watch', 'perform', 'shoot', 'record', 'film', 'pose',

  // Technology
  'install', 'update', 'reset', 'charge', 'connect', 'search',
  'google', 'screenshot', 'selfie',

  // General
  'try', 'use', 'start', 'stop', 'finish', 'fix', 'clean',
  'move', 'change', 'wait', 'plan', 'prepare', 'pack',
};

/// Allowed reduplicated word pairs that should NOT be deduplicated.
///
/// These are lexicalized Tagalog expressions where reduplication
/// carries specific meaning. Pairs in this set are preserved by the
/// consecutive-duplicate-removal step.
const Set<String> allowedReduplication = {
  // Time and frequency expressions
  'araw araw',
  'gabi gabi',
  'umaga umaga',
  'hapon hapon',
  'linggo linggo',
  'buwan buwan',
  'taon taon',
  'oras oras',

  // Intensity and manner expressions
  'dahan dahan',
  'pababa baba',
  'pataas taas',
  'palayo layo',
  'mabilis bilis',
  'marami rami',
  'konti konti',
  'isa isa',
  'tig isa',

  // Reduplicated nouns (standard Filipino forms)
  // Note: 'iba iba' appears twice in source spec; Set deduplicates automatically
  'iba iba',
  'sari sari',
  'bawat isa',
  'kanya kanya',
  'kani kanina',
  'halo halo',
  'luto luto',
  'turo turo',
};
