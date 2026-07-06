import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/relation/following_user.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/user/user_or_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/shimmer.dart';
import 'package:lichess_mobile/src/widgets/user.dart';

class FollowingCarousel extends ConsumerWidget {
  const FollowingCarousel(this.followingAsync, {super.key});

  final AsyncValue<IList<FollowingUser>> followingAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return followingAsync.when(
      data: (following) {
        if (following.isEmpty) {
          return const SizedBox.shrink();
        }

        final onlineFriends = following.where((f) => f.online).toList(growable: false);

        if (onlineFriends.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: Styles.verticalBodyPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: Styles.horizontalBodyPadding,
                child: ListSectionHeader(title: Text(context.l10n.onlineFriends)),
              ),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  scrollDirection: Axis.horizontal,
                  itemCount: onlineFriends.length,
                  itemBuilder: (context, index) {
                    final friend = onlineFriends[index];
                    return _FriendCard(friend: friend);
                  },
                ),
              ),
            ],
          ),
        );
      },
      error: (error, stackTrace) => const SizedBox.shrink(),
      loading: () => Shimmer(
        child: ShimmerLoading(
          isLoading: true,
          child: Padding(
            padding: Styles.verticalBodyPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: Styles.horizontalBodyPadding,
                  child: ListSectionHeader(title: const Text('Online friends')),
                ),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    scrollDirection: Axis.horizontal,
                    itemCount: 5,
                    itemBuilder: (context, index) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: _FriendCardLoading(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({required this.friend});

  final FollowingUser friend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context, rootNavigator: true).push(
              UserOrProfileScreen.buildRoute(friend.user),
            );
          },
          child: Container(
            width: 140,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                UserStatusWidget(friend.user, size: 30),
                const SizedBox(height: 8),
                Text(
                  friend.user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (friend.playingId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Playing',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendCardLoading extends StatelessWidget {
  const _FriendCardLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
