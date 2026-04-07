// lib/core/fun_content_repository.dart

import 'package:flutter/material.dart';
import 'db_provider.dart';
import 'db_schema.dart';

// ── Modelos ────────────────────────────────────────────────────────────────────

class JokeItem {
  final int id;
  final String text;
  const JokeItem({required this.id, required this.text});
}

class PhraseItem {
  final int id;
  final String text;
  final String author;
  const PhraseItem({
    required this.id,
    required this.text,
    required this.author,
  });
}

class LanguagePhrase {
  final int id;
  final String language;
  final String phrase;
  final String pronunciation;
  final String meaning;
  final String example;
  final String examplePronunciation;
  const LanguagePhrase({
    required this.id,
    required this.language,
    required this.phrase,
    required this.pronunciation,
    required this.meaning,
    required this.example,
    required this.examplePronunciation,
  });
}

class FactItem {
  final int id;
  final String text;
  final String category;
  const FactItem({
    required this.id,
    required this.text,
    required this.category,
  });
}

// ── Repositorio ────────────────────────────────────────────────────────────────

class FunContentRepository {
  FunContentRepository._();
  static final FunContentRepository instance = FunContentRepository._();

  // ── Seed ────────────────────────────────────────────────────────────────────

  Future<void> seedIfEmpty() async {
    final db = DBProvider.db;
    if (await db.count(DBSchema.tableJokes) == 0) {
      await db.batchInsert(DBSchema.tableJokes, _jokes);
    }
    if (await db.count(DBSchema.tablePhrases) == 0) {
      await db.batchInsert(DBSchema.tablePhrases, _phrases);
    }
    if (await db.count(DBSchema.tableLanguageWords) == 0) {
      await db.batchInsert(DBSchema.tableLanguageWords, _idioms);
    }
    if (await db.count(DBSchema.tableFacts) == 0) {
      await db.batchInsert(DBSchema.tableFacts, _facts);
    }
  }

  // ── Queries ──────────────────────────────────────────────────────────────────

  Future<JokeItem> randomJoke() async {
    final rows = await DBProvider.db.query(
      DBSchema.tableJokes,
      orderBy: 'RANDOM()',
      limit: '1',
    );
    if (rows.isEmpty)
      return const JokeItem(id: 0, text: 'Sin chistes disponibles.');
    final r = rows.first;
    return JokeItem(id: r['id'] as int, text: r['text'] as String);
  }

  Future<PhraseItem> randomPhrase() async {
    final rows = await DBProvider.db.query(
      DBSchema.tablePhrases,
      orderBy: 'RANDOM()',
      limit: '1',
    );
    if (rows.isEmpty)
      return const PhraseItem(
        id: 0,
        text: 'Sin frases disponibles.',
        author: '',
      );
    final r = rows.first;
    return PhraseItem(
      id: r['id'] as int,
      text: r['text'] as String,
      author: (r['author'] as String?) ?? '',
    );
  }

  Future<LanguagePhrase> randomIdiom() async {
    final rows = await DBProvider.db.query(
      DBSchema.tableLanguageWords,
      orderBy: 'RANDOM()',
      limit: '1',
    );
    if (rows.isEmpty) {
      return const LanguagePhrase(
        id: 0,
        language: '',
        phrase: '',
        pronunciation: '',
        meaning: '',
        example: '',
        examplePronunciation: '',
      );
    }
    final r = rows.first;
    return LanguagePhrase(
      id: r['id'] as int,
      language: r['language'] as String,
      phrase: r['phrase'] as String,
      pronunciation: (r['pronunciation'] as String?) ?? '',
      meaning: r['meaning'] as String,
      example: (r['example'] as String?) ?? '',
      examplePronunciation: (r['example_pronunciation'] as String?) ?? '',
    );
  }

