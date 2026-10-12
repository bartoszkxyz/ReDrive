import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'bottom_bar_config.dart';

class BottomBarItem extends StatelessWidget {
  const BottomBarItem({
    super.key,
    required this.data,
    required this.isActive,
    required this.onTap,
    this.isCompact = false,
  });

  final BottomBarItemData data;
  final bool isActive;
  final VoidCallback onTap;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final Color activeColor = Theme.of(context).colorScheme.primary;
    final Color inactiveColor = Colors.grey.shade600;

    Color currentColor = isActive ? activeColor : inactiveColor;
    final double iconSize = isCompact ? (isActive ? 22 : 19) : (isActive ? 27 : 23);
    final double fontSize = isCompact ? 11 : 12;
    final double spacing = isCompact ? 3 : 6;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: SvgPicture.asset(
                data.iconPath,
                width: iconSize,
                height: iconSize,
                colorFilter: ColorFilter.mode(currentColor, BlendMode.srcIn),
              ),
            ),
            SizedBox(height: spacing),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: currentColor,
                fontSize: fontSize,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: isCompact ? 2 : 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: isActive ? (isCompact ? 16 : 20) : 0,
              height: 2,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
