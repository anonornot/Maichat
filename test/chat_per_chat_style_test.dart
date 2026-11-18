import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maichat/models/character.dart';
import 'package:maichat/models/chat_interface.dart';
import 'package:maichat/screens/chat_screen.dart';
import 'package:maichat/state/app_state.dart';
import 'package:maichat/widgets/message_bubble.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings that belong to one chat have to actually reach that chat's screen —
/// storing them is the easy half. This drives the real [ChatScreen].
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<AppState> chat() async {
    final state = AppState();
    // The chat screen holds a startup gate until the store has been read.
    await state.init();
    final character = Character.empty()
      ..name = 'Aria'
      ..firstMes = 'Evening.';
    await state.addCharacter(character);
    state.startChatWithCharacter(character);
    return state;
  }

  Widget host(AppState state) => ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: ChatScreen()),
      );

  ChatInterface bubbleUi(WidgetTester tester) =>
      tester.widget<MessageBubble>(find.byType(MessageBubble).first).ui;

  testWidgets('a chat with its own style is drawn with it, not the app-wide one',
      (tester) async {
    final state = await chat();
    await state.updateChatInterface(
      state.chatInterface.copyWith(fontSize: 13, showNames: false),
    );
    await state.saveChatInterfaceOverride(
      state.active.id,
      state.chatInterface.copyWith(fontSize: 25, showNames: true),
    );

    await tester.pumpWidget(host(state));
    await tester.pump();
    await tester.pump();

    expect(bubbleUi(tester).fontSize, 25);
    expect(bubbleUi(tester).showNames, isTrue);
  });

  testWidgets('dropping the override puts the chat back on the app-wide style',
      (tester) async {
    final state = await chat();
    await state.saveChatInterfaceOverride(
      state.active.id,
      state.chatInterface.copyWith(fontSize: 25),
    );
    await state.clearChatInterfaceOverride(state.active.id);

    await tester.pumpWidget(host(state));
    await tester.pump();
    await tester.pump();

    expect(bubbleUi(tester).fontSize, state.chatInterface.fontSize);
  });

  testWidgets('a background picture is drawn behind the thread, faded',
      (tester) async {
    final state = await chat();
    await state.setChatBackground(
      state.active.id,
      'https://example.com/bg.png',
      opacity: 0.3,
    );

    await tester.pumpWidget(host(state));
    await tester.pump();
    await tester.pump();

    final image = find.byType(Image);
    expect(image, findsOneWidget);
    final widget = tester.widget<Image>(image);
    expect(widget.fit, BoxFit.cover);
    // The fade is the point: a photograph at full strength behind running text
    // cannot be read over. It is applied through the Image's own `opacity`
    // (a cheap paint-level alpha), not an `Opacity` widget (which forces an
    // expensive full-screen save-layer).
    expect(widget.opacity?.value, 0.3);
  });

  testWidgets('no background means no picture layer at all', (tester) async {
    final state = await chat();
    await tester.pumpWidget(host(state));
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsNothing);
  });

  testWidgets("a character's background is drawn behind their chat",
      (tester) async {
    final state = await chat();
    state.characterById(state.active.characterId)!
      ..backgroundImage = 'https://example.com/char-bg.png'
      ..avatar = ''; // the avatar is an Image too — keep it out of the way.

    await tester.pumpWidget(host(state));
    await tester.pump();
    await tester.pump();

    final image = find.byType(Image);
    expect(image, findsOneWidget);
    expect(backgroundUrl(tester), 'https://example.com/char-bg.png');
  });

  testWidgets("the chat's own background outranks the character's",
      (tester) async {
    final state = await chat();
    state.characterById(state.active.characterId)!
      ..backgroundImage = 'https://example.com/char-bg.png'
      ..avatar = '';
    await state.setChatBackground(
      state.active.id,
      'https://example.com/chat-bg.png',
      opacity: 0.3,
    );

    await tester.pumpWidget(host(state));
    await tester.pump();
    await tester.pump();

    final widget = tester.widget<Image>(find.byType(Image));
    expect(backgroundUrl(tester), 'https://example.com/chat-bg.png');
    expect(widget.opacity?.value, 0.3);
  });

  testWidgets("a character's background outranks the interface look's",
      (tester) async {
    final state = await chat();
    state.characterById(state.active.characterId)!
      ..backgroundImage = 'https://example.com/char-bg.png'
      ..avatar = '';
    await state.updateChatInterface(
      state.chatInterface.copyWith(
        backgroundImage: 'https://example.com/ui-bg.png',
      ),
    );

    await tester.pumpWidget(host(state));
    await tester.pump();
    await tester.pump();

    expect(backgroundUrl(tester), 'https://example.com/char-bg.png');
  });
}

/// Which URL the chat's background `Image` is drawing. The provider is a
/// `ResizeImage` (what `avatarImage` wraps every provider in for cache
/// sizing); the `NetworkImage` inside it carries the URL.
String? backgroundUrl(WidgetTester tester) {
  final provider = tester.widget<Image>(find.byType(Image)).image;
  final inner = provider is ResizeImage ? provider.imageProvider : provider;
  return inner is NetworkImage ? inner.url : null;
}
