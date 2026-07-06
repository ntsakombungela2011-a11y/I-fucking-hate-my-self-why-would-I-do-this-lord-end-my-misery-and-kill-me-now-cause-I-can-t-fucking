import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/message/conversation_screen.dart';
import 'package:lichess_mobile/src/view/user/user_or_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';

void showUserContextMenu(BuildContext context, WidgetRef ref, LightUser user) {
  final authUser = ref.read(authControllerProvider);

  showAdaptiveActionSheet(
    context: context,
    actions: [
      BottomSheetAction(
        leading: const Icon(Icons.person_outline),
        makeLabel: (context) => Text(context.l10n.profile),
        onPressed: (context) =>
            Navigator.of(context).push(UserOrProfileScreen.buildRoute(user)),
      ),
      if (authUser != null && authUser.user.id != user.id)
        BottomSheetAction(
          leading: const Icon(Icons.mail_outline),
          makeLabel: (context) => Text(context.l10n.chatContactViaMessage),
          onPressed: (context) =>
              Navigator.of(context).push(ConversationScreen.buildRoute(user: user)),
        ),
      BottomSheetAction(
        leading: const Icon(Icons.share_outlined),
        makeLabel: (context) => Text(context.l10n.share),
        onPressed: (context) => shareUser(user),
      ),
    ],
  );
}
