import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/ai_provider.dart';
import '../../core/services/hf_vision_service.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_buttons.dart';

/// Screen 12: AI Assistant Configuration & Status Screen.
/// Displays Qwen3-VL-8B model status, ZeroGPU endpoints, daily 120s allowance metrics,
/// and live connectivity verification.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  bool _isTestingConnection = false;
  String? _testResult;
  bool _testSuccess = false;

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _testResult = null;
    });

    try {
      final res = await http.get(
        Uri.parse('${HfVisionService.baseUrl}/gradio_api/info'),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        setState(() {
          _testSuccess = true;
          _testResult = 'Connected to Qwen3-VL-8B ZeroGPU Space successfully.';
        });
      } else {
        setState(() {
          _testSuccess = false;
          _testResult = 'Space responded with HTTP ${res.statusCode}.';
        });
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Unable to reach AI service: $e';
      });
    } finally {
      setState(() => _isTestingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aiProvider = context.watch<AiProvider>();
    final remainingSecs = aiProvider.remainingSecondsToday;
    final usedSecs = aiProvider.usedSecondsToday;
    final progress = aiProvider.usageProgress;
    final isExhausted = aiProvider.isAllowanceExhausted;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('AI Assistant Settings'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppDimensions.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Informative disclaimer card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 20,
                      color: isDark ? AppColors.darkPrimary : AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Independent from Google Drive',
                            style: AppTypography.bodyMedium.copyWith(
                              color: isDark ? AppColors.darkText : const Color(0xFF1E3A8A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'DocuRay AI runs on high-performance Qwen3-VL-8B via ZeroGPU. '
                            'Using AI does not consume your Google Drive storage or require Google Cloud credentials.',
                            style: AppTypography.secondary.copyWith(
                              color: isDark ? AppColors.darkTextSecondary : const Color(0xFF1E40AF),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Active AI Model Status Card
              Text(
                'AI MODEL & ENGINE',
                style: AppTypography.badge.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.smart_toy_rounded,
                            size: 24,
                            color: isDark ? AppColors.darkPrimary : AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Qwen3-VL-8B Vision',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Active (ZeroGPU Accelerated)',
                                    style: AppTypography.secondary.copyWith(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildInfoRow('Endpoint', 'smsram-zerogpu.hf.space', isDark),
                    const SizedBox(height: 8),
                    _buildInfoRow('Architecture', 'Multimodal Vision-Language (8B)', isDark),
                    const SizedBox(height: 8),
                    _buildInfoRow('Stream Format', 'Server-Sent Events (SSE)', isDark),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Free Daily Usage Allowance Card
              Text(
                'DAILY FREE ALLOWANCE',
                style: AppTypography.badge.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Daily Quota',
                          style: AppTypography.bodyMedium.copyWith(
                            color: isDark ? AppColors.darkText : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${usedSecs}s / 120s used',
                          style: AppTypography.caption.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: isDark ? const Color(0xFF262C34) : const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isExhausted
                              ? AppColors.error
                              : (remainingSecs <= 30 ? AppColors.warning : AppColors.success),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isExhausted
                              ? 'Quota exhausted for today'
                              : '$remainingSecs seconds remaining',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isExhausted
                                ? AppColors.error
                                : (isDark ? AppColors.darkText : AppColors.textPrimary),
                          ),
                        ),
                        Text(
                          'Resets at midnight',
                          style: AppTypography.caption.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Connection Test & Diagnostics
              Text(
                'SERVICE DIAGNOSTICS',
                style: AppTypography.badge.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test ZeroGPU Connection',
                      style: AppTypography.bodyMedium.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Verifies handshake with Hugging Face ZeroGPU endpoint.',
                      style: AppTypography.secondary.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _testSuccess
                              ? (isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7))
                              : (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _testSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                              size: 16,
                              color: _testSuccess ? AppColors.success : AppColors.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _testResult!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _testSuccess
                                      ? (isDark ? const Color(0xFFBBF7D0) : const Color(0xFF166534))
                                      : (isDark ? const Color(0xFFFECACA) : const Color(0xFF991B1B)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    PrimaryButton(
                      label: _isTestingConnection ? 'Testing Handshake...' : 'Test Connection',
                      icon: _isTestingConnection ? null : Icons.network_check_rounded,
                      width: double.infinity,
                      onPressed: _isTestingConnection ? null : _testConnection,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkText : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
