import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';

/// Screen 5: Polished processing screen with calm step animations (no fake percentages).
class ProcessingScreen extends StatefulWidget {
  final String? stepTitle;
  final String destinationRoute;

  const ProcessingScreen({
    super.key,
    this.stepTitle,
    required this.destinationRoute,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  int _activeStepIndex = 0;

  final List<String> _processingSteps = [
    'Detecting document',
    'Straightening page',
    'Enhancing image',
    'Preparing document',
  ];

  @override
  void initState() {
    super.initState();
    _runStepProgression();
  }

  Future<void> _runStepProgression() async {
    for (int i = 0; i < _processingSteps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      setState(() => _activeStepIndex = i);
    }

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    context.go(widget.destinationRoute);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Calm scanning animation symbol
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isDark ? AppColors.darkPrimary : AppColors.primary).withAlpha(25),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? AppColors.darkPrimary : AppColors.primary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.document_scanner_rounded,
                        size: 26,
                        color: isDark ? AppColors.darkPrimary : AppColors.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.space32),

                // Main Title
                Text(
                  widget.stepTitle ?? 'Preparing your scan...',
                  textAlign: TextAlign.center,
                  style: AppTypography.screenTitle.copyWith(
                    color: isDark ? AppColors.darkText : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppDimensions.space24),

                // Subtle Step Sequence
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: AppDimensions.borderCard,
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                    ),
                  ),
                  child: Column(
                    children: List.generate(_processingSteps.length, (index) {
                      final isComplete = index < _activeStepIndex;
                      final isCurrent = index == _activeStepIndex;

                      Color itemColor;
                      IconData stepIcon;

                      if (isComplete) {
                        itemColor = AppColors.success;
                        stepIcon = Icons.check_circle_rounded;
                      } else if (isCurrent) {
                        itemColor = isDark ? AppColors.darkPrimary : AppColors.primary;
                        stepIcon = Icons.radio_button_checked_rounded;
                      } else {
                        itemColor = isDark ? AppColors.darkTextSecondary.withAlpha(100) : AppColors.textSecondary.withAlpha(100);
                        stepIcon = Icons.radio_button_unchecked_rounded;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            Icon(stepIcon, size: 18, color: itemColor),
                            const SizedBox(width: 12),
                            Text(
                              _processingSteps[index],
                              style: AppTypography.bodyMedium.copyWith(
                                color: isDark ? AppColors.darkText : AppColors.textPrimary,
                                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
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
