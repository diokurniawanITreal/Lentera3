import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../core/theme/app_colors.dart';
import '../state/lentera_controller.dart';
import '../state/lentera_state.dart';
import 'widgets/brand_assets.dart';
import 'widgets/loading_shape.dart';
import 'widgets/status_indicator.dart';
import 'widgets/voice_orb.dart';

/// Layar Mode Dasar dan Mode AI. Seluruh layar adalah satu area interaksi:
///  * sentuh        -> mendengarkan kembali (saat tidak mendengarkan)
///  * geser kiri    -> Mode Dasar -> Mode AI
///  * geser kanan   -> Mode AI -> Mode Dasar
///  * tekan-tahan   -> hentikan pembacaan lalu dengarkan
/// Semua aksi juga tersedia sebagai aksi semantik (menu aksi TalkBack/
/// VoiceOver) dan lewat perintah suara.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final LenteraController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _velocity = 300.0;

  static const _toAi = CustomSemanticsAction(label: 'Buka Mode AI');
  static const _toBasic = CustomSemanticsAction(label: 'Buka Mode Dasar');
  static const _listen = CustomSemanticsAction(label: 'Mulai mendengarkan');
  static const _stop = CustomSemanticsAction(label: 'Hentikan dan dengarkan');

  LenteraController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.onHomeReady());
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v <= -_velocity) {
      c.onSwipeLeft();
    } else if (v >= _velocity) {
      c.onSwipeRight();
    } // gestur lain: tidak mengubah status
  }

  String _semanticLabel() {
    final mode = c.mode == AppMode.ai ? 'Mode AI' : 'Mode Dasar';
    return '$mode. ${StatusIndicator.label(c.status).replaceAll('...', '')}.';
  }

  String? _semanticHint() {
    switch (c.status) {
      case VoiceStatus.idle:
        return 'Ketuk dua kali untuk mulai mendengarkan. '
            '${c.mode == AppMode.basic ? 'Geser kiri' : 'Geser kanan'} '
            'untuk pindah mode.';
      case VoiceStatus.speaking:
      case VoiceStatus.processing:
        return 'Tekan dan tahan untuk menghentikan lalu mendengarkan.';
      case VoiceStatus.listening:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final actions = <CustomSemanticsAction, VoidCallback>{
          if (c.mode == AppMode.basic) _toAi: () => c.switchMode(AppMode.ai),
          if (c.mode == AppMode.ai)
            _toBasic: () => c.switchMode(AppMode.basic),
          if (c.status == VoiceStatus.idle) _listen: c.onTap,
          if (c.status == VoiceStatus.speaking ||
              c.status == VoiceStatus.processing)
            _stop: c.interrupt,
        };

        return Scaffold(
          body: Semantics(
            container: true,
            label: _semanticLabel(),
            hint: _semanticHint(),
            button: c.status == VoiceStatus.idle,
            onTap: c.status == VoiceStatus.idle ? c.onTap : null,
            onLongPress: c.interrupt,
            customSemanticsActions: actions,
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: c.onTap,
                onLongPress: c.onLongPress,
                onHorizontalDragEnd: _onDragEnd,
                child: SafeArea(child: _Body(controller: c)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});
  final LenteraController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isAi = c.mode == AppMode.ai;
    final answerLayout = isAi &&
        c.status == VoiceStatus.speaking &&
        c.question.isNotEmpty;

    if (answerLayout) return _AnswerLayout(controller: c);
    return _VoiceLayout(controller: c, isAi: isAi);
  }
}

class _ModeLabel extends StatelessWidget {
  const _ModeLabel(this.isAi);
  final bool isAi;

  @override
  Widget build(BuildContext context) => Text(
        isAi ? 'Mode AI' : 'Mode Dasar',
        style: Theme.of(context).textTheme.bodyMedium,
      );
}

/// Frame Figma: Mode Dasar (mendengarkan/memproses/berbicara) dan Mode AI
/// (mendengarkan/memproses).
class _VoiceLayout extends StatelessWidget {
  const _VoiceLayout({required this.controller, required this.isAi});
  final LenteraController controller;
  final bool isAi;

  Widget _centerpiece() {
    final s = controller.status;
    if (s == VoiceStatus.processing) {
      return SizedBox(
        width: 200,
        height: 200,
        child: Center(
          child: isAi ? const GeminiIcon(size: 52) : const LoadingShape(),
        ),
      );
    }
    if (s == VoiceStatus.speaking) {
      return const VoiceOrb(icon: Icons.volume_up, iconSize: 57);
    }
    return const VoiceOrb(icon: Icons.mic, iconSize: 60);
  }

  String _line() {
    final s = controller.status;
    if (s == VoiceStatus.processing) return '. . . . . . .';
    if (s == VoiceStatus.speaking) return '“${controller.answer}”';
    if (controller.transcript.isEmpty) return '';
    return '“${controller.transcript}”';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // Rasio jarak vertikal dari Figma (Mode Dasar / Mode AI).
    final g = isAi ? const [53, 53, 54, 105] : const [63, 102, 63, 124];

    return LayoutBuilder(
      builder: (context, cons) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: cons.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              child: Column(
                children: [
                  _ModeLabel(isAi),
                  Spacer(flex: g[0]),
                  if (isAi) ...[
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GeminiIcon(size: 40),
                        SizedBox(width: 12),
                        GeminiWordmark(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Apa yang sebaiknya kita fokuskan?',
                        textAlign: TextAlign.center, style: t.titleMedium),
                  ] else
                    Text('Selamat Datang di Lentera',
                        textAlign: TextAlign.center, style: t.displaySmall),
                  Spacer(flex: g[1]),
                  _centerpiece(),
                  Spacer(flex: g[2]),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 58),
                    child: Text(
                      _line(),
                      textAlign: TextAlign.center,
                      style: t.headlineSmall,
                    ),
                  ),
                  Spacer(flex: g[3]),
                  StatusIndicator(status: controller.status),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frame Figma "hasil Mode AI": gelembung pertanyaan + jawaban yang dapat
/// digulir.
class _AnswerLayout extends StatelessWidget {
  const _AnswerLayout({required this.controller});
  final LenteraController controller;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 44, 20, 32),
      child: Column(
        children: [
          const _ModeLabel(true),
          const SizedBox(height: 46),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 279),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.questionBubble,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.zero,
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Text(controller.question, style: t.bodyLarge),
            ),
          ),
          const SizedBox(height: 34),
          Expanded(
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(controller.answer, style: t.bodyLarge),
              ),
            ),
          ),
          const SizedBox(height: 16),
          StatusIndicator(status: controller.status),
        ],
      ),
    );
  }
}
