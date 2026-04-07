// lib/views/fun_day_sheet.dart

import 'package:flutter/material.dart';
import '../core/fun_content_repository.dart';

class FunDaySheet extends StatefulWidget {
  const FunDaySheet({Key? key}) : super(key: key);

  @override
  State<FunDaySheet> createState() => _FunDaySheetState();
}

class _FunDaySheetState extends State<FunDaySheet> {
  String? _mode;
  bool _loading = false;
  JokeItem? _joke;
  PhraseItem? _phrase;
  LanguagePhrase? _idiom;
  String _selectedLanguage = '🇬🇧 Inglés'; // idioma por defecto
  FactItem? _fact;

  // ── Loaders ────────────────────────────────────────────────────────────────

  Future<void> _loadJoke() async {
    setState(() {
      _mode = 'joke';
      _loading = true;
    });
    final v = await FunContentRepository.instance.randomJoke();
    if (mounted)
      setState(() {
        _joke = v;
        _loading = false;
      });
  }

  Future<void> _loadPhrase() async {
    setState(() {
      _mode = 'phrase';
      _loading = true;
    });
    final v = await FunContentRepository.instance.randomPhrase();
    if (mounted)
      setState(() {
        _phrase = v;
        _loading = false;
      });
  }

  Future<void> _loadIdiom({String? language}) async {
    final lang = language ?? _selectedLanguage;
    setState(() {
      _mode = 'language';
      _loading = true;
      _selectedLanguage = lang;
    });
    final v = await FunContentRepository.instance.randomIdiomByLanguage(lang);
    if (mounted)
      setState(() {
        _idiom = v;
        _loading = false;
      });
  }

  Future<void> _loadFact() async {
    setState(() {
      _mode = 'fact';
      _loading = true;
    });
    final v = await FunContentRepository.instance.randomFact();
    if (mounted)
      setState(() {
        _fact = v;
        _loading = false;
      });
  }

  void _goBack() => setState(() {
    _mode = null;
    _joke = null;
    _phrase = null;
    _idiom = null;
    _fact = null;
  });

  // ── Título según modo ──────────────────────────────────────────────────────

