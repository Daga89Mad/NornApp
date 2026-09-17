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
    {'text': '¿Cuál es el café más peligroso? El ex-preso.'},
    {'text': '¿Qué le dijo una pared a otra pared? Nos vemos en la esquina.'},
    {'text': '¿Cuál es el último animal que subió al arca de Noé? El del-fin.'},
    {
      'text':
          '¿Qué le dice un gusano a otro gusano? Voy a dar una vuelta a la manzana.',
    },
    {
      'text':
          '¿Cuál es el animal más antiguo? La cebra, porque está en blanco y negro.',
    },
    {
      'text':
          '¿Qué le dice una pulga a otra pulga? ¿Vamos andando o esperamos al perro?',
    },
    {
      'text':
          '¿Tiene platos del día? Sí. Pues déme uno de ayer, que estará más barato.',
    },
    {
      'text':
          'Papá, ¿qué se siente al tener un hijo tan guapo? No lo sé, pregúntale a tu abuelo.',
    },
    {
      'text':
          'Papá, ¿me haces los deberes? No, hijo, eso estaría mal. Bueno, inténtalo igualmente.',
    },
    {
      'text':
          'Mamá, ¿qué haces delante del ordenador con los ojos cerrados? Windows me dijo que cerrara las pestañas.',
    },
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
    {
      'text':
          'La opinión es el punto medio entre el conocimiento y la ignorancia.',
      'author': 'Platón',
    },
    {
      'text': 'Pensar es el diálogo del alma consigo misma.',
      'author': 'Platón',
    },
    {
      'text':
          'No hay viento favorable para quien no sabe a qué puerto se dirige.',
      'author': 'Séneca',
    },
    {
      'text': 'No es pobre quien tiene poco, sino quien desea mucho.',
      'author': 'Séneca',
    },
    {
      'text': 'Sufrimos más en la imaginación que en la realidad.',
      'author': 'Séneca',
    },
    {'text': 'La vida es larga si sabes cómo usarla.', 'author': 'Séneca'},
    {
      'text':
          'Saber lo que sabes y saber lo que no sabes: eso es conocimiento.',
      'author': 'Confucio',
    },
    {
      'text':
          'Si conoces al enemigo y te conoces a ti mismo, no debes temer el resultado de cien batallas.',
      'author': 'Sun Tzu',
    },
    {
      'text': 'La suprema excelencia consiste en vencer al enemigo sin luchar.',
      'author': 'Sun Tzu',
    },
    {
      'text': 'En medio del caos también existe la oportunidad.',
      'author': 'Sun Tzu',
    },
    {'text': 'El conocimiento es poder.', 'author': 'Francis Bacon'},
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
    {
      'text':
          'Las nutrias marinas pueden cogerse de las patas mientras flotan para evitar separarse unas de otras con las corrientes.',
      'category': '🦦 Animales',
    },
    {
      'text':
          'Los koalas tienen huellas dactilares tan parecidas a las humanas que pueden resultar difíciles de distinguir a simple vista.',
      'category': '🐨 Animales',
    },
    {
      'text':
          'Los pulpos pueden cambiar rápidamente el color y la textura aparente de su piel para camuflarse o comunicarse.',
      'category': '🐙 Animales',
    },
    {
      'text':
          'Los elefantes pueden comunicarse mediante sonidos de frecuencia muy baja que recorren varios kilómetros.',
      'category': '🐘 Animales',
    },
    {
      'text':
          'Las jirafas tienen siete vértebras cervicales, el mismo número que los seres humanos, aunque cada una es mucho más larga.',
      'category': '🦒 Animales',
    },
    {
      'text':
          'Los caballitos de mar machos son los que llevan los embriones en una bolsa incubadora y posteriormente dan a luz.',
      'category': '🐠 Animales',
    },
    {
      'text':
          'En Mercurio, un día solar dura aproximadamente 176 días terrestres, mientras que su año dura solo unos 88 días terrestres.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'La luz del Sol tarda aproximadamente 8 minutos y 20 segundos en llegar hasta la Tierra.',
      'category': '☀️ Espacio',
    },
    {
      'text':
          'Júpiter es tan grande que en su interior cabrían más de mil planetas del tamaño de la Tierra por volumen.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'Saturno tiene una densidad media menor que la del agua, aunque obviamente no existe un océano suficientemente grande para hacerlo flotar.',
      'category': '🪐 Espacio',
    },
    {
      'text':
          'Marte alberga el Olympus Mons, el volcán más grande conocido del sistema solar, con más de 20 kilómetros de altura respecto a las llanuras circundantes.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'La Luna se aleja de la Tierra aproximadamente 3,8 centímetros cada año debido a las interacciones de las mareas.',
      'category': '🌙 Espacio',
    },
    {
      'text':
          'Urano gira prácticamente tumbado: su eje de rotación está inclinado unos 98 grados respecto al plano de su órbita.',
      'category': '🪐 Espacio',
    },
    {
      'text':
          'Neptuno posee algunos de los vientos más rápidos registrados en el sistema solar, que pueden superar los 2 000 kilómetros por hora.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'En la Luna las huellas de los astronautas pueden permanecer durante millones de años porque prácticamente no hay viento ni lluvia que las erosionen.',
      'category': '🌙 Espacio',
    },
    {
      'text':
          'El Sol concentra aproximadamente el 99,8% de toda la masa del sistema solar.',
      'category': '☀️ Espacio',
    },
    {
      'text':
          'Un año luz no es una medida de tiempo, sino de distancia: equivale a unos 9,46 billones de kilómetros.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'La Estación Espacial Internacional tarda aproximadamente 90 minutos en completar una vuelta alrededor de la Tierra.',
      'category': '🚀 Espacio',
    },
    {
      'text':
          'La montaña más alta de la Tierra medida desde su base es Mauna Kea, en Hawái, si se incluye la parte que se encuentra bajo el océano.',
      'category': '🌍 Naturaleza',
    },
    {
      'text':
          'La Antártida es técnicamente el desierto más grande del planeta porque recibe muy pocas precipitaciones.',
      'category': '❄️ Naturaleza',
    },
    {
      'text':
          'Alrededor del 71% de la superficie de la Tierra está cubierta por agua.',
      'category': '🌊 Naturaleza',
    },
    {
      'text':
          'La mayor parte del agua dulce de la Tierra se encuentra almacenada en glaciares, capas de hielo y aguas subterráneas.',
      'category': '🌊 Naturaleza',
    },
    {
      'text':
          'El océano Pacífico es el océano más grande de la Tierra y ocupa una superficie mayor que todas las masas terrestres combinadas.',
      'category': '🌊 Naturaleza',
    },
    {
      'text':
          'La fosa de las Marianas contiene el punto oceánico conocido más profundo de la Tierra, a casi 11 kilómetros bajo el nivel del mar.',
      'category': '🌊 Naturaleza',
    },
    {
      'text':
          'Los continentes se desplazan unos pocos centímetros cada año debido al movimiento de las placas tectónicas.',
      'category': '🌍 Naturaleza',
    },
    {
      'text':
          'Los rayos pueden calentar el aire que los rodea hasta temperaturas cercanas a los 30 000 grados Celsius durante un instante.',
      'category': '⚡ Naturaleza',
    },
    {
      'text':
          'Un arcoíris completo tiene forma circular, aunque desde el suelo normalmente solo vemos una parte debido al horizonte.',
      'category': '🌈 Naturaleza',
    },
    {
      'text':
          'Los copos de nieve desarrollan estructuras de seis lados debido a la forma en que se organizan las moléculas de agua al congelarse.',
      'category': '❄️ Naturaleza',
    },
    {
      'text':
          'El olor característico que aparece después de la lluvia sobre suelo seco se conoce como petricor.',
      'category': '🌧️ Naturaleza',
    },
    {
      'text':
          'Los árboles pueden intercambiar nutrientes y señales químicas mediante redes subterráneas en las que participan sus raíces y determinados hongos.',
      'category': '🌳 Naturaleza',
    },
    {
      'text':
          'El cuerpo humano adulto posee normalmente 206 huesos, aunque los bebés nacen con un número mayor que posteriormente se fusiona.',
      'category': '🧠 Cuerpo humano',
    },
    {
      'text':
          'La piel es el órgano más grande del cuerpo humano y actúa como una importante barrera frente al entorno.',
      'category': '🧠 Cuerpo humano',
    },
    {
      'text':
          'El intestino delgado de un adulto mide aproximadamente entre 5 y 7 metros, aunque su longitud varía entre personas.',
      'category': '🧠 Cuerpo humano',
    },
    {
      'text':
          'Los glóbulos rojos humanos maduros no tienen núcleo, lo que deja más espacio para transportar hemoglobina.',
      'category': '🩸 Cuerpo humano',
    },
    {
      'text':
          'El esmalte dental es el tejido más duro del cuerpo humano, aunque puede deteriorarse por ácidos y desgaste.',
      'category': '🦷 Cuerpo humano',
    },
    {
      'text':
          'El cerebro humano contiene alrededor de 86 000 millones de neuronas.',
      'category': '🧠 Cuerpo humano',
    },
    {
      'text':
          'La Universidad de Bolonia, fundada en el siglo XI, es considerada generalmente la universidad más antigua del mundo occidental que continúa en funcionamiento.',
      'category': '📚 Historia',
    },
    {
      'text':
          'Los vikingos llegaron a América del Norte alrededor del año 1000, varios siglos antes de los viajes de Cristóbal Colón.',
      'category': '🏛️ Historia',
    },
    {
      'text':
          'Durante gran parte de la historia, el color púrpura fue extremadamente caro porque algunos pigmentos se obtenían a partir de miles de moluscos marinos.',
      'category': '🏛️ Historia',
    },
    {
      'text':
          'La palabra "robot" procede del término checo "robota", relacionado históricamente con el trabajo forzado.',
      'category': '🤖 Tecnología',
    },
    {
      'text':
          'El primer mensaje enviado a través de ARPANET en 1969 debía ser "LOGIN", pero el sistema falló después de transmitir únicamente las letras "LO".',
      'category': '💻 Tecnología',
    },
    {
      'text':
          'El código QR fue desarrollado originalmente en Japón en la década de 1990 para rastrear componentes durante la fabricación de automóviles.',
      'category': '📱 Tecnología',
    },
    {
      'text':
          'Bluetooth recibió su nombre del rey Harald Bluetooth, conocido por haber contribuido a unificar Dinamarca y Noruega.',
      'category': '📱 Tecnología',
    },
    {
      'text':
          'El primer disco duro comercial de IBM, presentado en 1956, almacenaba alrededor de 5 megabytes y ocupaba un espacio comparable al de grandes armarios.',
      'category': '💾 Tecnología',
    },
    {
      'text':
          'Una fotografía digital está formada por pequeños elementos llamados píxeles, cada uno de los cuales almacena información relacionada con el color y la luminosidad.',
      'category': '💻 Tecnología',
    },
    {
      'text':
          'La velocidad de la luz en el vacío es de aproximadamente 299 792 kilómetros por segundo.',
      'category': '🧪 Ciencia',
    },
    {
      'text':
          'El sonido viaja más rápido a través del agua que a través del aire porque las partículas están mucho más próximas entre sí.',
      'category': '🧪 Ciencia',
    },
    {
      'text':
          'El diamante y el grafito están formados por carbono, pero sus átomos están organizados de maneras diferentes y por eso sus propiedades son muy distintas.',
      'category': '🧪 Ciencia',
    },
    {
      'text':
          'La temperatura más baja posible según la física es el cero absoluto, equivalente a -273,15 grados Celsius.',
      'category': '🧪 Ciencia',
    },
    {
      'text':
          'Los átomos están formados en su mayor parte por espacio vacío entre el núcleo y los electrones.',
      'category': '⚛️ Ciencia',
    },
    {
      'text':
          'La tabla periódica organiza los elementos químicos principalmente según su número atómico, es decir, el número de protones de su núcleo.',
      'category': '⚛️ Ciencia',
    },
    {
      'text':
          'El símbolo @ existía siglos antes de la creación del correo electrónico y se utilizaba en documentos comerciales.',
      'category': '📚 Curiosidades',
    },
    {
      'text':
          'La palabra "alfabeto" procede de los nombres de las dos primeras letras griegas: alfa y beta.',
      'category': '📚 Cultura',
    },
    {
      'text':
          'El mandarín es el idioma con mayor número de hablantes nativos del mundo.',
      'category': '📚 Cultura',
    },
    {
      'text':
          'El español pertenece a la familia de las lenguas romances y evolucionó principalmente a partir del latín hablado en la península ibérica.',
      'category': '📚 Cultura',
    },
    {
      'text':
          'La bandera de Nepal es la única bandera nacional moderna que no tiene forma rectangular.',
      'category': '🌍 Curiosidades',
    },
    {
      'text':
          'Rusia se extiende por once zonas horarias, más que cualquier otro país del mundo.',
      'category': '🌍 Geografía',
    },
    {
      'text':
          'África es el único continente atravesado tanto por el ecuador como por los dos trópicos.',
      'category': '🌍 Geografía',
    },
    {
      'text':
          'Canadá posee una costa más larga que la de cualquier otro país del mundo.',
      'category': '🌍 Geografía',
    },
    {
      'text':
          'El lago Baikal, en Siberia, es el lago de agua dulce más profundo del mundo y contiene alrededor de una quinta parte del agua dulce superficial no congelada del planeta.',
      'category': '🌍 Geografía',
    },
    {
      'text':
          'La cordillera de los Andes es la cadena montañosa continental más larga del mundo y recorre gran parte del oeste de Sudamérica.',
      'category': '🌍 Geografía',
    },
    {
      'text':
          'El Sahara no siempre fue un desierto: en diferentes periodos del pasado tuvo lagos, ríos y extensas zonas de vegetación.',
      'category': '🌍 Historia natural',
    },
    {
      'text':
          'Los primeros seres humanos modernos aparecieron cientos de miles de años antes de que comenzara la construcción de las grandes ciudades y civilizaciones.',
      'category': '🏛️ Historia',
    },
    {
      'text':
          'Los dinosaurios no avianos desaparecieron hace unos 66 millones de años, pero las aves actuales son descendientes directos de dinosaurios terópodos.',
      'category': '🦖 Animales',
    },
    {
      'text':
          'El Tyrannosaurus rex vivió más cerca en el tiempo de los seres humanos actuales que del Stegosaurus.',
      'category': '🦖 Historia natural',
    },
    {
      'text':
          'Algunas especies de medusas del género Turritopsis pueden regresar a una fase juvenil de su ciclo vital después de alcanzar la madurez.',
      'category': '🪼 Animales',
    },
    {
      'text':
          'Los axolotes pueden regenerar extremidades y reparar partes de órganos y tejidos sin formar cicatrices como las que aparecen normalmente en los mamíferos.',
      'category': '🦎 Animales',
    },
    {
      'text':
          'Los tardígrados pueden sobrevivir a condiciones extremas entrando en un estado de actividad metabólica extremadamente reducida llamado criptobiosis.',
      'category': '🔬 Animales',
    },
    {
      'text':
          'Las estrellas de mar no tienen un cerebro centralizado como los vertebrados; poseen un sistema nervioso distribuido por su cuerpo.',
      'category': '⭐ Animales',
    },
    {
      'text':
          'Las serpientes utilizan su lengua bífida para recoger partículas químicas del entorno y analizarlas mediante el órgano vomeronasal.',
      'category': '🐍 Animales',
    },
    {
      'text':
          'Los búhos pueden girar la cabeza hasta unos 270 grados gracias a adaptaciones especiales de sus vértebras y vasos sanguíneos.',
      'category': '🦉 Animales',
    },
    {
      'text':
          'Los pingüinos emperador machos incuban el huevo sobre sus patas durante el invierno antártico mientras las hembras regresan al océano para alimentarse.',
      'category': '🐧 Animales',
    },
    {
      'text':
          'Los cocodrilos llevan existiendo en formas similares desde mucho antes de la extinción de los dinosaurios no avianos.',
      'category': '🐊 Animales',
    },
    {
      'text':
          'Las vacas forman relaciones sociales y pueden mostrar preferencias claras por determinados individuos de su grupo.',
      'category': '🐄 Animales',
    },
    {
      'text':
          'Los loros no solo pueden imitar sonidos humanos; algunas especies son capaces de asociar determinadas palabras con objetos, colores o cantidades.',
      'category': '🦜 Animales',
    },
    {
      'text':
          'La lengua de una ballena azul puede pesar aproximadamente lo mismo que un elefante pequeño.',
      'category': '🐋 Animales',
    },
  ];
}
