import 'package:flutter/material.dart';

import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../services/streaming/streaming_storage.dart';
import '../streaming/streaming_widgets.dart';

class StreamingImageField extends StatefulWidget {
  final String label;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final double aspectRatio;
  final String folder;
  final IconData icon;

  const StreamingImageField({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.folder,
    this.aspectRatio = 16 / 9,
    this.icon = Icons.image_outlined,
  });

  @override
  State<StreamingImageField> createState() => _StreamingImageFieldState();
}

class _StreamingImageFieldState extends State<StreamingImageField> {
  bool _enviando = false;

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      final url = await StreamingStorage.escolherEEnviarImagem(
        pasta: widget.folder,
      );
      if (url == null) return;
      if (widget.value.trim().isNotEmpty &&
          StreamingStorage.caminhoDoBucket(widget.value) != null) {
        await StreamingStorage.removerImagem(widget.value);
      }
      widget.onChanged(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _remover() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover imagem'),
        content: const Text(
          'A imagem será removida deste registro e do armazenamento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    await StreamingStorage.removerImagem(widget.value);
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.aspectRatio < 1;
    final larguraPreview = vertical ? 112.0 : 210.0;
    final alturaPreview = larguraPreview / widget.aspectRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          widget.hint,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ThemeColors.secondaryText(context),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: larguraPreview,
                height: alturaPreview,
                child: widget.value.trim().isEmpty
                    ? Container(
                        color: ThemeColors.surfaceVariant(context),
                        child: Icon(
                          widget.icon,
                          color: ThemeColors.hint(context),
                          size: 30,
                        ),
                      )
                    : StreamingNetworkImage(
                        url: widget.value,
                        memCacheWidth: 600,
                        fallbackIcon: widget.icon,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _enviando ? null : _enviar,
                      icon: _enviando
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_rounded, size: 17),
                      label: Text(_enviando ? 'Enviando...' : 'Enviar imagem'),
                    ),
                  ),
                  if (widget.value.trim().isNotEmpty)
                    TextButton.icon(
                      onPressed: _enviando ? null : _remover,
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Remover'),
                      style: TextButton.styleFrom(
                        foregroundColor: ThemeColors.error(context),
                      ),
                    ),
                  Text(
                    'JPG, PNG ou WebP • até 10 MB',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: ThemeColors.secondaryText(context),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class StreamingAdminSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const StreamingAdminSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ThemeColors.secondaryText(context),
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}

class StreamingStatusChip extends StatelessWidget {
  final String status;

  const StreamingStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final cor = switch (status) {
      'publicado' => ThemeColors.success(context),
      'agendado' => ThemeColors.warning(context),
      'arquivado' => ThemeColors.hint(context),
      _ => ThemeColors.secondaryText(context),
    };
    final label = switch (status) {
      'publicado' => 'Publicado',
      'agendado' => 'Agendado',
      'arquivado' => 'Arquivado',
      _ => 'Rascunho',
    };
    return StreamingBadge(label: label.toUpperCase(), color: cor);
  }
}
