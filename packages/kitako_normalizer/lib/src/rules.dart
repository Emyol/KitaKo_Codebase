/// Normalization rules for Taglish text processing.
///
/// Contains dictionaries, allowed patterns, and word sets for
/// Filipino/Tagalog/Taglish text normalization.

/// Allowed reduplicated word pairs that should NOT be deduplicated.
///
/// These are lexicalized Tagalog expressions where reduplication
/// carries specific meaning.
const Set<String> allowedReduplication = {
  // Core lexicalized Tagalog reduplication
  'araw araw', // daily
  'gabi gabi', // every night
  'taon taon', // yearly
  'linggo linggo', // weekly
  'buwan buwan', // monthly

  'isa isa', // one by one
  'paulit ulit', // repeatedly
  'sabay sabay', // together
  'sunod sunod', // consecutive
  'halo halo', // mixed (food)
  'sari sari', // variety / store
  'iba iba', // different
  'kung saan saan', // everywhere
  'paikot ikot', // going around
  'pabalik balik', // back and forth

  // Body / action related (visible)
  'takbo takbo', // running around
  'lakad lakad', // walking around
  'tingin tingin', // looking around
  'ikot ikot', // circling

  // Descriptive / visual emphasis
  'dahan dahan', // slowly
  'bilis bilis', // quickly
  'siksik siksik', // crowded
  'dikit dikit', // close together

  // Environment / scene
  'ulan ulan', // rainy
  'init init', // hot
  'lamig lamig', // cold
};

/// Common English verbs used in Taglish speech.
///
/// Used to detect patterns like "nag-" + English verb
/// (e.g., "nagshopping" → "shopping")
const Set<String> englishVerbs = {
  // Movement / posture
  'walk', 'run', 'stand', 'sit', 'lie', 'lying',
  'jump', 'hop', 'skip', 'crawl', 'climb',
  'dance', 'pose', 'lean', 'kneel',

  // Interaction with objects
  'hold', 'carry', 'grab', 'touch', 'push', 'pull',
  'lift', 'throw', 'catch', 'drop',
  'open', 'close', 'pick', 'place',

  // Eating / drinking
  'eat', 'eating', 'drink', 'drinking',
  'cook', 'cooking', 'serve',

  // Looking / perception
  'look', 'looking', 'watch', 'watching',
  'see', 'stare', 'smile', 'laugh', 'cry',

  // Daily activities
  'sleep', 'sleeping', 'wake',
  'rest', 'resting', 'work', 'working',
  'study', 'studying', 'read', 'reading',
  'write', 'writing', 'draw', 'drawing',

  // Play / leisure
  'play', 'playing', 'game', 'gaming',
  'swim', 'swimming',
  'ride', 'riding',
  'bike', 'cycling',

  // Vehicles / travel
  'drive', 'driving',
  'park', 'parking',
  'travel', 'traveling',
  'walking',

  // Social / interaction
  'talk', 'talking',
  'chat', 'chatting',
  'hug', 'hugging',
  'kiss', 'kissing',

  // Photography-specific
  'posing',
  'shoot', 'shooting',
  'record', 'recording',

  // Shopping / activities
  'shop', 'shopping',
  'buy', 'buying',
  'sell', 'selling',
};

/// Dictionary mapping informal/abbreviated text to standard forms.
///
/// Includes:
/// - Tagalog text speak abbreviations
/// - Numeric substitutions (e.g., "2" for "to")
/// - Common misspellings
/// - English shorthand
const Map<String, String> normalizationDictionary = {
  // Tagalog function words
  'aq': 'ako',
  'anq': 'anak',
  'anu': 'ano',
  'b': 'ba',
  'bk8': 'bakit',
  'bkt': 'bakit',
  'bka': 'baka',
  'bta': 'bata',
  'bwat': 'bawat',
  'cia': 'siya',
  'cla': 'sila',
  'cgro': 'siguro',
  'cguro': 'siguro',
  'cmula': 'simula',
  'cnabi': 'sinabi',
  'd': 'hindi',
  'd2': 'dito',
  'dba': 'diba',
  'dn': 'din',
  'dpat': 'dapat',
  'dto': 'dito',
  'dyn': 'diyan',
  'gbi': 'gabi',
  'gvi': 'gabi',
  'gwa': 'gawa',
  'habng': 'habang',
  'hnd': 'hindi',
  'hndi': 'hindi',
  'hwag': 'huwag',
  'i2': 'ito',
  'ibg': 'ibig',
  'icp': 'isip',
  'ingt': 'ingat',
  'jan': 'diyan',
  'jn': 'diyan',
  'kaba': 'ka ba',
  'kana': 'ka na',
  'kn': 'ka na',
  'kna': 'ka na',
  'kau': 'kayo',
  'kc': 'kasi',
  'kci': 'kasi',
  'khit': 'kahit',
  'kme': 'kami',
  'kng': 'kung',
  'kun': 'kung',
  'kp': 'ka pa',
  'ksma': 'kasama',
  'ktabi': 'katabi',
  'kya': 'kaya',
  'lhat': 'lahat',
  'lht': 'lahat',
  'lng': 'lang',
  'm': 'mo',
  'mu': 'mo',
  'mejo': 'medyo',
  'mlaki': 'malaki',
  'mlapit': 'malapit',
  'mlyo': 'malayo',
  'mrami': 'marami',
  'msama': 'masama',
  'mskit': 'masakit',
  'msyado': 'masyado',
  'my': 'may',
  'n': 'na',
  'nah': 'na',
  'nd': 'hindi',
  'ngaun': 'ngayon',
  'ngyun': 'ngayon',
  'nl': 'nila',
  'nla': 'nila',
  'nman': 'naman',
  'nmn': 'naman',
  'nnaman': 'na naman',
  'nnamn': 'na naman',
  'nsa': 'nasa',
  'ntin': 'natin',
  'nyo': 'niyo',
  'p': 'pa',
  'pba': 'pa ba',
  'pla': 'pala',

  // Common Tagalog content words (caption-relevant)
  'bhay': 'bahay',
  'bgay': 'bagay',
  'bgyo': 'bagyo',
  'bqyo': 'bagyo',
  'gnyan': 'ganyan',
  'la2ki': 'lalaki',
  'lage': 'lagi',
  'mhal': 'mahal',
  'maherap': 'mahirap',
  'mwla': 'mawala',
  'mwln': 'mawalan',
  'naka2': 'nakaka',
  'nkkita': 'nakikita',
  'nkktkt': 'nakakatakot',
  'nkkawa': 'nakakaawa',

  // Verbs / actions (image-visible)
  'abutn': 'abutin',
  'awayn': 'awayin',
  'ggwin': 'gagawin',
  'gnawa': 'ginawa',
  'gnagawa': 'ginagawa',
  'naghi2ntay': 'naghihintay',
  'ngyyri': 'nangyayari',
  'ngyari': 'nangyari',
  'npapakinggan': 'napapakinggan',
  'nttwa': 'natatawa',

  // Tagalog → English translations (demo vocabulary)
  'pusa': 'cat',
  'aso': 'dog',
  'lalaki': 'guy',
  'lalake': 'guy',
  'kain': 'eating',

  // English shorthand / numeric substitutions
  'bcos': 'because',
  'bcoz': 'because',
  'c0mplain': 'complain',
  'c0ntr0l': 'control',
  'frm': 'from',
  'gr8': 'great',
  'gud': 'good',
  'h0pe': 'hope',
  'm0rning': 'morning',
  'morng': 'morning',
  'n0body': 'nobody',
};

