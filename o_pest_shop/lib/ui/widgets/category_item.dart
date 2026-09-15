import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/categoria.dart';

class CategoryItem extends StatelessWidget {
  final Categoria categoria;
  final VoidCallback? onTap;

  const CategoryItem({super.key, required this.categoria, this.onTap});

  IconData _getIcon() {
    final icone = categoria.icone?.toLowerCase();
    if (icone != null) {
      switch (icone) {
        case 'bolt_rounded':
          return Icons.bolt_rounded;
        case 'energy_savings_leaf_rounded':
          return Icons.energy_savings_leaf_rounded;
        case 'monitoring_rounded':
          return Icons.monitor_heart_outlined;
        case 'local_fire_department_rounded':
          return Icons.local_fire_department_rounded;
        case 'checkroom_rounded':
          return Icons.checkroom_rounded;
        case 'fitness_center_rounded':
          return Icons.storefront_rounded;
      }
    }
    switch (categoria.nome.toLowerCase()) {
      case 'proteína':
      case 'proteina':
      case 'whey':
        return Icons.bolt_rounded;
      case 'creatina':
        return Icons.energy_savings_leaf_rounded;
      case 'hipercalóricos':
      case 'hipercaloricos':
      case 'mass gainer':
        return Icons.monitor_heart_outlined;
      case 'pré-treino':
      case 'pre-treino':
      case 'pre treino':
        return Icons.local_fire_department_rounded;
      case 'roupas':
      case 'roupa':
        return Icons.checkroom_rounded;
      case 'equipamentos':
      case 'equipamento':
        return Icons.shopping_bag_rounded;
      case 'acessórios':
      case 'acessorios':
        return Icons.watch_rounded;
      case 'masculino':
        return Icons.male_rounded;
      case 'feminino':
        return Icons.female_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              _getIcon(),
              color: AppColors.primary,
              size: 32,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: 80,
            child: Text(
              categoria.nome,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.secondaryText,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

