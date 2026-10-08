// Reusable UI components built on the design tokens. Every screen should
// compose these rather than styling raw Containers, so spacing, colour and
// behaviour stay identical across the app.

import 'package:flutter/material.dart';
import 'tokens.dart';

// ─── Map chrome ──────────────────────────────────────────────────────────────

/// Search field floating over the map. Results ([below]) expand out of the
/// same panel instead of appearing as a separate floating card.
class MapSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool loading;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  /// Compact actions shown at the right end of the bar.
  final List<Widget> actions;

  /// Content revealed under the field (e.g. suggestions); null = collapsed.
  final Widget? below;

  const MapSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.loading = false,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.actions = const [],
    this.below,
  });

  @override
  Widget build(BuildContext context) {
    // Shadow outside, then a clipped Material so row ripples paint on the
    // panel's own surface.
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
        boxShadow: AppShadow.floating,
      ),
      child: Material(
        color: AppPalette.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppPalette.elevatedEdge),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: Row(children: [
                  const SizedBox(width: AppSpace.md),
                  SizedBox(
                    width: 20,
                    child: loading
                        ? const Center(
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppPalette.accent)))
                        : const Icon(Icons.search_rounded,
                            color: AppPalette.textSecondary, size: 20),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: AppText.body,
                      cursorColor: AppPalette.accent,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: AppText.body
                            .copyWith(color: AppPalette.textTertiary),
                        // Plain field: the panel itself is the container
                        filled: false,
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, __) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : CompactIconButton(
                            icon: Icons.close_rounded,
                            onTap: onClear,
                          ),
                  ),
                  if (actions.isNotEmpty) ...[
                    Container(
                        width: 1,
                        height: 20,
                        margin: const EdgeInsets.symmetric(
                            horizontal: AppSpace.xs),
                        color: AppPalette.divider),
                    ...actions,
                  ],
                  const SizedBox(width: AppSpace.xs),
                ]),
              ),
              if (below != null) ...[
                const Divider(height: 1, thickness: 1),
                below!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 40 × 40 icon button for use inside bars and rows (no background).
class CompactIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final String? tooltip;
  final double size;

  const CompactIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.color = AppPalette.textSecondary,
    this.tooltip,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: size, color: color),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      splashRadius: 20,
    );
  }
}

/// Square control floating over the map (e.g. "my location").
class MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color iconColor;

  const MapControlButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.iconColor = AppPalette.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppPalette.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppPalette.elevatedEdge),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: iconColor),
        ),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        boxShadow: AppShadow.floating,
      ),
      child: tooltip == null ? button : Tooltip(message: tooltip!, child: button),
    );
  }
}

/// Slim one-line prompt floating under the search bar, with dismiss.
class MapPromptChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? actionLabel;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  const MapPromptChip({
    super.key,
    required this.icon,
    required this.label,
    this.actionLabel,
    required this.onTap,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
        boxShadow: AppShadow.floating,
      ),
      child: Material(
        color: AppPalette.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppPalette.elevatedEdge),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: SizedBox(
            height: 44,
            child: Row(children: [
              const SizedBox(width: AppSpace.md),
              Icon(icon, size: 18, color: AppPalette.accent),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(label,
                    style: AppText.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (actionLabel != null)
                Text(actionLabel!,
                    style: AppText.label.copyWith(color: AppPalette.accent)),
              if (onDismiss != null)
                CompactIconButton(
                    icon: Icons.close_rounded, size: 18, onTap: onDismiss)
              else
                const SizedBox(width: AppSpace.md),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Bottom sheet parts ──────────────────────────────────────────────────────

/// Grab handle at the top of a bottom sheet; tap cycles snap heights.
class SheetHandle extends StatelessWidget {
  final VoidCallback? onTap;
  const SheetHandle({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xs),
        child: Center(
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: AppPalette.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text tabs with an accent underline — the Android-native pattern, lighter
/// than a filled segmented control.
class SheetTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  const SheetTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppPalette.divider)),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: InkWell(
              onTap: () => onSelect(i),
              child: SizedBox(
                height: 44,
                child: Stack(alignment: Alignment.center, children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: AppText.bodyStrong.copyWith(
                        color: i == selected
                            ? AppPalette.textPrimary
                            : AppPalette.textTertiary),
                    child: Text(labels[i],
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Positioned(
                    left: AppSpace.xl,
                    right: AppSpace.xl,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 2,
                      decoration: BoxDecoration(
                        color: i == selected
                            ? AppPalette.accent
                            : Colors.transparent,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Small heading above a group of rows.
class SectionHeader extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Widget? trailing;

  const SectionHeader(this.text, {super.key, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppPalette.accent),
          const SizedBox(width: AppSpace.xs + 2),
        ],
        Expanded(child: Text(text, style: AppText.heading)),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

// ─── Lists ───────────────────────────────────────────────────────────────────

/// Standard flat list row: leading · title/subtitle · trailing, with a
/// hairline divider. Use instead of a bordered card per item.
class ListRow extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  final bool highlighted;

  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? AppPalette.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg, vertical: AppSpace.sm + 2),
          decoration: divider
              ? const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: AppPalette.divider, width: 1)))
              : null,
          child: Row(children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle.merge(
                    style: AppText.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpace.md),
              trailing!,
            ],
          ]),
        ),
      ),
    );
  }
}

/// Route number badge. Neutral on purpose: the route number is the content,
/// colour is reserved for status.
class RouteBadge extends StatelessWidget {
  final String name;
  final bool large;
  const RouteBadge(this.name, {super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      // Fixed minimum so row titles line up for 35 / 351 / 351區
      constraints: BoxConstraints(minWidth: large ? 60 : 52),
      padding: EdgeInsets.symmetric(
          horizontal: AppSpace.sm, vertical: large ? 6 : 4),
      decoration: BoxDecoration(
        color: AppPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Text(
        name,
        maxLines: 1,
        style: (large ? AppText.heading : AppText.bodyStrong)
            .copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Outlined selectable chip (filters, route options, nearby stops).
class OptionChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const OptionChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppPalette.accent : AppPalette.textSecondary;
    return Material(
      color: selected ? AppPalette.accentSoft : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
            color: selected ? Colors.transparent : AppPalette.outline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md - 2, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: AppSpace.xs),
            ],
            Text(label, style: AppText.label.copyWith(color: fg)),
          ]),
        ),
      ),
    );
  }
}

/// Centered muted message for empty / loading states inside sheets.
class SheetMessage extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final bool loading;

  const SheetMessage({super.key, this.text, this.icon, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.xl),
      child: SizedBox(
        width: double.infinity,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (loading)
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppPalette.accent))
        else if (icon != null)
          Icon(icon, size: 24, color: AppPalette.textTertiary),
        if (text != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(text!,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: AppPalette.textTertiary)),
        ],
        ]),
      ),
    );
  }
}