  /// Devuelve un idiom aleatorio del idioma indicado.
  Future<LanguagePhrase> randomIdiomByLanguage(String language) async {
    final rows = await DBProvider.db.query(
      DBSchema.tableLanguageWords,
      where: 'language = ?',
      whereArgs: [language],
      orderBy: 'RANDOM()',
      limit: '1',
    );
    if (rows.isEmpty) {
      return LanguagePhrase(
        id: 0,
        language: language,
        phrase: 'Sin frases disponibles.',
        pronunciation: '',
        meaning: '',
        example: '',
        examplePronunciation: '',
      );
    }
    final r = rows.first;
    return LanguagePhrase(
      id: r['id'] as int,
      language: r['language'] as String,
      phrase: r['phrase'] as String,
      pronunciation: (r['pronunciation'] as String?) ?? '',
      meaning: r['meaning'] as String,
      example: (r['example'] as String?) ?? '',
      examplePronunciation: (r['example_pronunciation'] as String?) ?? '',
    );
  }

  /// Lista de idiomas disponibles en BD, en el orden de banderas.
  static const List<String> orderedLanguages = [
    '🇬🇧 Inglés',
    '🇮🇹 Italiano',
    '🇵🇹 Portugués',
    '🇫🇷 Francés',
    '🇩🇪 Alemán',
  ];

  /// Extrae solo el emoji de bandera del string de idioma.
  static String flagEmoji(String language) => language.split(' ').first;

  Future<FactItem> randomFact() async {
    final rows = await DBProvider.db.query(
      DBSchema.tableFacts,
      orderBy: 'RANDOM()',
      limit: '1',
    );
    if (rows.isEmpty)
      return const FactItem(
        id: 0,
        text: 'Sin datos disponibles.',
        category: '',
      );
    final r = rows.first;
    return FactItem(
      id: r['id'] as int,
      text: r['text'] as String,
      category: (r['category'] as String?) ?? '',
    );
  }

  // ── Datos: Chistes ────────────────────────────────────────────────────────────

  static final List<Map<String, dynamic>> _jokes = [
    {'text': '¿Qué le dice un bit al otro? Nos vemos en el bus.'},
    {
      'text':
          'El Wi-Fi de casa dejó de funcionar así que tuve que hablar con mi familia. Parecen buena gente.',
    },
    {
      'text':
          '¿Por qué el espantapájaros ganó un premio? Porque era sobresaliente en su campo.',
    },
    {'text': '¿Cómo se despiden los químicos? Ácido un placer.'},
    {
      'text':
          '¿Qué le dijo el semáforo al coche? No me mires que me estoy cambiando.',
    },
    {'text': 'Mi memoria es tan mala que a veces olvido el final de los chis…'},
    {'text': '¿Qué hace una abeja en el gimnasio? ¡Zum-ba!'},
    {
      'text':
          '¿Qué le dice un semáforo a otro? No me mires que me estoy cambiando.',
    },
    {'text': '¿Qué hace un perro con un taladro? ¡Taladrando!'},
    {'text': '¿Qué le dice un techo a otro? Techo de menos.'},
    {'text': '¿Qué le dice un pato a otro? Estamos empatados.'},
    {'text': '¿Qué hace una computadora en la playa? Nada, solo navega.'},
    {
      'text':
          '¿Qué le dice una impresora a otra? ¿Esa hoja es tuya o es una impresión mía?',
    },
    {'text': '¿Qué hace un pez? Nada.'},
    {'text': '¿Qué hace un pez mago? Nada por arte de magia.'},
    {'text': '¿Qué hace un semáforo en una fiesta? Cambia de ambiente.'},
    {'text': '¿Qué hace un gato matemático? ¡Miau-tiplíca!'},
    {'text': '¿Qué le dice un cable a otro? Somos corrientes.'},
    {'text': '¿Qué hace un fantasma en el ascensor? Eleva el espíritu.'},
    {'text': '¿Qué hace un gato en la computadora? Busca el ratón.'},
    {'text': '¿Qué le dice una piedra a otra? Nada, las piedras no hablan.'},
    {'text': '¿Qué hace una vaca cuando sale el sol? Sombra.'},
    {'text': '¿Qué hace un mono con un lápiz? ¡Mono-grafías!'},
    {'text': '¿Qué hace una vaca en un terremoto? ¡Leche batida!'},
    {'text': '¿Qué le dice un camello a otro? ¡Qué jorobado estás hoy!'},
    {'text': '¿Qué hace un canguro en un restaurante? Salta el menú.'},
  ];

  // ── Datos: Frases ─────────────────────────────────────────────────────────────

