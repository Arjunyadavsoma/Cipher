import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mimir_ai/app/features/rss/view/pages/rss_page.dart';

class DrawerView extends StatelessWidget {
  const DrawerView({super.key});

  @override
  Widget build(BuildContext context) {
    final drawerWidth = MediaQuery.of(context).size.width * 0.72;

    return Material(
      color: const Color(0xFFF7F7F8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: drawerWidth,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Menu",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 18),

                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _DrawerTile(
                          icon: Icons.auto_awesome,
                          title: "Agents",
                          onTap: () {
                            // Intentionally a no-op for now, per current
                            // requirements — tapping "Agents" does nothing.
                            // Wire this to an agent-picker screen later
                            // if/when one exists.
                          },
                        ),
                        _DrawerTile(
                          icon: Icons.newspaper_outlined,
                          title: "News",
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RssPage(
                                  // TODO: replace with the real signed-in
                                  // user id from your auth provider
                                  // (firebase_auth, per pubspec.yaml).
                                  // Left as a literal placeholder rather
                                  // than guessing at an auth read I
                                  // haven't seen — swap this one line
                                  // once you point me at how the rest of
                                  // the app reads the current user.
                                  userId: 'CURRENT_USER_ID_PLACEHOLDER',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const Divider(),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      radius: 20,
                      child: Icon(Icons.person),
                    ),
                    title: const Text(
                      "Arjun",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text("Profile"),
                    onTap: () {},
                  ),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(CupertinoIcons.settings),
                    title: const Text("Settings"),
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      leading: Icon(icon, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}