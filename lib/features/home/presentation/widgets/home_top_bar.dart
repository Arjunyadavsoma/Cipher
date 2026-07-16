import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class HomeTopBar extends StatelessWidget {
  final VoidCallback onMenuPressed;

  const HomeTopBar({
    super.key,
    required this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xffF7F7F8),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              const Text(
                "Agents",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 18),

              const _DrawerTile(
                icon: Icons.chat_outlined,
                title: "Default Chat",
              ),

              const _DrawerTile(
                icon: Icons.travel_explore_outlined,
                title: "Research Agent",
              ),

              const _DrawerTile(
                icon: Icons.mail_outline,
                title: "Email Agent",
              ),

              const _DrawerTile(
                icon: Icons.calendar_month_outlined,
                title: "Calendar Agent",
              ),

              const _DrawerTile(
                icon: Icons.bolt_outlined,
                title: "Automation",
              ),

              const _DrawerTile(
                icon: Icons.code,
                title: "Coding Agent",
              ),

              const _DrawerTile(
                icon: Icons.school_outlined,
                title: "DSA Agent",
              ),

              const SizedBox(height: 34),

              const Text(
                "Recent Chats",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 14),

              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const BouncingScrollPhysics(),
                  children: const [
                    _ChatTile("Flutter Clean Architecture"),
                    _ChatTile("Groq Integration"),
                    _ChatTile("Daily DSA"),
                    _ChatTile("Machine Learning"),
                    _ChatTile("Research Paper"),
                    _ChatTile("AI Automation"),
                    _ChatTile("Resume Review"),
                    _ChatTile("Portfolio Website"),
                  ],
                ),
              ),

              const Divider(height: 28),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  radius: 21,
                  child: Icon(Icons.person),
                ),
                title: const Text(
                  "Arjun",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text("View Profile"),
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
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;

  const _DrawerTile({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        size: 22,
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () {},
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String title;

  const _ChatTile(this.title);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(
        CupertinoIcons.chat_bubble,
        size: 18,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
        ),
      ),
      onTap: () {},
    );
  }
}