  String _modeTitle() {
    switch (_mode) {
      case 'joke':
        return '😂 Chiste del día';
      case 'phrase':
        return '💬 Frase del día';
      case 'language':
        return '🌍 Aprende idiomas';
      case 'fact':
        return '🤯 Dato interesante';
      default:
        return '😄 ¿Qué quieres hoy?';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Asa
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Cabecera
          Row(
            children: [
              if (_mode != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: _goBack,
                  tooltip: 'Volver',
                ),
              Expanded(
                child: Text(
                  _modeTitle(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: _mode == null ? TextAlign.center : TextAlign.start,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Contenido
          if (_mode == null) _buildMenu(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(),
            ),
          if (!_loading) ...[
            if (_mode == 'joke' && _joke != null) _buildJokeCard(),
            if (_mode == 'phrase' && _phrase != null) _buildPhraseCard(),
            if (_mode == 'language' && _idiom != null) _buildIdiomCard(),
            if (_mode == 'fact' && _fact != null) _buildFactCard(),
          ],
        ],
      ),
    );
  }

  // ── Menú ───────────────────────────────────────────────────────────────────

  Widget _buildMenu() {
    return Column(
      children: [
        _MenuButton(
          emoji: '😂',
          label: 'Chiste del día',
          subtitle: 'Un chiste para alegrar la jornada',
          color: Colors.amber.shade600,
          onTap: _loadJoke,
        ),
        const SizedBox(height: 10),
        _MenuButton(
          emoji: '💬',
          label: 'Frase del día',
          subtitle: 'Inspiración de grandes mentes',
          color: Colors.indigo.shade500,
          onTap: _loadPhrase,
        ),
        const SizedBox(height: 10),
        _MenuButton(
          emoji: '🌍',
          label: 'Aprende idiomas',
          subtitle: 'Una frase hecha con pronunciación',
          color: Colors.teal.shade600,
          onTap: () => _loadIdiom(),
        ),
        const SizedBox(height: 10),
        _MenuButton(
          emoji: '🤯',
          label: 'Dato interesante',
          subtitle: 'Aprende algo nuevo hoy',
          color: Colors.deepPurple.shade500,
          onTap: _loadFact,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Chiste ─────────────────────────────────────────────────────────────────

  Widget _buildJokeCard() => _ContentCard(
    color: Colors.amber.shade50,
    border: Colors.amber.shade300,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_joke!.text, style: const TextStyle(fontSize: 16, height: 1.5)),
        const SizedBox(height: 16),
        _AnotherButton(color: Colors.amber.shade600, onTap: _loadJoke),
      ],
    ),
  );

  // ── Frase ──────────────────────────────────────────────────────────────────

  Widget _buildPhraseCard() => _ContentCard(
    color: Colors.indigo.shade50,
    border: Colors.indigo.shade200,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '"${_phrase!.text}"',
          style: const TextStyle(
            fontSize: 16,
            height: 1.5,
            fontStyle: FontStyle.italic,
          ),
        ),
        if (_phrase!.author.isNotEmpty) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '— ${_phrase!.author}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.indigo.shade700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _AnotherButton(color: Colors.indigo.shade500, onTap: _loadPhrase),
      ],
    ),
  );

  // ── Idioma: frase hecha con pronunciación ──────────────────────────────────

  Widget _buildIdiomCard() {
    final i = _idiom!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selector de idioma con banderas
        _buildLanguageSelector(),
        const SizedBox(height: 12),
        _ContentCard(
          color: Colors.teal.shade50,
          border: Colors.teal.shade200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Idioma
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  i.language,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.teal.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Frase
              Text(
                '"${i.phrase}"',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.teal.shade700,
                  height: 1.3,
                ),
              ),

              // Pronunciación
              if (i.pronunciation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.volume_up_outlined,
                      size: 15,
                      color: Colors.teal.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      i.pronunciation,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.teal.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),

              // Significado
              _InfoRow(
                icon: Icons.lightbulb_outline,
                color: Colors.teal.shade700,
                text: i.meaning,
              ),

              // Ejemplo
              if (i.example.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade100.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ejemplo:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '"${i.example}"',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.teal.shade900,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      if (i.examplePronunciation.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.volume_up_outlined,
                              size: 13,
                              color: Colors.teal.shade400,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                i.examplePronunciation,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.teal.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _AnotherButton(
                color: Colors.teal.shade600,
                onTap: () => _loadIdiom(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Selector de idioma ─────────────────────────────────────────────────────

  Widget _buildLanguageSelector() {
    final langs = FunContentRepository.orderedLanguages;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: langs.map((lang) {
          final isSelected = lang == _selectedLanguage;
          final flag = FunContentRepository.flagEmoji(lang);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _loadIdiom(language: lang),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: isSelected
                      ? Colors.teal.shade600
                      : Colors.teal.shade50,
                  border: Border.all(
                    color: isSelected
                        ? Colors.teal.shade600
                        : Colors.teal.shade200,
                    width: 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.teal.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  flag,
                  style: TextStyle(fontSize: isSelected ? 22 : 20),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Dato interesante ───────────────────────────────────────────────────────

  Widget _buildFactCard() {
    final f = _fact!;
    return _ContentCard(
      color: Colors.deepPurple.shade50,
      border: Colors.deepPurple.shade200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (f.category.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                f.category,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.deepPurple.shade800,
                ),
              ),
            ),
          Text(f.text, style: const TextStyle(fontSize: 15, height: 1.55)),
          const SizedBox(height: 16),
          _AnotherButton(color: Colors.deepPurple.shade500, onTap: _loadFact),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ─────────────────────────────────────────────────────────

class _MenuButton extends StatelessWidget {
  final String emoji;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _MenuButton({
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
          ),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    ),
  );
}

class _ContentCard extends StatelessWidget {
  final Color color;
  final Color border;
  final Widget child;
  const _ContentCard({
    required this.color,
    required this.border,
    required this.child,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border, width: 1.5),
    ),
    child: child,
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoRow({
    required this.icon,
    required this.color,
    required this.text,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );
}

class _AnotherButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _AnotherButton({required this.color, required this.onTap, Key? key})
    : super(key: key);

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.refresh, size: 16, color: color),
      label: Text('Otra', style: TextStyle(color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    ),
  );
}
