import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/widgets/app_card.dart';

/// Screen for Open Source Licenses disclosure.
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final licenses = [
      {'package': 'Flutter SDK', 'license': 'BSD 3-Clause License', 'desc': 'Google LLC'},
      {'package': 'Provider', 'license': 'MIT License', 'desc': 'Remi Rousselet'},
      {'package': 'GoRouter', 'license': 'BSD 3-Clause License', 'desc': 'Flutter Community'},
      {'package': 'Google Fonts', 'license': 'Apache License 2.0', 'desc': 'Material Design Team'},
      {'package': 'Shared Preferences', 'license': 'BSD 3-Clause License', 'desc': 'Flutter Team'},
      {'package': 'UUID', 'license': 'MIT License', 'desc': 'Yulian Kuncheff'},
      {'package': 'Intl', 'license': 'BSD 3-Clause License', 'desc': 'Dart Project Authors'},
    ];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Open Source Licenses'),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: AppDimensions.screenPadding,
          itemCount: licenses.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = licenses[index];
            return AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['package']!,
                    style: AppTypography.subsectionTitle.copyWith(
                      color: isDark ? AppColors.darkText : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item['license']} · ${item['desc']}',
                    style: AppTypography.secondary.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
