import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart' hide Provider;

import '../../state/app_state.dart';
import '../../widgets/avatar_image.dart';
import '../gallery/gallery_picker_sheet.dart';
import 'creator_controls.dart';
import 'creator_draft.dart';

/// Chooses the background picture chats with this character wear: one kept in
/// the app's gallery, or a file off the phone.
///
/// Both sources hand back a stored reference — the gallery's file is pointed
/// at as-is, and a device file is written to the pictures directory the moment
/// it is picked (see `AppState.storePicture`) — so the draft never holds
/// base64, whatever saves it.
Future<void> showCharacterBackgroundSheet(
  BuildContext context, {
  required CreatorDraft draft,
  String? characterId,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('creator-background-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('App gallery'),
              subtitle: const Text('A picture already in MaiChat'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final ref = await showGalleryPickerSheet(
                  context,
                  title: 'Background for this character',
                  characterId: characterId,
                );
                if (ref != null) draft.setBackground(ref);
              },
            ),
            ListTile(
              key: const Key('creator-background-device'),
              leading: const Icon(Icons.smartphone_outlined),
              title: const Text('This device'),
              subtitle: const Text('Pick a file from the phone'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pickFromDevice(context, draft);
              },
            ),
            if (draft.backgroundImage.trim().isNotEmpty)
              ListTile(
                key: const Key('creator-background-remove'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove background'),
                subtitle: const Text(
                  'Chats go back to the style they would wear anyway',
                ),
                onTap: () {
                  draft.setBackground('');
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

/// Reads a file off the phone and stores it straight away, so what the draft
/// holds is a reference rather than bytes.
Future<void> _pickFromDevice(BuildContext context, CreatorDraft draft) async {
  final state = context.read<AppState>();
  final result = await FilePicker.pickFiles(
    type: FileType.image,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return;
  final bytes = result.files.first.bytes;
  if (bytes == null || bytes.isEmpty) return;
  final ref = await state.storePicture(bytes);
  if (ref == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That picture could not be stored.')),
      );
    }
    return;
  }
  draft.setBackground(ref);
}

/// The Identity tab's row for the background: a preview of what is set (or an
/// icon when nothing is), a line under it saying what a chat will do, and the
/// sheet behind the tap.
class CharacterBackgroundCard extends StatelessWidget {
  const CharacterBackgroundCard({super.key, required this.draft});

  final CreatorDraft draft;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ref = draft.backgroundImage.trim();
    final provider = ref.isEmpty
        ? null
        : avatarImage(
            ref,
            displaySize: 96,
            devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: const Key('creator-background-card'),
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
            ref.isEmpty
                ? 'Chats with this character wear their usual style'
                : 'A picture of this character\'s own',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showCharacterBackgroundSheet(
            context,
            draft: draft,
            characterId: draft.original?.id,
          ),
        ),
        const CreatorNote(
          'A background picked here sits behind every chat with this character, '
          'under one the chat chooses for itself.',
        ),
      ],
    );
  }
}
