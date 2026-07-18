import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class ModernBottomNavigation extends StatelessWidget {
  const ModernBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static final _items = <_NavItem>[
    _NavItem(
      label: 'Home',
      icon: CupertinoIcons.house,
      selectedIcon: CupertinoIcons.house_fill,
    ),
    _NavItem(
      label: 'Sales',
      icon: CupertinoIcons.doc_text,
      selectedIcon: CupertinoIcons.doc_text_fill,
    ),
    _NavItem(
      label: 'Products',
      icon: CupertinoIcons.cube_box,
      selectedIcon: CupertinoIcons.cube_box_fill,
    ),
    _NavItem(
      label: 'Customers',
      icon: CupertinoIcons.person_2,
      selectedIcon: CupertinoIcons.person_2_fill,
    ),
    _NavItem(
      label: 'More',
      icon: CupertinoIcons.square_grid_2x2,
      selectedIcon: CupertinoIcons.square_grid_2x2_fill,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFECECF2)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            height: 72,
            child: Row(
              children: List<Widget>.generate(
                _items.length,
                (index) => Expanded(
                  child: _BottomNavigationDestination(
                    item: _items[index],
                    selected: selectedIndex == index,
                    onTap: () => onDestinationSelected(index),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavigationDestination extends StatelessWidget {
  const _BottomNavigationDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.primary : const Color(0xFF7A7F91);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Tooltip(
        message: item.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                width: 54,
                height: 54,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFEEE9FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    AnimatedScale(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      scale: selected ? 1.08 : 1,
                      child: Icon(
                        selected ? item.selectedIcon : item.icon,
                        size: selected ? 28 : 24,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      width: selected ? 12 : 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
