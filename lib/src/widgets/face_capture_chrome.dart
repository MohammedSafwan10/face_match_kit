import 'package:flutter/material.dart';

import '../face_match_models.dart';
import 'face_match_theme.dart';

class FaceFriendlyHeader extends StatelessWidget {
  final String title;
  final String? badge;
  final Color accentColor;
  final FaceMatchTheme theme;

  const FaceFriendlyHeader({
    super.key,
    required this.title,
    required this.accentColor,
    required this.theme,
    this.badge,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.foregroundColor,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      if (badge != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, color: accentColor, size: 15),
              const SizedBox(width: 6),
              Text(
                badge!,
                style: TextStyle(
                  color: theme.foregroundColor.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class FaceCameraPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;

  const FaceCameraPill({
    super.key,
    required this.label,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xDD202124),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: const [
            BoxShadow(color: Color(0x30000000), blurRadius: 12),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accentColor, size: 21),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
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

class FaceCameraTitle extends StatelessWidget {
  final String label;

  const FaceCameraTitle({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label,
    textAlign: TextAlign.center,
    maxLines: 2,
    softWrap: true,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
    ),
  );
}

class FaceCaptureHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final FaceMatchTheme theme;

  const FaceCaptureHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: theme.accentColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: theme.accentColor, size: 22),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.foregroundColor,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.foregroundColor.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      Icon(Icons.lock_outline_rounded, color: theme.successColor, size: 20),
    ],
  );
}

class FacePoseProgress extends StatelessWidget {
  final int activeIndex;
  final FaceMatchTheme theme;
  final Color? accentColor;

  const FacePoseProgress({
    super.key,
    required this.activeIndex,
    required this.theme,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.face_rounded,
      Icons.turn_left_rounded,
      Icons.turn_right_rounded,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < icons.length; index++) ...[
          Flexible(
            child: _PoseStep(
              icon: icons[index],
              number: index + 1,
              complete: index < activeIndex,
              active: index == activeIndex,
              theme: theme,
              accentColor: accentColor,
            ),
          ),
          if (index < icons.length - 1)
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 54),
                height: 2,
                color: index < activeIndex
                    ? theme.successColor
                    : theme.foregroundColor.withValues(alpha: 0.16),
              ),
            ),
        ],
      ],
    );
  }
}

class _PoseStep extends StatelessWidget {
  final IconData icon;
  final int number;
  final bool complete;
  final bool active;
  final FaceMatchTheme theme;
  final Color? accentColor;

  const _PoseStep({
    required this.icon,
    required this.number,
    required this.complete,
    required this.active,
    required this.theme,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final highlighted = complete || active;
    final color = accentColor ?? theme.accentColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: highlighted ? color : const Color(0xFFF3ECE4),
        shape: BoxShape.circle,
        border: Border.all(
          color: highlighted
              ? color
              : theme.foregroundColor.withValues(alpha: 0.12),
        ),
        boxShadow: highlighted
            ? [BoxShadow(color: color.withValues(alpha: 0.24), blurRadius: 10)]
            : null,
      ),
      alignment: Alignment.center,
      child: complete
          ? const Icon(Icons.check_rounded, size: 22, color: Colors.white)
          : Icon(
              icon,
              size: 21,
              color: highlighted
                  ? Colors.white
                  : theme.foregroundColor.withValues(alpha: 0.48),
              semanticLabel: 'Step $number',
            ),
    );
  }
}

class FaceInstructionCard extends StatelessWidget {
  final String title;
  final String detail;
  final IconData icon;
  final bool isError;
  final FaceMatchTheme theme;

  const FaceInstructionCard({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    required this.isError,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? theme.errorColor : theme.accentColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isError ? theme.errorColor : theme.foregroundColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.foregroundColor.withValues(alpha: 0.62),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FaceReadinessRow extends StatelessWidget {
  final bool faceReady;
  final bool qualityReady;
  final bool actionReady;
  final String actionLabel;
  final FaceMatchTheme theme;

  const FaceReadinessRow({
    super.key,
    required this.faceReady,
    required this.qualityReady,
    required this.actionReady,
    required this.actionLabel,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ReadinessPill(label: 'Face', ready: faceReady, theme: theme),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: _ReadinessPill(
          label: 'Quality',
          ready: qualityReady,
          theme: theme,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: _ReadinessPill(
          label: actionLabel,
          ready: actionReady,
          theme: theme,
        ),
      ),
    ],
  );
}

class _ReadinessPill extends StatelessWidget {
  final String label;
  final bool ready;
  final FaceMatchTheme theme;

  const _ReadinessPill({
    required this.label,
    required this.ready,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final color = ready ? theme.successColor : theme.foregroundColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: ready ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: ready ? 0.38 : 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: color.withValues(alpha: ready ? 1 : 0.45),
            size: 14,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.withValues(alpha: ready ? 1 : 0.55),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData guidanceIcon({required FaceMatchFailure? failure, FacePose? pose}) {
  if (failure != null) return Icons.info_outline_rounded;
  return switch (pose) {
    FacePose.front => Icons.face_rounded,
    FacePose.slightLeft => Icons.turn_left_rounded,
    FacePose.slightRight => Icons.turn_right_rounded,
    null => Icons.verified_user_outlined,
  };
}
