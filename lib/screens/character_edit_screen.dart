import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart' hide Provider;

import '../models/character.dart';
import '../state/app_state.dart';
import '../widgets/avatar_image.dart';
import 'gallery/gallery_picker_sheet.dart';

/// Create or edit a character. Passed a [character] it edits in place;
/// otherwise it builds a fresh one. Fields are grouped into calm sections
/// (Identity, Persona, Conversation, Advanced) rather than one long wall.
///
/// With [persist] false it edits a *draft*: Save pops the edited copy without
/// touching the roster or the store, leaving the caller to decide where it
/// lands. That is how the Chat settings screen collects a change before asking
/// whether to keep it for one chat or everywhere.
class CharacterEditScreen extends StatefulWidget {
  const CharacterEditScreen({
    super.key,
    this.character,
    this.persist = true,
  });

  final Character? character;
  final bool persist;

  @override
  State<CharacterEditScreen> createState() => _CharacterEditScreenState();
}

class _CharacterEditScreenState extends State<CharacterEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _avatar;
  late final TextEditingController _description;
  late final TextEditingController _personality;
  late final TextEditingController _scenario;
  late final TextEditingController _customScenario;
  late final TextEditingController _greeting;
  late final TextEditingController _example;
  late final TextEditingController _system;
  late final TextEditingController _postHistory;
  late final TextEditingController _creator;
  late final TextEditingController _notes;
  late final TextEditingController _tags;

  /// One controller per alternate greeting (SillyTavern `alternate_greetings` /
  /// Agnai's extra opening messages). The first message lives in [_greeting];
  /// these are "Greeting 2", "Greeting 3", … shown as foldable tiles.
  late List<TextEditingController> _altGreetings;

  /// Preserved so an imported PNG's base64 avatar survives an edit even though
  /// we never dump the blob into the URL field.
  late final String _originalAvatar;

  /// A freshly chosen device image, base64-encoded (no `data:` prefix).
  String? _pickedBase64;

  /// Set when the user explicitly clears the avatar.
  bool _removed = false;

  /// The background picture chats with this character wear, as a stored ref
  /// (`local:<file>` or an URL). Both pickers hand back a reference — a device
  /// file is stored the moment it is picked — so unlike the avatar there is
  /// never base64 to carry to Save.
  String? _background;

  bool get _isNew => widget.character == null;

  @override
  void initState() {
    super.initState();
    final c = widget.character;
    _originalAvatar = c?.avatar ?? '';
    _background = c?.backgroundImage.trim() == '' ? null : c?.backgroundImage;
    _name = TextEditingController(text: c?.name ?? '');
    // Only surface a URL avatar for editing; a base64 card image is kept
    // silently via [_originalAvatar].
    _avatar = TextEditingController(
      text: (c?.avatarIsUrl ?? false) ? c!.avatar : '',
    );
    _description = TextEditingController(text: c?.description ?? '');
    _personality = TextEditingController(text: c?.personality ?? '');
    _scenario = TextEditingController(text: c?.scenario ?? '');
    _customScenario = TextEditingController(text: c?.customScenario ?? '');
    _greeting = TextEditingController(text: c?.firstMes ?? '');
    _example = TextEditingController(text: c?.mesExample ?? '');
    _system = TextEditingController(text: c?.systemPrompt ?? '');
    _postHistory = TextEditingController(text: c?.postHistoryInstructions ?? '');
    _creator = TextEditingController(text: c?.creator ?? '');
    _notes = TextEditingController(text: c?.creatorNotes ?? '');
    _tags = TextEditingController(text: (c?.tags ?? const <String>[]).join(', '));
    _altGreetings = (c?.alternateGreetings ?? const <String>[])
        .map((g) => TextEditingController(text: g))
        .toList();
    // A typed URL should update the preview live.
    _avatar.addListener(_onAvatarUrlChanged);
  }

  void _onAvatarUrlChanged() => setState(() {});

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null || bytes.isEmpty) return;
    setState(() {
      _pickedBase64 = base64Encode(bytes);
      _removed = false;
      _avatar.clear(); // a picked image takes over from any typed URL
    });
  }

  /// The background chooser: a picture kept in the app's gallery, or a file off
  /// the device — the same two sources the chat's own background offers. A
  /// device file is written to the pictures directory straight away and only
  /// its reference is held until Save.
  Future<void> _pickBackground() async {
    final source = await showModalBottomSheet<_BackgroundSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('edit-background-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('App gallery'),
              subtitle: const Text('A picture already in MaiChat'),
              onTap: () => Navigator.of(sheetContext)
                  .pop(_BackgroundSource.gallery),
            ),
            ListTile(
              key: const Key('edit-background-device'),
              leading: const Icon(Icons.smartphone_outlined),
              title: const Text('This device'),
              subtitle: const Text('Pick a file from the phone'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_BackgroundSource.device),
            ),
            if (_background != null)
              ListTile(
                key: const Key('edit-background-remove'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove background'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_BackgroundSource.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    switch (source) {
      case _BackgroundSource.gallery:
        final ref = await showGalleryPickerSheet(
          context,
          title: 'Background for this character',
          characterId: widget.character?.id,
        );
        if (ref != null && mounted) setState(() => _background = ref);
      case _BackgroundSource.device:
        final result = await FilePicker.pickFiles(
          type: FileType.image,
          withData: true,
        );
        final bytes = result?.files.firstOrNull?.bytes;
        if (bytes == null || bytes.isEmpty || !mounted) return;
        final ref = await context.read<AppState>().storePicture(bytes);
        if (!mounted) return;
        if (ref == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That picture could not be stored.')),
          );
          return;
        }
        setState(() => _background = ref);
      case _BackgroundSource.remove:
        setState(() => _background = null);
    }
  }

  /// The avatar to persist / preview: a typed URL wins, then a freshly picked
  /// image, then the preserved original (unless it was explicitly removed).
  String _effectiveAvatar() {
    final url = _avatar.text.trim();
    if (url.isNotEmpty) return url;
    if (_pickedBase64 != null) return _pickedBase64!;
    if (_removed) return '';
    // A cleared URL original resolves to empty; a base64 image is kept.
    return _originalAvatar.startsWith('http') ? '' : _originalAvatar;
  }

  @override
  void dispose() {
    for (final controller in [
      _name, _avatar, _description, _personality, _scenario, _customScenario,
      _greeting, _example, _system, _postHistory, _creator, _notes, _tags,
      ..._altGreetings,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addGreeting() =>
      setState(() => _altGreetings.add(TextEditingController()));

  void _removeGreeting(int index) => setState(() {
        _altGreetings.removeAt(index).dispose();
      });

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final avatar = _effectiveAvatar();

    // A draft edit must not touch the object the roster is holding, so it is
    // written onto a copy; an in-place edit keeps mutating the live card as
    // before, which is what [AppState.saveCharacter] expects.
    final character = widget.persist
        ? (widget.character ?? Character.empty())
        : (widget.character?.clone() ?? Character.empty());
    character
      ..name = _name.text.trim()
      ..avatar = avatar
      ..backgroundImage = _background?.trim() ?? ''
      ..description = _description.text.trim()
      ..personality = _personality.text.trim()
      ..scenario = _scenario.text.trim()
      ..customScenario = _customScenario.text.trim()
      ..firstMes = _greeting.text.trim()
      ..alternateGreetings = _altGreetings
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList()
      ..mesExample = _example.text.trim()
      ..systemPrompt = _system.text.trim()
      ..postHistoryInstructions = _postHistory.text.trim()
      ..creator = _creator.text.trim()
      ..creatorNotes = _notes.text.trim()
      ..tags = _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

    if (widget.persist) await context.read<AppState>().saveCharacter(character);
    if (mounted) Navigator.of(context).pop(character);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New character' : 'Edit character'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _avatarSection(),
            const _SectionLabel('Identity'),
            _field(_name, 'Name', required: true),
            _field(_avatar, 'Avatar image URL',
                hint: 'Optional — https://…'),
            _field(_tags, 'Tags', hint: 'Comma-separated'),
            _backgroundRow(),
            const _SectionLabel('Persona'),
            _field(_description, 'Description', lines: 4),
            _field(_personality, 'Personality', lines: 2),
            _field(_scenario, 'Scenario', lines: 2),
            _field(_customScenario, 'Custom scenario',
                hint: "Optional — used instead of the card's scenario",
                lines: 2),
            const _SectionLabel('Conversation'),
            _field(_greeting, 'Greeting (first message)', lines: 3),
            _alternateGreetings(),
            _field(_example, 'Example dialogue', lines: 3),
            const _SectionLabel('Advanced'),
            _field(_system, 'System prompt', lines: 3),
            _field(_postHistory, 'Post-history instructions', lines: 2),
            _field(_creator, 'Creator'),
            _field(_notes, 'Creator notes', lines: 2),
          ],
        ),
      ),
    );
  }

  /// The avatar preview + pick/remove controls shown atop the form.
  Widget _avatarSection() {
    final scheme = Theme.of(context).colorScheme;
    final eff = _effectiveAvatar();
    final image = avatarImage(
      eff,
      displaySize: 88,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: scheme.secondaryContainer,
            backgroundImage: image,
            onBackgroundImageError: image == null ? null : (_, _) {},
            child: image == null
                ? Icon(Icons.person_outline,
                    size: 40, color: scheme.onSecondaryContainer)
                : null,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Choose image'),
              ),
              if (eff.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _removed = true;
                    _pickedBase64 = null;
                    _avatar.clear();
                  }),
                  icon: const Icon(Icons.close),
                  label: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The background row: a preview of what is set, a tap for the source sheet.
  Widget _backgroundRow() {
    final scheme = Theme.of(context).colorScheme;
    final provider = _background == null
        ? null
        : avatarImage(
            _background!,
            displaySize: 96,
            devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            key: const Key('edit-background-card'),
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 48,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: scheme.surfaceContainerHighest,
                  image: provider == null
                      ? null
                      : DecorationImage(image: provider, fit: BoxFit.cover),
                ),
                child: provider == null
                    ? Icon(Icons.image_outlined, color: scheme.onSurfaceVariant)
                    : null,
              ),
            ),
            title: const Text('Chat background'),
            subtitle: Text(
              _background == null
                  ? 'Chats with this character wear their usual style'
                  : 'A picture of this character\'s own',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickBackground,
          ),
        ],
      ),
    );
  }

  /// Foldable editors for the extra opening messages ("Greeting 2", "Greeting
  /// 3", …). A + on the right adds another; each tile can be removed.
  Widget _alternateGreetings() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Alternate greetings',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Add greeting',
                icon: const Icon(Icons.add),
                onPressed: _addGreeting,
              ),
            ],
          ),
          if (_altGreetings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                'None yet — tap + to add a swipeable opening message.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          for (var i = 0; i < _altGreetings.length; i++)
            Card(
              key: ValueKey(_altGreetings[i]),
              elevation: 0,
              color: scheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                title: Text('Greeting ${i + 2}'),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                children: [
                  TextField(
                    controller: _altGreetings[i],
                    minLines: 3,
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText: 'Alternate opening message',
                      alignLabelWithHint: true,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _removeGreeting(i),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int lines = 1,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 4,
        textInputAction:
            lines == 1 ? TextInputAction.next : TextInputAction.newline,
        keyboardType:
            lines == 1 ? TextInputType.text : TextInputType.multiline,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: lines > 1,
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }
}

/// Where a character's chat background comes from.
enum _BackgroundSource { gallery, device, remove }

/// A quiet run-in heading between field groups.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}