  static final List<Map<String, dynamic>> _phrases = [
    {
      'text': 'El único modo de hacer un gran trabajo es amar lo que haces.',
      'author': 'Steve Jobs',
    },
    {
      'text':
          'La vida es lo que pasa mientras estás ocupado haciendo otros planes.',
      'author': 'John Lennon',
    },
    {
      'text': 'En medio de la dificultad reside la oportunidad.',
      'author': 'Albert Einstein',
    },
    {
      'text': 'La creatividad es la inteligencia divirtiéndose.',
      'author': 'Albert Einstein',
    },
    {'text': 'Si puedes soñarlo, puedes hacerlo.', 'author': 'Walt Disney'},
    {
      'text':
          'El futuro pertenece a quienes creen en la belleza de sus sueños.',
      'author': 'Eleanor Roosevelt',
    },
    {
      'text': 'Sé el cambio que quieres ver en el mundo.',
      'author': 'Mahatma Gandhi',
    },
    {
      'text':
          'La felicidad de tu vida depende de la calidad de tus pensamientos.',
      'author': 'Marco Aurelio',
    },
    {
      'text': 'El alma se tiñe con el color de sus pensamientos.',
      'author': 'Marco Aurelio',
    },
    {
      'text':
          'No nos atrevemos a muchas cosas porque son difíciles, pero son difíciles porque no nos atrevemos.',
      'author': 'Séneca',
    },
    {'text': 'Mientras vivimos, aprendamos a vivir.', 'author': 'Séneca'},
    {
      'text':
          'La suerte es lo que sucede cuando la preparación se encuentra con la oportunidad.',
      'author': 'Séneca',
    },
    {
      'text': 'No es lo que te ocurre, sino cómo reaccionas lo que importa.',
      'author': 'Epicteto',
    },
    {
      'text': 'La libertad es el poder de vivir como deseas.',
      'author': 'Epicteto',
    },
    {'text': 'La dificultad muestra lo que somos.', 'author': 'Epicteto'},
    {
      'text':
          'Elige un trabajo que te guste y no tendrás que trabajar ni un día de tu vida.',
      'author': 'Confucio',
    },
    {
      'text': 'No importa lo lento que vayas mientras no te detengas.',
      'author': 'Confucio',
    },
    {
      'text': 'Donde hay educación, no hay distinción de clases.',
      'author': 'Confucio',
    },
    {
      'text': 'Las oportunidades se multiplican a medida que se aprovechan.',
      'author': 'Sun Tzu',
    },
    {
      'text': 'La victoria es para quien sabe cuándo luchar y cuándo no.',
      'author': 'Sun Tzu',
    },
    {
      'text':
          'Lo que haces habla tan fuerte que no puedo escuchar lo que dices.',
      'author': 'Ralph Waldo Emerson',
    },
    {
      'text':
          'No vayas por donde el camino te lleve; ve por donde no hay camino y deja un rastro.',
      'author': 'Ralph Waldo Emerson',
    },
    {
      'text': 'La confianza en uno mismo es el primer secreto del éxito.',
      'author': 'Ralph Waldo Emerson',
    },
    {
      'text': 'Ve con confianza en la dirección de tus sueños.',
      'author': 'Henry David Thoreau',
    },
    {
      'text':
          'Lo que un hombre piensa de sí mismo es lo que determina su destino.',
      'author': 'Henry David Thoreau',
    },
    {
      'text': 'La energía y la persistencia conquistan todas las cosas.',
      'author': 'Benjamin Franklin',
    },
    {
      'text': 'Bien hecho es mejor que bien dicho.',
      'author': 'Benjamin Franklin',
    },
    {
      'text': 'La inversión en conocimiento paga el mejor interés.',
      'author': 'Benjamin Franklin',
    },
    {
      'text': 'Un viaje de mil millas comienza con un solo paso.',
      'author': 'Lao-Tsé',
    },
    {
      'text': 'La paciencia es amargura, pero su fruto es dulce.',
      'author': 'Lao-Tsé',
    },
    {
      'text': 'Dominar a otros es fuerza; dominarse a uno mismo es poder.',
      'author': 'Lao-Tsé',
    },
    {
      'text':
          'No habites en el pasado, no sueñes con el futuro; concentra la mente en el presente.',
      'author': 'Buda',
    },
    {
      'text': 'La mente lo es todo. En lo que piensas, te conviertes.',
      'author': 'Buda',
    },
    {'text': 'La paz viene de dentro; no la busques fuera.', 'author': 'Buda'},
    {
      'text': 'La mayor victoria es conquistarse a uno mismo.',
      'author': 'Platón',
    },
    {
      'text': 'El principio es la parte más importante del trabajo.',
      'author': 'Platón',
    },
    {
      'text':
          'Somos lo que hacemos repetidamente. La excelencia, entonces, no es un acto, sino un hábito.',
      'author': 'Aristóteles',
    },
  ];

