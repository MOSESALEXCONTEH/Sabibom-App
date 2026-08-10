import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/business_setup/application/business_experience_providers.dart';

class ModernBottomNavigation extends StatelessWidget {
  const ModernBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.terminology = const BusinessTerminology.product(),
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final BusinessTerminology terminology;

  List<_NavItem> get _items => <_NavItem>[
    _NavItem(
      label: 'Home',
      icon: CupertinoIcons.house,
      selectedIcon: CupertinoIcons.house_fill,
    ),
    _NavItem(
      label: terminology.sales,
      icon: CupertinoIcons.doc_text,
      selectedIcon: CupertinoIcons.doc_text_fill,
    ),
    _NavItem(
      label: terminology.products,
      icon: CupertinoIcons.cube_box,
      selectedIcon: CupertinoIcons.cube_box_fill,
    ),
    _NavItem(
      label: terminology.customers,
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
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: context.borderColor),
            boxShadow: context.floatingShadow,
          ),
          child: SizedBox(
            height: 72,
            child: Row(
              children: List<Widget>.generate(
                _items.length,
                (index) => Expanded(
                  child: RepaintBoundary(
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
    final iconColor = selected
        ? Theme.of(context).colorScheme.primary
        : (context.isDarkTheme
              ? const Color(0xFF8A90A5)
              : const Color(0xFF7A7F91));
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
                duration: AppMotion.resolve(context, AppMotion.standard),
                curve: AppMotion.curve,
                width: double.infinity,
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                decoration: BoxDecoration(
                  color: selected ? context.brandTint : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    AnimatedScale(
                      duration: AppMotion.resolve(context, AppMotion.standard),
                      curve: AppMotion.curve,
                      scale: selected ? 1.08 : 1,
                      child: Icon(
                        selected ? item.selectedIcon : item.icon,
                        size: selected ? 28 : 24,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 14,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          style: TextStyle(
                            color: iconColor,
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
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