  // ── Datos: Idiomas — frases hechas con pronunciación ─────────────────────────

  static final List<Map<String, dynamic>> _idioms = [
    // ── 🇬🇧 Inglés ──────────────────────────────────────────────────────────────
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'Break a leg',
      'pronunciation': 'breik a leg',
      'meaning': 'Buena suerte.',
      'example': 'You have an important presentation today — break a leg!',
      'example_pronunciation':
          'yu jav an importánt presenteishon tudei — breik a leg',
    },
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'Piece of cake',
      'pronunciation': 'pís of keik',
      'meaning': 'Algo muy fácil.',
      'example': 'Don\'t worry about the test, it will be a piece of cake.',
      'example_pronunciation':
          'dont wóri abáut de test, it uil bi a pís of keik',
    },
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'Hit the nail on the head',
      'pronunciation': 'jit de neyl on de jed',
      'meaning': 'Dar en el clavo.',
      'example':
          'When you said we need more time, you hit the nail on the head.',
      'example_pronunciation':
          'wen yu sed wi nid mor taim, yu jit de neyl on de jed',
    },
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'Under the weather',
      'pronunciation': 'ánder de wéder',
      'meaning': 'Sentirse mal o enfermo.',
      'example': 'I\'m feeling a bit under the weather today.',
      'example_pronunciation': 'aim fíling a bit ánder de wéder tudei',
    },
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'Once in a blue moon',
      'pronunciation': 'uans in a blu mun',
      'meaning': 'Algo que ocurre muy rara vez.',
      'example': 'We go out for dinner together once in a blue moon.',
      'example_pronunciation':
          'wi gou aut for díner toguéder uans in a blu mun',
    },
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'The ball is in your court',
      'pronunciation': 'de bol is in yor kort',
      'meaning': 'Te toca decidir o actuar.',
      'example': 'I\'ve done everything I can — now the ball is in your court.',
      'example_pronunciation':
          'aiv don évrizin ai can — nau de bol is in yor kort',
    },
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'Bite the bullet',
      'pronunciation': 'bait de búlet',
      'meaning': 'Aceptar hacer algo difícil o desagradable.',
      'example': 'I didn\'t want to do it, but I had to bite the bullet.',
      'example_pronunciation':
          'ai dírent uant tu du it, bat ai jad tu bait de búlet',
    },
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'Spill the beans',
      'pronunciation': 'spil de bins',
      'meaning': 'Revelar un secreto.',
      'example': 'Come on, spill the beans! What happened at the party?',
      'example_pronunciation': 'com on, spil de bins! uat japend at de párti',
    },
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'Cost an arm and a leg',
      'pronunciation': 'cost an arm and a leg',
      'meaning': 'Costar muy caro.',
      'example': 'That car costs an arm and a leg.',
      'example_pronunciation': 'dat car costs an arm and a leg',
    },
    {
      'language': '🇬🇧 Inglés',
      'phrase': 'It\'s raining cats and dogs',
      'pronunciation': 'its réining cats and dogs',
      'meaning': 'Está lloviendo a cántaros.',
      'example': 'Take an umbrella — it\'s raining cats and dogs out there.',
      'example_pronunciation':
          'teik an ámbrela — its réining cats and dogs aut der',
    },
    // ── 🇮🇹 Italiano ───────────────────────────────────────────────────────────
    {
      'language': '🇮🇹 Italiano',
      'phrase': 'In bocca al lupo',
      'pronunciation': 'in bócca al lúpo',
      'meaning': 'Buena suerte (lit. "en la boca del lobo").',
      'example': 'Hai l\'esame domani — in bocca al lupo!',
      'example_pronunciation': 'ái lezáme dománi — in bócca al lúpo',
    },
    {
      'language': '🇮🇹 Italiano',
      'phrase': 'Avere le mani in pasta',
      'pronunciation': 'avére le máni in pásta',
      'meaning':
          'Estar metido en un asunto (lit. "tener las manos en la masa").',
      'example': 'Ha le mani in pasta in quel progetto.',
      'example_pronunciation': 'a le máni in pásta in kuel prodyétto',
    },
    {
      'language': '🇮🇹 Italiano',
      'phrase': 'Costare un occhio della testa',
      'pronunciation': 'kostáre un ókio déla tésta',
      'meaning': 'Costar un ojo de la cara.',
      'example': 'Queste scarpe costano un occhio della testa!',
      'example_pronunciation': 'kuéste skárpe kostano un ókio déla tésta',
    },
    {
      'language': '🇮🇹 Italiano',
      'phrase': 'Non tutte le ciambelle riescono col buco',
      'pronunciation': 'non tútte le ciambélle riéscono col búco',
      'meaning':
          'No todo sale siempre perfecto (lit. "no todos los donuts tienen agujero").',
      'example':
          'Ho sbagliato la ricetta — non tutte le ciambelle riescono col buco.',
      'example_pronunciation':
          'o zbalyáto la rikétta — non tútte le ciambélle riéscono col búco',
    },
    {
      'language': '🇮🇹 Italiano',
      'phrase': 'Tra il dire e il fare c\'è di mezzo il mare',
      'pronunciation': 'tra il díre e il fáre ché di médzo il máre',
      'meaning': 'Del dicho al hecho hay un gran trecho.',
      'example':
          'Vuoi correre una maratona? Tra il dire e il fare c\'è di mezzo il mare.',
      'example_pronunciation':
          'vuói koréere una maratóna? tra il díre e il fáre ché di médzo il máre',
    },
    // ── 🇵🇹 Portugués ──────────────────────────────────────────────────────────
    {
      'language': '🇵🇹 Portugués',
      'phrase': 'Chutar o balde',
      'pronunciation': 'shutar u bálchi',
      'meaning': 'Rendirse o abandonar (lit. "patear el cubo").',
      'example': 'Depois de tanto esforço, ele chutou o balde.',
      'example_pronunciation': 'depóis de tantu esforsu, eli shutou u bálchi',
    },
    {
      'language': '🇵🇹 Portugués',
      'phrase': 'Pagar o pato',
      'pronunciation': 'pagár u pátu',
      'meaning': 'Cargar con las culpas / pagar los platos rotos.',
      'example': 'Ele não fez nada mas pagou o pato.',
      'example_pronunciation': 'éli nãu fez náda mas pagóu u pátu',
    },
    {
      'language': '🇵🇹 Portugués',
      'phrase': 'Quem não arrisca não petisca',
      'pronunciation': 'kéi nãu aríska nãu petíska',
      'meaning':
          'Quien no arriesga no gana (lit. "quien no arriesga no pica").',
      'example': 'Vai lá pedir aumento — quem não arrisca não petisca!',
      'example_pronunciation':
          'vai lá pedir auméntu — kéi nãu aríska nãu petíska',
    },
    {
      'language': '🇵🇹 Portugués',
      'phrase': 'Água mole em pedra dura, tanto bate até que fura',
      'pronunciation': 'água mólë éi pédra dúra, tantu báti até ki fúra',
      'meaning':
          'La constancia todo lo vence (lit. "el agua blanda en piedra dura, tanto golpea hasta que perfora").',
      'example': 'Continuou a treinar e conseguiu — água mole em pedra dura!',
      'example_pronunciation':
          'kontinuóu a treinar i konsegiú — água mólë éi pédra dúra',
    },
    {
      'language': '🇵🇹 Portugués',
      'phrase': 'Fazer das tripas coração',
      'pronunciation': 'fazér das trípas corasão',
      'meaning': 'Hacer de tripas corazón / esforzarse al máximo.',
      'example': 'Estava cansado, mas fez das tripas coração e terminou.',
      'example_pronunciation':
          'eshtáva kansádu, mas féz das trípas corasão i terminóu',
    },
    // ── 🇫🇷 Francés ────────────────────────────────────────────────────────────
    {
      'language': '🇫🇷 Francés',
      'phrase': 'Casser les pieds',
      'pronunciation': 'kasé lé pyé',
      'meaning': 'Molestar o fastidiar (lit. "romper los pies").',
      'example': 'Arrête de me casser les pieds avec ça!',
      'example_pronunciation': 'arét de me kasé lé pyé avék sa',
    },
    {
      'language': '🇫🇷 Francés',
      'phrase': 'Avoir le cafard',
      'pronunciation': 'avwár le kafár',
      'meaning': 'Estar deprimido o con bajón (lit. "tener la cucaracha").',
      'example': 'Depuis lundi j\'ai le cafard.',
      'example_pronunciation': 'depüí lündi yé le kafár',
    },
    {
      'language': '🇫🇷 Francés',
      'phrase': 'Poser un lapin',
      'pronunciation': 'pozé ün lapán',
      'meaning': 'Dar plantón a alguien (lit. "dejarle un conejo").',
      'example': 'Elle m\'a posé un lapin hier soir.',
      'example_pronunciation': 'él ma pozé ün lapán yér swár',
    },
    {
      'language': '🇫🇷 Francés',
      'phrase':
          'Il ne faut pas vendre la peau de l\'ours avant de l\'avoir tué',
      'pronunciation': 'il ne fó pa vandr la pó de lúrs aván de lavwár tüé',
      'meaning': 'No vender la piel del oso antes de cazarlo.',
      'example': 'On n\'a pas encore gagné — ne vends pas la peau de l\'ours!',
      'example_pronunciation': 'on na pa ankór gañé — ne van pa la pó de lúrs',
    },
    {
      'language': '🇫🇷 Francés',
      'phrase': 'Avoir d\'autres chats à fouetter',
      'pronunciation': 'avwár dótr shá a fueté',
      'meaning':
          'Tener cosas más importantes que hacer (lit. "tener otros gatos que azotar").',
      'example': 'Je n\'ai pas le temps — j\'ai d\'autres chats à fouetter.',
      'example_pronunciation': 'ye né pa le tan — yé dótr shá a fueté',
    },
    // ── 🇩🇪 Alemán ─────────────────────────────────────────────────────────────
    {
      'language': '🇩🇪 Alemán',
      'phrase': 'Ich drücke dir die Daumen',
      'pronunciation': 'ij drücke dir di dáumen',
      'meaning': 'Te deseo suerte (lit. "te aprieto los pulgares").',
      'example':
          'Du hast morgen ein Vorstellungsgespräch? Ich drücke dir die Daumen!',
      'example_pronunciation':
          'du jast mórgen ain forshtelungs-geshprech? ij drücke dir di dáumen',
    },
    {
      'language': '🇩🇪 Alemán',
      'phrase': 'Tomaten auf den Augen haben',
      'pronunciation': 'tomáten auf den áugen háben',
      'meaning': 'No ver lo obvio (lit. "tener tomates en los ojos").',
      'example': 'Siehst du das nicht? Du hast wohl Tomaten auf den Augen!',
      'example_pronunciation':
          'zist du das nijt? du jast vol tomáten auf den áugen',
    },
    {
      'language': '🇩🇪 Alemán',
      'phrase': 'Das ist nicht mein Bier',
      'pronunciation': 'das ist nijt main bier',
      'meaning': 'No es asunto mío (lit. "eso no es mi cerveza").',
      'example': 'Was er macht, ist nicht mein Bier.',
      'example_pronunciation': 'vas er majt, ist nijt main bier',
    },
    {
      'language': '🇩🇪 Alemán',
      'phrase': 'Alles hat ein Ende, nur die Wurst hat zwei',
      'pronunciation': 'áles jat ain énde, nur di vurst jat tsvai',
      'meaning':
          'Todo tiene un final (lit. "todo tiene un extremo, solo el salchichón tiene dos").',
      'example':
          'Die Prüfungen sind vorbei — alles hat ein Ende, nur die Wurst hat zwei!',
      'example_pronunciation':
          'di prüfungen zind forbai — áles jat ain énde, nur di vurst jat tsvai',
    },
    {
      'language': '🇩🇪 Alemán',
      'phrase': 'Eulen nach Athen tragen',
      'pronunciation': 'óilen naj atén trágen',
      'meaning': 'Llevar leña al monte (lit. "llevar búhos a Atenas").',
      'example':
          'Ich erkläre dir das nicht — das wäre Eulen nach Athen tragen.',
      'example_pronunciation':
          'ij erkléere dir das nijt — das vére óilen naj atén trágen',
    },
  ];

  // ── Datos: Hechos interesantes ────────────────────────────────────────────────

  static final List<Map<String, dynamic>> _facts = [
    {
      'text':
          'Los pulpos tienen tres corazones y su sangre es de color azul debido a la hemocianina, una proteína que contiene cobre.',
      'category': '🐙 Animales',
    },
    {
      'text':
          'Un rayo cae en la Tierra aproximadamente 100 veces por segundo, lo que equivale a unos 8 millones de rayos al día.',
      'category': '⚡ Naturaleza',
    },
    {
      'text':
          'El ADN humano es un 60% idéntico al de una banana. El 98,7% de nuestro ADN coincide con el de los chimpancés.',
      'category': '🧬 Ciencia',
    },
    {
      'text':
          'Cleopatra vivió más cerca en el tiempo de la llegada del ser humano a la Luna que de la construcción de las Pirámides de Giza.',
      'category': '🏛️ Historia',
    },
    {
      'text':
          'Una cucharadita de estrella de neutrones pesa aproximadamente mil millones de toneladas debido a su densidad extrema.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'Hay más estrellas en el universo observable que granos de arena en todas las playas y desiertos de la Tierra.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'El agua caliente puede congelarse más rápido que el agua fría en ciertas condiciones. Este fenómeno se llama efecto Mpemba.',
      'category': '🧪 Ciencia',
    },
    {
      'text':
          'Las hormigas pueden levantar entre 10 y 50 veces su propio peso corporal, dependiendo de la especie.',
      'category': '🐜 Animales',
    },
    {
      'text':
          'El número de bacterias en tu cuerpo supera al número de células humanas. Convives con billones de microorganismos.',
      'category': '🧬 Cuerpo humano',
    },
    {
      'text':
          'La Gran Muralla China no es visible a simple vista desde el espacio. Este mito fue popularizado antes de que hubiera astronautas.',
      'category': '🏛️ Historia',
    },
    {
      'text':
          'Venus gira en sentido contrario a la mayoría de los planetas del sistema solar, y un día venusiano dura más que su año.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'Los tiburones son más antiguos que los árboles. Los tiburones llevan 450 millones de años en la Tierra; los árboles solo 350 millones.',
      'category': '🦈 Animales',
    },
    {
      'text':
          'En Japón existe el "síndrome de París": una condición psicológica que afecta a turistas que se sienten decepcionados al descubrir que París no es como la imaginaban.',
      'category': '🌍 Curiosidades',
    },
    {
      'text':
          'El chocolate fue utilizado como moneda por los mayas y aztecas. Las semillas de cacao eran tan valiosas que se falsificaban.',
      'category': '🍫 Curiosidades',
    },
    {
      'text':
          'Oxford University es más antigua que el Imperio Azteca. La universidad comenzó a impartir clases en 1096; los aztecas fundaron Tenochtitlán en 1325.',
      'category': '🏛️ Historia',
    },
    {
      'text':
          'El cerebro humano genera suficiente electricidad mientras está despierto como para encender una bombilla de baja energía.',
      'category': '🧠 Cuerpo humano',
    },
    {
      'text':
          'El corazón humano late aproximadamente 100 000 veces al día y bombea unos 7 500 litros de sangre.',
      'category': '🧠 Cuerpo humano',
    },
    {
      'text':
          'Los flamencos son rosados porque comen carotenoides presentes en algas y crustáceos. En cautiverio, sin esa dieta, se vuelven blancos.',
      'category': '🦩 Animales',
    },
    {
      'text':
          'El sonido no puede viajar en el vacío. En el espacio, nadie puede oírte gritar.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'El idioma más antiguo escrito que aún se habla es el griego, con registros de escritura de más de 3 000 años.',
      'category': '📚 Cultura',
    },
  ];
}
